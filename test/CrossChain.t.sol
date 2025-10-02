// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

import {CCIPLocalSimulatorFork} from "../lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

contract CrossChainTest is Test {
    RebaseToken rebaseToken;
    RebaseTokenPool rebaseTokenPool;
    Vault vault;

    uint256 sepoliaFork;
    uint256 arbitrumSepoliaFork;

    // this is our CCIP simulator contract that will simulate the CCIP behavior for us - it will be deployed on both forks and will be used to send messages between the two forks.
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    function setUp() public {
        // "sepolia-eth" and "arb-sepolia" are ALIASES defined in foundry.toml inside rpc_endpoints with the respective RPC URLs stored in environment variables

        // also vm.createSelectFork Creates and selects a new fork from the given endpoint and returns the identifier of the fork.
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        arbitrumSepoliaFork = vm.createSelectFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        /* Each fork (createFork) has its own independent storage, which is also replaced when another fork is selected (selectFork). By default, only the test contract account and the caller are persistent across forks, which means that changes to the state of the test contract (variables) are preserved when different forks are selected. This way data can be shared by storing it in the contract's variables.
        However, with this vm.makePersistent(address) cheatcode, it is possible to mark the specified accounts as persistent, which means that their state is available regardless of which fork is currently active. */
        vm.makePersistent(address(ccipLocalSimulatorFork));
    }
}
