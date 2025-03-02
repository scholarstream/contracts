// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IYieldVault {
    function deposit(uint256 amount) external returns (uint256 shares);
    function withdraw(uint256 shares) external returns (uint256 redeemed);
    function getPricePerShare() external view returns (uint256);
}

contract ScholarStreamYield is ReentrancyGuard {
    uint256 public constant SCALE = 1e18;

    // Streaming mappings.
    mapping(bytes32 => uint256) public streamToStart;         // time when stream started
    mapping(address => uint256) public totalPaidPerSec;        // streaming rate (tokens per second)
    mapping(address => uint256) public lastPayerUpdate;          // last timestamp for streaming update

    // Underlying funds.
    mapping(address => uint256) public directBalances;         // funds held directly in the contract
    mapping(address => uint256) public vaultShares;            // vault shares obtained from deposits
    mapping(address => uint256) public paidBalance;            // total streaming cost charged (locked in)

    IERC20 public immutable token;
    IYieldVault public immutable vault;

    event Deposit(address indexed payer, uint256 amount, uint256 percentToVault);
    event StreamCreated(address indexed from, address indexed to, uint256 amountPerSec, bytes32 streamId);
    event StreamCancelled(address indexed from, address indexed to, uint256 amountPerSec, bytes32 streamId);
    event Withdraw(address indexed from, address indexed to, uint256 amount, bytes32 streamId);
    event WithdrawPayer(address indexed payer, uint256 amount);
    event Rebalance(address indexed payer, uint256 directDelta, uint256 newVaultShares);

    constructor(address _token, address _vault) {
        token = IERC20(_token);
        vault = IYieldVault(_vault);
    }

    /// @notice Returns the effective balance of a payer.
    /// effectiveBalance = directBalances + (vaultShares * pricePerShare)/SCALE – paidBalance.
    function effectiveBalance(address payer) public view returns (uint256) {
        uint256 vaultValue = (vaultShares[payer] * vault.getPricePerShare()) / SCALE;
        // uint256 _effectiveBalance = directBalances[payer] + vaultValue - paidBalance[payer];
        uint256 _effectiveBalance = directBalances[payer] + vaultValue;
        return _effectiveBalance;
    }

    /// @notice Deposit tokens, splitting between vault and direct funds.
    /// percentToVault is the percentage of the deposit to route to the vault.
    function deposit(uint256 amount, uint256 percentToVault) external nonReentrant {
        require(percentToVault <= 100, "percentToVault must be <= 100");
        token.transferFrom(msg.sender, address(this), amount);
        uint256 vaultAmount = (amount * percentToVault) / 100;
        uint256 directAmount = amount - vaultAmount;

        if (vaultAmount > 0) {
            token.approve(address(vault), vaultAmount);
            uint256 sharesReceived = vault.deposit(vaultAmount);
            vaultShares[msg.sender] += sharesReceived;
        }
        if (directAmount > 0) {
            directBalances[msg.sender] += directAmount;
        }
        if (lastPayerUpdate[msg.sender] == 0) {
            lastPayerUpdate[msg.sender] = block.timestamp;
        }
        emit Deposit(msg.sender, amount, percentToVault);
    }

    /// @notice Create a streaming payment from msg.sender (payer) to a payee.
    function createStream(address payee, uint256 amountPerSec) external nonReentrant {
        require(amountPerSec > 0, "amountPerSec must be > 0");
        updatePayerBalances(msg.sender);
        bytes32 streamId = getStreamId(msg.sender, payee, amountPerSec);
        require(streamToStart[streamId] == 0, "Stream already exists");
        streamToStart[streamId] = block.timestamp;
        totalPaidPerSec[msg.sender] += amountPerSec;
        emit StreamCreated(msg.sender, payee, amountPerSec, streamId);
    }

    /// @notice Update streaming state by "charging" the elapsed cost.
    /// This function ONLY increases paidBalance (locking in cost) without subtracting funds.
    function updatePayerBalances(address payer) public {
        uint256 delta = block.timestamp - lastPayerUpdate[payer];
        uint256 totalNeedToPay = delta * totalPaidPerSec[payer];
        console.log("==================");
        console.log("delta: %d", delta);
        console.log("totalPaidPerSec: %d", totalPaidPerSec[payer]);
        console.log("effectiveBalance: %d", effectiveBalance(payer));
        console.log("totalNeedToPay: %d", totalNeedToPay);
        require(effectiveBalance(payer) >= totalNeedToPay, "Insufficient funds for stream");
        paidBalance[payer] += totalNeedToPay;
        lastPayerUpdate[payer] = block.timestamp;
    }

    /// @notice Internal function for streaming withdrawals.
    /// This function redeems the underlying funds corresponding to the accrued streaming cost.
    function _withdrawStream(address from, address to, uint256 amountPerSec) internal {
        bytes32 streamId = getStreamId(from, to, amountPerSec);
        require(streamToStart[streamId] != 0, "Stream doesn't exist");
        updatePayerBalances(from);
        uint256 delta = lastPayerUpdate[from] - streamToStart[streamId];
        streamToStart[streamId] = lastPayerUpdate[from];
        uint256 paymentDue = delta * amountPerSec;
        // At this point, paidBalance already increased by paymentDue.
        // Now, withdraw underlying funds from direct and vault funds.
        if (directBalances[from] >= paymentDue) {
            directBalances[from] -= paymentDue;
            token.transfer(to, paymentDue);
            emit Withdraw(from, to, paymentDue, streamId);
        } else {
            uint256 toTransferDirect = directBalances[from];
            directBalances[from] = 0;
            token.transfer(to, toTransferDirect);
            uint256 remaining = paymentDue - toTransferDirect;
            uint256 pricePerShare = vault.getPricePerShare();
            uint256 sharesNeeded = (remaining * SCALE) / pricePerShare;
            require(vaultShares[from] >= sharesNeeded, "Not enough vault shares");
            vaultShares[from] -= sharesNeeded;
            uint256 redeemed = vault.withdraw(sharesNeeded);
            token.transfer(to, redeemed);
            emit Withdraw(from, to, toTransferDirect + redeemed, streamId);
        }
    }

    /// @notice External function for payee withdrawal.
    function withdraw(address payer, address payee, uint256 amountPerSec) external nonReentrant {
        _withdrawStream(payer, payee, amountPerSec);
    }

    /// @notice Cancel stream: withdraw accrued streaming funds, cancel the stream, and reduce the streaming rate.
    function cancelStream(address payee, uint256 amountPerSec) external nonReentrant {
        _withdrawStream(msg.sender, payee, amountPerSec);
        bytes32 streamId = getStreamId(msg.sender, payee, amountPerSec);
        streamToStart[streamId] = 0;
        unchecked {
            totalPaidPerSec[msg.sender] -= amountPerSec;
        }
        emit StreamCancelled(msg.sender, payee, amountPerSec, streamId);
    }

    /// @notice Payer withdraws remaining unstreamed funds.
    /// This function redeems funds from direct and/or vault portions to satisfy the withdrawal.
    function withdrawPayer(uint256 amount) external nonReentrant {
        require(effectiveBalance(msg.sender) >= amount, "Insufficient principal");
        if (directBalances[msg.sender] >= amount) {
            directBalances[msg.sender] -= amount;
            token.transfer(msg.sender, amount);
            emit WithdrawPayer(msg.sender, amount);
        } else {
            uint256 toWithdrawDirect = directBalances[msg.sender];
            directBalances[msg.sender] = 0;
            token.transfer(msg.sender, toWithdrawDirect);
            uint256 remaining = amount - toWithdrawDirect;
            uint256 pricePerShare = vault.getPricePerShare();
            uint256 sharesNeeded = (remaining * SCALE) / pricePerShare;
            require(vaultShares[msg.sender] >= sharesNeeded, "Not enough vault shares");
            vaultShares[msg.sender] -= sharesNeeded;
            uint256 redeemed = vault.withdraw(sharesNeeded);
            token.transfer(msg.sender, redeemed);
            emit WithdrawPayer(msg.sender, toWithdrawDirect + redeemed);
        }
        // Note: We do NOT modify paidBalance here because streaming cost is already locked in.
    }

    /// @notice Rebalance funds between direct and vault portions to achieve a target vault ratio.
    /// targetRatio: target percentage (0-100) of effective balance that should reside in the vault.
    function rebalance(uint256 targetRatio) external nonReentrant {
        require(targetRatio <= 100, "Invalid target ratio");
        uint256 vaultValue = (vaultShares[msg.sender] * vault.getPricePerShare()) / SCALE;
        uint256 directValue = directBalances[msg.sender];
        uint256 totalEffective = directValue + vaultValue;
        if (totalEffective == 0) return;
        uint256 currentVaultRatio = (vaultValue * 100) / totalEffective;

        if (currentVaultRatio > targetRatio) {
            // Too much in vault: redeem a portion to direct funds.
            uint256 excessPercent = currentVaultRatio - targetRatio;
            uint256 excessAmount = (excessPercent * totalEffective) / 100;
            uint256 sharesToWithdraw = (excessAmount * SCALE) / vault.getPricePerShare();
            require(vaultShares[msg.sender] >= sharesToWithdraw, "Not enough vault shares for rebalance");
            vaultShares[msg.sender] -= sharesToWithdraw;
            uint256 redeemed = vault.withdraw(sharesToWithdraw);
            directBalances[msg.sender] += redeemed;
            emit Rebalance(msg.sender, redeemed, vaultShares[msg.sender]);
        } else if (currentVaultRatio < targetRatio) {
            // Too little in vault: deposit some direct funds into vault.
            uint256 shortagePercent = targetRatio - currentVaultRatio;
            uint256 shortageAmount = (shortagePercent * totalEffective) / 100;
            require(directBalances[msg.sender] >= shortageAmount, "Not enough direct funds for rebalance");
            directBalances[msg.sender] -= shortageAmount;
            token.approve(address(vault), shortageAmount);
            uint256 sharesReceived = vault.deposit(shortageAmount);
            vaultShares[msg.sender] += sharesReceived;
            emit Rebalance(msg.sender, shortageAmount, vaultShares[msg.sender]);
        }
    }

    /// @notice Helper: computes a unique stream identifier.
    function getStreamId(address from, address to, uint256 amountPerSec) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, amountPerSec));
    }
}
