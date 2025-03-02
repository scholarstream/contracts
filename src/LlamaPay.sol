// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {console} from "forge-std/Test.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract LlamaPay is ReentrancyGuard {
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

    IERC20 public immutable token;

    // Constant for checking potential overflow on streaming amounts.
    uint256 private constant RATE_LIMIT_DENOMINATOR = 10_000_000_000 * 1_000 * 365 days * 1_000_000_000;

    event Deposit(address indexed payer, uint256 amount);
    event StreamCreated(address indexed from, address indexed to, uint256 amountPerSec, bytes32 streamId);
    event StreamCancelled(address indexed from, address indexed to, uint256 amountPerSec, bytes32 streamId);
    event Withdraw(address indexed from, address indexed to, uint256 amount, bytes32 streamId);
    event WithdrawPayer(address indexed payer, uint256 amount);

    constructor(address _token) {
        token = IERC20(_token);
    }

    /// @notice Computes a unique stream identifier.
    function getStreamId(
        address from,
        address to,
        uint256 amountPerSec
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(from, to, amountPerSec));
    }

    /// @dev Updates the payer’s balances by subtracting streamed amount and crediting the paid balance.
    function updateBalances(address payer) private {
        uint256 delta = block.timestamp - lastPayerUpdate[payer];
        uint256 totalPaid = delta * totalPaidPerSec[payer];
        require(balances[payer] >= totalPaid, "Insufficient funds for stream");

        balances[payer] -= totalPaid;
        paidBalance[payer] += totalPaid;
        lastPayerUpdate[payer] = block.timestamp;
    }

    /// @notice Deposits tokens into the contract.
    function deposit(uint256 amount) external nonReentrant {
        token.transferFrom(msg.sender, address(this), amount);
        balances[msg.sender] += amount;
        if (lastPayerUpdate[msg.sender] == 0) {
            lastPayerUpdate[msg.sender] = block.timestamp;
        }
        emit Deposit(msg.sender, amount);
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

    /// @dev Internal withdrawal logic (without nonReentrant) that both withdraw and cancelStream can use.
    function _withdraw(
        address from,
        address to,
        uint256 amountPerSec
    ) internal {
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

    /// @notice Withdraws streamed funds from a payer to a payee.
    function withdraw(
        address from,
        address to,
        uint256 amountPerSec
    ) public nonReentrant {
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
        token.transfer(msg.sender, amount);
        emit WithdrawPayer(msg.sender, amount);
    }
}
