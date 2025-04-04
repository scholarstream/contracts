// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ScholarStream.sol";

contract ScholarStreamFactory {
  mapping(address => ScholarStream) public payContracts;
  mapping(uint256 => ScholarStream) public payContractsArray;
  uint256 public payContractsArrayLength;

  event ScholarStreamCreated(address token, address scholarStream);

  function createPayContract(
    address _token
  ) external returns (ScholarStream newContract) {
    newContract = new ScholarStream(_token);

    payContracts[_token] = newContract;
    payContractsArray[payContractsArrayLength] = newContract;

    unchecked {
      payContractsArrayLength++;
    }

    emit ScholarStreamCreated(_token, address(newContract));
  }

  function getPayContract(
    address _token
  ) external view returns (ScholarStream) {
    return payContracts[_token];
  }
}
