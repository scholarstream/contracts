// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./ScholarStreamYield.sol";

contract ScholarStreamYieldFactory {
  mapping(uint256 => ScholarStreamYield) public payContractsArray;
  mapping(address => mapping(address => ScholarStreamYield))
    public payContracts;
  uint256 public payContractsArrayLength;

  event ScholarStreamCreated(
    address token,
    address vault,
    address scholarStream
  );

  function createPayContract(
    address _token,
    address _vault
  ) external returns (ScholarStreamYield newContract) {
    if (payContracts[_token][_vault] != ScholarStreamYield(address(0))) {
      revert("Pay contract already exists");
    }

    newContract = new ScholarStreamYield(_token, _vault);

    payContracts[_token][_vault] = newContract;
    payContractsArray[payContractsArrayLength] = newContract;

    unchecked {
      payContractsArrayLength++;
    }

    emit ScholarStreamCreated(_token, _vault, address(newContract));
  }

  function getPayContract(
    address _token,
    address _vault
  ) external view returns (ScholarStreamYield) {
    return payContracts[_token][_vault];
  }
}
