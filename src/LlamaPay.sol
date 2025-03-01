// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Adapter.sol";
import {console} from "forge-std/Test.sol";

contract LlamaPay {
    mapping(bytes32 => uint256) public streamToStart;
    mapping(address => uint256) public totalPaidPerSec;
    mapping(address => uint256) public lastPayerUpdate;
    mapping(address => uint256) public balances;
    mapping(address => uint256) public yieldEarnedPerToken;
    mapping(address => uint256) public paidBalance;
    mapping(address => uint256) public lastPricePerShare;

    IERC20 immutable public token;
    address immutable public vault;
    address immutable public adapter;

    constructor(address _token, address _adapter, address _vault) {
        token = IERC20(_token);
        adapter = _adapter;
        vault = _vault;

        _refreshSetup(_adapter, _token, _vault);
    }

    function getStreamId(address from, address to, uint256 amountPerSec) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, amountPerSec));
    }

    function getPricePerShare() private view returns (uint256) {
        return Adapter(adapter).pricePerShare(vault);
    }

    function updateBalances(address payer) private {
        uint256 delta = block.timestamp - lastPayerUpdate[payer];
    
        uint256 totalPaid = delta * totalPaidPerSec[payer];
        balances[payer] -= totalPaid;
        lastPayerUpdate[payer] = block.timestamp;
    
        uint256 lastPrice = lastPricePerShare[payer];
        uint256 currentPrice = getPricePerShare();
    
        if (lastPrice == 0) {
            lastPrice = currentPrice;
        }
    
        if (currentPrice >= lastPrice) {
            // Adjust balance based on price change
            balances[payer] = balances[payer] * currentPrice / lastPrice;
    
            // Calculate profits on new paid tokens
            uint256 profitsFromPaid = (totalPaid * currentPrice / lastPrice - totalPaid) / 2;
            balances[payer] += profitsFromPaid;
    
            // Calculate yield on the coins already paid
            uint256 yieldOnOldCoins = paidBalance[payer] * currentPrice / lastPrice - paidBalance[payer];
    
            // Only update yieldEarnedPerToken if paidBalance is non-zero
            if (paidBalance[payer] > 0) {
                yieldEarnedPerToken[payer] += (profitsFromPaid + yieldOnOldCoins) / paidBalance[payer];
            }
            
            // Update paidBalance with the newly computed values and totalPaid
            paidBalance[payer] += yieldOnOldCoins + profitsFromPaid + totalPaid;
            lastPricePerShare[payer] = currentPrice;
        }
    }

    function createStream(address to, uint256 amountPerSec) public {
        bytes32 streamId = getStreamId(msg.sender, to, amountPerSec);

        // this checks that even if:
        // - token has 18 decimals
        // - each person earns 10B / year
        // - each person will be earning for 1000 years
        // - there are 1B people earning (requires 1B txs)
        // there won't be an overflow in all those 1k years
        // checking for overflow is important because if there's an overflow later money will be stuck forever as all txs will revert
        unchecked {
            require(amountPerSec < type(uint256).max / (10e9 * 1e3 * 365 days * 1e9), "no overflow");
        }

        require(amountPerSec > 0, "amountPerSec must be positive"); 
        require(streamToStart[streamId] == 0, "stream already exists");

        streamToStart[streamId] = block.timestamp;
        updateBalances(msg.sender); // can't create a new stream unless there's no debt
        totalPaidPerSec[msg.sender] += amountPerSec;
    }

    function cancelStream(address to, uint256 amountPerSec) public {
        withdraw(msg.sender, to, amountPerSec);
        bytes32 streamId = getStreamId(msg.sender, to, amountPerSec);
        streamToStart[streamId] = 0;
        unchecked {
            totalPaidPerSec[msg.sender] -= amountPerSec;
        }
    }

    // make it possible to withdraw on behalf of others, important for people that don't have a metamask wallet e.g cex address
    function withdraw(address from, address to, uint256 amountPerSec) public {
        bytes32 streamId = getStreamId(from, to, amountPerSec);
        require(streamToStart[streamId] != 0, "stream doesn't exist");

        uint256 payerDelta = block.timestamp - lastPayerUpdate[from];
        uint256 totalPayerPayment = payerDelta * totalPaidPerSec[from];
        uint256 payerBalance = balances[from];

        if (payerBalance >= totalPayerPayment) {
            balances[from] -= totalPayerPayment;
            lastPayerUpdate[from] = block.timestamp;
        } else {
            // invariant: totalPaidPerSec[from] != 0
            unchecked {
                uint256 timePaid = payerBalance / totalPaidPerSec[from];
                lastPayerUpdate[from] += timePaid;

                // invariant: lastPayerUpdate[from] < block.timestamp
                balances[from] = payerBalance % totalPaidPerSec[from];
            }
        }

        uint256 lastUpdate = lastPayerUpdate[from];
        uint256 delta = lastUpdate - streamToStart[streamId];
        streamToStart[streamId] = lastUpdate;
        paidBalance[from] -= delta * amountPerSec;

        token.transfer(to, delta * amountPerSec);
    }

    function modify(address oldTo, uint256 oldAmountPerSec, address to, uint256 amountPerSec) public {
        cancelStream(oldTo, oldAmountPerSec);
        createStream(to, amountPerSec);
    }

    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        (bool success,) = adapter.delegatecall(
            abi.encodeWithSelector(Adapter.deposit.selector, vault, amount)
        );
        require(success, "deposit() failed");
        balances[msg.sender] += amount;
    }

    function withdrawPayer(uint256 amount) external {
        balances[msg.sender] -= amount;
        uint256 delta;
        unchecked {
            delta = block.timestamp - lastPayerUpdate[msg.sender];
        }
        require(delta * totalPaidPerSec[msg.sender] >= balances[msg.sender], "pls no rug");

        uint256 prevBalance = token.balanceOf(address(this));
        withdrawFromVault(amount / lastPricePerShare[msg.sender]);

        uint256 newBalance = token.balanceOf(address(this));
        token.transfer(msg.sender, newBalance - prevBalance);
    }

    function withdrawFromVault(uint256 amount) private {
        (bool success,) = adapter.delegatecall(
            abi.encodeWithSelector(Adapter.withdraw.selector, vault, amount)
        );
        require(success, "withdraw() failed");
    }

    function _refreshSetup(address _adapter, address _token, address _vault) internal {
        (bool success,) = _adapter.delegatecall(
            abi.encodeWithSelector(Adapter.refreshSetup.selector, _token, _vault)
        );
        require(success, "refreshSetup() failed");
    }

    function refreshSetup() public {
        _refreshSetup(adapter, address(token), vault);
    }

    // perform an arbitrary call
    // this will be under a heavy timelock and only used in case something goes very wrong e.g with yield engine
    // function emergencyAccess(address target, uint256 value, bytes memory callData) external onlyOwner {
    //     target.call{value: value}(callData);
    // }
}

