// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {LlamaPay} from "../src/LlamaPay.sol";
import {LlamaPayFactory} from "../src/LlamaPayFactory.sol";
import {MockToken} from "../src/mock/MockToken.sol";

contract FactoryTest is Test {
    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("arbitrum"));
    }

    function helper_deployAll(uint8 _tokenDecimals) internal returns (LlamaPayFactory, MockToken, LlamaPay) {
        MockToken mockToken = new MockToken(_tokenDecimals);

        LlamaPayFactory factory = new LlamaPayFactory();
        factory.createLlamaPayContract(address(mockToken));

        address llamaPayAddress = factory.getLlamaPayContractByIndex(0);
        LlamaPay llamaPay = LlamaPay(llamaPayAddress);

        return (factory, mockToken, llamaPay);
    }

    function test_CantCreateInstanceWithSameTokenMoreThanOne() public {
        (LlamaPayFactory factory, MockToken mockToken,) = helper_deployAll(18);

        vm.expectRevert();
        factory.createLlamaPayContract(address(mockToken));
    }

    function test_CreateWithArray() public {
        (LlamaPayFactory factory,,) = helper_deployAll(18);

        address[] memory tokens = new address[](3);
        tokens[0] = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8; // usdc
        tokens[1] = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1; // weth
        tokens[2] = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f; // wbtc

        // check if the contract is deployed
        for (uint256 i = 0; i < tokens.length; i++) {
            // check if the contract is deployed
            (, bool isDeployed) = factory.getLlamaPayContractByToken(tokens[i]);
            assertEq(isDeployed, false);

            // create a new LlamaPay contract for each token
            factory.createLlamaPayContract(tokens[i]);
        }

        // expect contract count to equal length + 1
        assertEq(factory.getLlamaPayContractCount(), tokens.length + 1);

        // check again if the contract is deployed
        for (uint256 i = 0; i < tokens.length; i++) {
            // check if the contract is deployed
            (, bool isDeployed) = factory.getLlamaPayContractByToken(tokens[i]);
            assertEq(isDeployed, true);
        }
    }
}
