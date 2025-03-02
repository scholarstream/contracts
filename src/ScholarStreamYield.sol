// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IYieldVault {
    function deposit(uint256 amount, address receiver) external returns (uint256 shares);
    function withdraw(uint256 shares, address receiver) external returns (uint256 amount);
    function pricePerShare() external view returns (uint256);
}

/// @title ScholarStreamYield
/// @notice A streaming contract that automatically deposits idle funds into a yield vault.
/// It tracks the vault shares corresponding to each payer's deposit.
contract ScholarStreamYield is ReentrancyGuard {
    // streamId => start time
    mapping(bytes32 => uint256) public streamToStart;
    // payer => total paid per second (in underlying token units)
    mapping(address => uint256) public totalPaidPerSec;
    // payer => last update time
    mapping(address => uint256) public lastPayerUpdate;
    // payer => principal (underlying token amount deposited)
    mapping(address => uint256) public balances;
    // payer => amount that has streamed (in underlying token units)
    mapping(address => uint256) public paidBalance;
    // payer => vault shares held on their behalf
    mapping(address => uint256) public vaultShares;

    IERC20 public immutable token;
    IYieldVault public immutable vault;

    // Constant for checking potential overflow on streaming amounts.
    uint256 private constant RATE_LIMIT_DENOMINATOR = 10_000_000_000 * 1_000 * 365 days * 1_000_000_000;

    event Deposit(address indexed payer, uint256 amount, uint256 sharesReceived);
    event StreamCreated(address indexed from, address indexed to, uint256 amountPerSec, bytes32 streamId);
    event StreamCancelled(address indexed from, address indexed to, uint256 amountPerSec, bytes32 streamId);
    event Withdraw(address indexed from, address indexed to, uint256 amount, bytes32 streamId);
    event WithdrawPayer(address indexed payer, uint256 amount);

    constructor(address _token, address _vault) {
        token = IERC20(_token);
        vault = IYieldVault(_vault);
    }

    /// @notice Computes a unique stream identifier.
    function getStreamId(address from, address to, uint256 amountPerSec) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, amountPerSec));
    }

    /// @dev Updates the payer’s balances by subtracting streamed amount and crediting the paid balance.
    function updateBalances(address payer) private {
        uint256 delta = block.timestamp - lastPayerUpdate[payer];
        uint256 totalPaid_ = delta * totalPaidPerSec[payer];
        require(balances[payer] >= totalPaid_, "Insufficient funds for stream");

        balances[payer] -= totalPaid_;
        paidBalance[payer] += totalPaid_;
        lastPayerUpdate[payer] = block.timestamp;
    }

    /// @notice Deposits tokens into the contract and routes them into the yield vault.
    function deposit(uint256 amount) external nonReentrant {
        // Transfer tokens from payer.
        token.transferFrom(msg.sender, address(this), amount);
        // Approve the vault.
        token.approve(address(vault), amount);
        // Deposit tokens into the vault; the scholar contract becomes the owner of the shares.
        uint256 sharesReceived = vault.deposit(amount, address(this));
        // Record the number of vault shares for this payer.
        vaultShares[msg.sender] += sharesReceived;
        // Record the underlying principal.
        balances[msg.sender] += amount;
        if (lastPayerUpdate[msg.sender] == 0) {
            lastPayerUpdate[msg.sender] = block.timestamp;
        }
        emit Deposit(msg.sender, amount, sharesReceived);
    }

    /// @notice Creates a streaming payment from msg.sender to a recipient.
    function createStream(address to, uint256 amountPerSec) external nonReentrant {
        require(amountPerSec > 0, "amountPerSec must be positive");
        bytes32 streamId = getStreamId(msg.sender, to, amountPerSec);
        require(streamToStart[streamId] == 0, "stream already exists");
        unchecked {
            require(amountPerSec < type(uint256).max / RATE_LIMIT_DENOMINATOR, "no overflow");
        }
        updateBalances(msg.sender);
        streamToStart[streamId] = block.timestamp;
        totalPaidPerSec[msg.sender] += amountPerSec;
        emit StreamCreated(msg.sender, to, amountPerSec, streamId);
    }

    /// @dev Internal function to redeem an underlying amount from the vault.
    /// It calculates how many shares are needed, reduces the payer's recorded vaultShares,
    /// and then calls the vault's withdraw.
    function _redeemFromVault(address payerAddress, uint256 underlyingAmount) internal returns (uint256 redeemed) {
        // Get current price per share.
        uint256 price = vault.pricePerShare(); // assumed scaled by 1e18
        // Calculate shares needed (rounding down).
        uint256 sharesNeeded = (underlyingAmount * 1e18) / price;
        require(vaultShares[payerAddress] >= sharesNeeded, "Not enough vault shares");
        vaultShares[payerAddress] -= sharesNeeded;
        redeemed = vault.withdraw(sharesNeeded, address(this));
    }

    /// @dev Internal withdrawal logic used for both payee withdrawal and stream cancellation.
    function _withdraw(address from, address to, uint256 amountPerSec) internal {
        bytes32 streamId = getStreamId(from, to, amountPerSec);
        require(streamToStart[streamId] != 0, "stream doesn't exist");
        updateBalances(from);
        uint256 lastUpdate = lastPayerUpdate[from];
        uint256 delta = lastUpdate - streamToStart[streamId];
        streamToStart[streamId] = lastUpdate;
        uint256 paymentDue = delta * amountPerSec;
        require(paidBalance[from] >= paymentDue, "Insufficient funds in paid balance");
        paidBalance[from] -= paymentDue;
        // Redeem the underlying amount from the vault.
        uint256 redeemed = _redeemFromVault(from, paymentDue);
        // Transfer redeemed tokens to the recipient.
        token.transfer(to, redeemed);
        emit Withdraw(from, to, redeemed, streamId);
    }

    /// @notice Withdraws streamed funds from a payer to a payee.
    function withdraw(address from, address to, uint256 amountPerSec) public nonReentrant {
        _withdraw(from, to, amountPerSec);
    }

    /// @notice Cancels an active stream and triggers an immediate withdrawal.
    function cancelStream(address to, uint256 amountPerSec) external nonReentrant {
        _withdraw(msg.sender, to, amountPerSec);
        bytes32 streamId = getStreamId(msg.sender, to, amountPerSec);
        streamToStart[streamId] = 0;
        unchecked {
            totalPaidPerSec[msg.sender] -= amountPerSec;
        }
        emit StreamCancelled(msg.sender, to, amountPerSec, streamId);
    }

    /// @notice Withdraws any remaining unstreamed principal funds for the payer.
    function withdrawPayer(uint256 amount) external nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient principal balance");
        balances[msg.sender] -= amount;
        // Redeem underlying tokens from the vault.
        uint256 redeemed = _redeemFromVault(msg.sender, amount);
        token.transfer(msg.sender, redeemed);
        emit WithdrawPayer(msg.sender, redeemed);
    }
}

