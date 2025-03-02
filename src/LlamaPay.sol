// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LlamaPay {
    // streamId => start time
    mapping(bytes32 => uint256) public streamToStart;
    // payer => total paid per second
    mapping(address => uint256) public totalPaidPerSec;
    // payer => last update time
    mapping(address => uint256) public lastPayerUpdate;
    // payer => deposited balance
    mapping(address => uint256) public balances;
    // payer => amount that has streamed (available for withdrawal)
    mapping(address => uint256) public paidBalance;

    IERC20 immutable public token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function getStreamId(address from, address to, uint256 amountPerSec) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, amountPerSec));
    }

    /// @dev Updates the payer’s balances.
    /// It subtracts the streamed amount from the payer’s deposited balance and credits it to paidBalance.
    function updateBalances(address payer) private {
        uint256 delta = block.timestamp - lastPayerUpdate[payer];
        uint256 totalPaid = delta * totalPaidPerSec[payer];
        
        // Ensure the payer has enough balance to cover streaming (should be true if streams are set up correctly)
        require(balances[payer] >= totalPaid, "Insufficient funds for stream");

        // Deduct streamed amount from principal
        balances[payer] -= totalPaid;
        // Credit streamed amount as available to withdraw
        paidBalance[payer] += totalPaid;
        // Update the last update time
        lastPayerUpdate[payer] = block.timestamp;
    }

    /// @notice User deposits tokens into the contract.
    function deposit(uint256 amount) external {
        token.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        // Initialize last update time if needed
        if (lastPayerUpdate[msg.sender] == 0) {
            lastPayerUpdate[msg.sender] = block.timestamp;
        }
    }

    /// @notice Creates a streaming payment from msg.sender to a recipient at a specified rate.
    function createStream(address to, uint256 amountPerSec) public {
        bytes32 streamId = getStreamId(msg.sender, to, amountPerSec);
        require(amountPerSec > 0, "amountPerSec must be positive"); 
        require(streamToStart[streamId] == 0, "stream already exists");

        // Check for overflow on future streaming amounts.
        unchecked {
            require(amountPerSec < type(uint256).max / (10e9 * 1e3 * 365 days * 1e9), "no overflow");
        }

        // Update balances first so that the streamed amount is accounted for
        updateBalances(msg.sender);
        streamToStart[streamId] = block.timestamp;
        totalPaidPerSec[msg.sender] += amountPerSec;
    }

    /// @notice Cancels an active stream and triggers an immediate withdrawal for the stream amount.
    function cancelStream(address to, uint256 amountPerSec) public {
        withdraw(msg.sender, to, amountPerSec);
        bytes32 streamId = getStreamId(msg.sender, to, amountPerSec);
        streamToStart[streamId] = 0;
        unchecked {
            totalPaidPerSec[msg.sender] -= amountPerSec;
        }
    }

    /// @notice Withdraws the accumulated streamed funds from a payer to a payee.
    function withdraw(address from, address to, uint256 amountPerSec) public {
        bytes32 streamId = getStreamId(from, to, amountPerSec);
        require(streamToStart[streamId] != 0, "stream doesn't exist");

        // Update balances to account for streaming since the last update.
        updateBalances(from);

        uint256 lastUpdate = lastPayerUpdate[from];
        uint256 delta = lastUpdate - streamToStart[streamId];
        streamToStart[streamId] = lastUpdate;

        uint256 paymentDue = delta * amountPerSec;
        require(paidBalance[from] >= paymentDue, "Insufficient funds in paid balance");
        paidBalance[from] -= paymentDue;

        token.transfer(to, paymentDue);
    }

    /// @notice Allows the payer to withdraw any remaining unstreamed funds.
    function withdrawPayer(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient principal balance");
        balances[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
    }
}

