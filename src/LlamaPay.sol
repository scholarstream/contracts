// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LlamaPay is ReentrancyGuard {
    /// @notice Mapping from stream identifier to the start timestamp.
    mapping(bytes32 => uint256) public streamToStart;

    /// @notice Mapping from payer to total streaming rate (amount per second).
    mapping(address => uint256) public totalPaidPerSec;

    /// @notice Mapping from payer to last update timestamp.
    mapping(address => uint256) public lastPayerUpdate;

    /// @notice Mapping from payer to deposited principal balance.
    mapping(address => uint256) public balances;

    /// @notice Mapping from payer to streamed amount available for withdrawal.
    mapping(address => uint256) public paidBalance;

    IERC20 public immutable token;

    // Constant for checking potential overflow on streaming rates.
    // This represents the maximum multiplier for a year's worth of streaming.
    uint256 private constant RATE_LIMIT_DENOMINATOR = 10_000_000_000 * 1_000 * 365 days * 1_000_000_000;

    /// @notice Emitted when a deposit is made.
    event Deposit(address indexed payer, uint256 amount);

    /// @notice Emitted when a streaming payment is created.
    event StreamCreated(
        address indexed from,
        address indexed to,
        uint256 amountPerSec,
        bytes32 streamId
    );

    /// @notice Emitted when a streaming payment is cancelled.
    event StreamCancelled(
        address indexed from,
        address indexed to,
        uint256 amountPerSec,
        bytes32 streamId
    );

    /// @notice Emitted when funds are withdrawn from a stream.
    event Withdraw(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes32 streamId
    );

    /// @notice Emitted when a payer withdraws unstreamed funds.
    event WithdrawPayer(address indexed payer, uint256 amount);

    /// @param _token Address of the ERC20 token used for streaming payments.
    constructor(address _token) {
        token = IERC20(_token);
    }

    /// @notice Computes a unique identifier for a payment stream.
    /// @param from The payer's address.
    /// @param to The recipient's address.
    /// @param amountPerSec The streaming rate (amount per second).
    /// @return The stream identifier as a bytes32 hash.
    function getStreamId(
        address from,
        address to,
        uint256 amountPerSec
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, amountPerSec));
    }

    /// @dev Updates the payer’s balances by subtracting the streamed amount from the principal
    /// balance and crediting it to the available (paid) balance.
    /// @param payer The address of the payer.
    function updateBalances(address payer) private {
        uint256 delta = block.timestamp - lastPayerUpdate[payer];
        uint256 totalPaid = delta * totalPaidPerSec[payer];

        require(balances[payer] >= totalPaid, "Insufficient funds for stream");

        balances[payer] -= totalPaid;
        paidBalance[payer] += totalPaid;
        lastPayerUpdate[payer] = block.timestamp;
    }

    /// @notice Deposits tokens into the contract.
    /// @param amount The amount of tokens to deposit.
    function deposit(uint256 amount) external nonReentrant {
        token.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        if (lastPayerUpdate[msg.sender] == 0) {
            lastPayerUpdate[msg.sender] = block.timestamp;
        }
        emit Deposit(msg.sender, amount);
    }

    /// @notice Creates a streaming payment from msg.sender to a recipient at a specified rate.
    /// @param to The recipient's address.
    /// @param amountPerSec The amount streamed per second.
    function createStream(address to, uint256 amountPerSec) external nonReentrant {
        require(amountPerSec > 0, "amountPerSec must be positive");
        bytes32 streamId = getStreamId(msg.sender, to, amountPerSec);
        require(streamToStart[streamId] == 0, "stream already exists");

        // Check for overflow on future streaming amounts.
        unchecked {
            require(amountPerSec < type(uint256).max / RATE_LIMIT_DENOMINATOR, "no overflow");
        }

        updateBalances(msg.sender);
        streamToStart[streamId] = block.timestamp;
        totalPaidPerSec[msg.sender] += amountPerSec;

        emit StreamCreated(msg.sender, to, amountPerSec, streamId);
    }

    /// @notice Withdraws the accumulated streamed funds from a payer to a payee.
    /// @param from The address of the payer.
    /// @param to The address of the recipient.
    /// @param amountPerSec The streaming rate of the stream.
    function withdraw(
        address from,
        address to,
        uint256 amountPerSec
    ) public nonReentrant {
        bytes32 streamId = getStreamId(from, to, amountPerSec);
        require(streamToStart[streamId] != 0, "stream doesn't exist");

        updateBalances(from);

        uint256 lastUpdate = lastPayerUpdate[from];
        uint256 delta = lastUpdate - streamToStart[streamId];
        streamToStart[streamId] = lastUpdate;

        uint256 paymentDue = delta * amountPerSec;
        require(paidBalance[from] >= paymentDue, "Insufficient funds in paid balance");
        paidBalance[from] -= paymentDue;

        token.transfer(to, paymentDue);

        emit Withdraw(from, to, paymentDue, streamId);
    }

    /// @notice Cancels an active stream and triggers an immediate withdrawal for the stream amount.
    /// @param to The recipient's address.
    /// @param amountPerSec The streaming rate of the stream.
    function cancelStream(address to, uint256 amountPerSec) external nonReentrant {
        withdraw(msg.sender, to, amountPerSec);
        bytes32 streamId = getStreamId(msg.sender, to, amountPerSec);
        streamToStart[streamId] = 0;
        unchecked {
            totalPaidPerSec[msg.sender] -= amountPerSec;
        }

        emit StreamCancelled(msg.sender, to, amountPerSec, streamId);
    }

    /// @notice Allows the payer to withdraw any remaining unstreamed funds.
    /// @param amount The amount to withdraw from the principal balance.
    function withdrawPayer(uint256 amount) external nonReentrant {
        require(balances[msg.sender] >= amount, "Insufficient principal balance");
        balances[msg.sender] -= amount;
        token.transfer(msg.sender, amount);
        emit WithdrawPayer(msg.sender, amount);
    }
}

