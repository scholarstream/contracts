// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./LlamaPay.sol";

contract LlamaPayFactory {
    mapping(address => LlamaPay) public payContracts;
    mapping(uint256 => LlamaPay) public payContractsArray;
    uint256 public payContractsArrayLength;

    event LlamaPayCreated(address token, address llamaPay);

    function createPayContract(address _token) external returns (LlamaPay newContract) {
        newContract = new LlamaPay(_token);

        payContracts[_token] = newContract;
        payContractsArray[payContractsArrayLength] = newContract;

        unchecked {
            payContractsArrayLength++;
        }

        emit LlamaPayCreated(_token, address(newContract));
    }

    function getPayContract(address _token) external view returns (LlamaPay) {
        return payContracts[_token];
    }
}

