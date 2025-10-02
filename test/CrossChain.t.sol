// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";

import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

import {CCIPLocalSimulatorFork} from "../lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

contract CrossChainTest is Test {
    address OWNER = makeAddr("OWNER");

    RebaseToken sepoliaRebaseToken;
    RebaseToken arbSepoliaRebaseToken;

    RebaseTokenPool sepoliaRebaseTokenPool;
    RebaseTokenPool arbSepoliaRebaseTokenPool;

    // notice that the vault is deployed only on the source chain - sepolia
    // whereas the token contracts and the tokenPools contracts are deployed on both the source and the destination chains
    Vault vaultOnSepolia;

    uint256 sepoliaFork;
    uint256 arbSepoliaFork;

    // this is our CCIP simulator contract that will simulate the CCIP behavior for us - it will be deployed on both forks and will be used to send messages between the two forks.
    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    function setUp() public {
        /*//////////////////////////////////////////////////////////////
              step-by-step guide at docs.chain.link/ccip/tutorials
        //////////////////////////////////////////////////////////////*/

        // "sepolia-eth" and "arb-sepolia" are ALIASES defined in foundry.toml inside rpc_endpoints with the respective RPC URLs stored in environment variables

        // also vm.createSelectFork Creates AND Selects a new fork from the given endpoint and returns the identifier of the fork.
        sepoliaFork = vm.createSelectFork("sepolia-eth");

        // then we are JUST creating the arbitrumSepoliaFork here, but we are NOT selecting it yet
        arbSepoliaFork = vm.createFork("arb-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();

        /* Each fork (createFork) has its own independent storage, which is also replaced when another fork is selected (selectFork). By default, only the test contract account and the caller are persistent across forks, which means that changes to the state of the test contract (variables) are preserved when different forks are selected. This way data can be shared by storing it in the contract's variables.
        However, with this vm.makePersistent(address) cheatcode, it is possible to mark the specified accounts as persistent, which means that their state is available regardless of which fork is currently active. */

        // so this will allow us to use this ccipLocalSimulatorFork address on BOTH chains - sepolia and abr_sepolia.
        vm.makePersistent(address(ccipLocalSimulatorFork));

        /*//////////////////////////////////////////////////////////////
                                SEPOLIA CONFIG
        //////////////////////////////////////////////////////////////*/

        // here we need to select/switch to the sepolia fork
        // n.d.r. actually this is redundant because the sepolia fork is already selected by default after the first createSelectFork() call
        vm.selectFork(sepoliaFork);

        // 1) deploy and configure on sepolia
        vm.startPrank(OWNER);
        sepoliaRebaseToken = new RebaseToken();
        sepoliaRebaseTokenPool = new RebaseTokenPool(
            IERC20(address(sepoliaRebaseToken)),
            new address[](0),
            ccipLocalSimulatorFork
                .getNetworkDetails(sepoliaFork)
                .rmnProxyAddress,
            ccipLocalSimulatorFork.getNetworkDetails(sepoliaFork).routerAddress
        );

        vaultOnSepolia = new Vault(sepoliaRebaseToken);

        // 1.1) we need to grant the mint and burn role to the I) sepoliaRebaseTokenPool and II) the Vault contracts so that THEY can mint and burn tokens
        sepoliaRebaseToken.grantMintAndBurnRole(
            address(sepoliaRebaseTokenPool)
        );
        sepoliaRebaseToken.grantMintAndBurnRole(address(vaultOnSepolia));

        // 1.2) we claim and accept the admin role by calling the RegistryModuleOwnerCustom to register our EOA as the token admin, which is reequired to enable our token for cross-chain transfers, by calling the registerAdminViaOwner() function on the RegistryModuleOwnerCustom contract

        address sepoliaRegistryModuleOwnerCustomAddress = ccipLocalSimulatorFork
            .getNetworkDetails(sepoliaFork)
            .registryModuleOwnerCustomAddress;

        RegistryModuleOwnerCustom(sepoliaRegistryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaRebaseToken));

        // 1.3) now once claimed we call the TokenAdminRegistry contract's acceptAdminRole() function to finalize the registration process on sepolia

        address sepoliaTokenAdminRegistryAddress = ccipLocalSimulatorFork
            .getNetworkDetails(sepoliaFork)
            .tokenAdminRegistryAddress;

        TokenAdminRegistry(sepoliaTokenAdminRegistryAddress).acceptAdminRole(
            address(sepoliaRebaseToken)
        );

        // 1.4) now we need to LINK the token contract on sepolia to the corresponding token pool on sepolia by calling the setPool() function on the TokenAdminRegistry contract on sepolia

        TokenAdminRegistry(sepoliaTokenAdminRegistryAddress).setPool(
            address(sepoliaRebaseToken),
            address(sepoliaRebaseTokenPool)
        );

        vm.stopPrank();

        /*//////////////////////////////////////////////////////////////
                               ARB SEPOLIA CONFIG
        //////////////////////////////////////////////////////////////*/

        // here we need to switch to the arbitrum sepolia fork to make sure that the next deployments/interactions/etc... are done on the arbitrum sepolia chain
        vm.selectFork(arbSepoliaFork);

        // 2) deploy and configure on arbitrum sepolia
        vm.startPrank(OWNER);
        arbSepoliaRebaseToken = new RebaseToken();
        arbSepoliaRebaseTokenPool = new RebaseTokenPool(
            IERC20(address(arbSepoliaRebaseToken)),
            new address[](0),
            ccipLocalSimulatorFork
                .getNetworkDetails(arbSepoliaFork)
                .rmnProxyAddress,
            ccipLocalSimulatorFork
                .getNetworkDetails(arbSepoliaFork)
                .routerAddress
        );

        // 2.1) we need to grant the mint and burn role to the arbSepoliaRebaseTokenPool contract so that it can mint and burn tokens
        arbSepoliaRebaseToken.grantMintAndBurnRole(
            address(arbSepoliaRebaseTokenPool)
        );

        // 2.2) we claim and accept the admin role by calling the RegistryModuleOwnerCustom to register our EOA as the token admin, which is reequired to enable our token for cross-chain transfers, by calling the registerAdminViaOwner() function on the RegistryModuleOwnerCustom contract
        address arbRegistryModuleOwnerCustomAddress = ccipLocalSimulatorFork
            .getNetworkDetails(arbSepoliaFork)
            .registryModuleOwnerCustomAddress;

        RegistryModuleOwnerCustom(arbRegistryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(arbSepoliaRebaseToken));

        // 2.3) now once claimed we call the TokenAdminRegistry contract's acceptAdminRole() function to finalize the registration process on arb sepolia

        address arbSepoliaTokenAdminRegistryAddress = ccipLocalSimulatorFork
            .getNetworkDetails(arbSepoliaFork)
            .tokenAdminRegistryAddress;

        TokenAdminRegistry(arbSepoliaTokenAdminRegistryAddress).acceptAdminRole(
                address(arbSepoliaRebaseToken)
            );

        // 2.4) now we need to LINK the token contract on arbSepolia to the corresponding token pool on arbSepolia by calling the setPool() function on the TokenAdminRegistry contract on arbitrum sepolia

        TokenAdminRegistry(arbSepoliaTokenAdminRegistryAddress).setPool(
            address(arbSepoliaRebaseToken),
            address(arbSepoliaRebaseTokenPool)
        );

        vm.stopPrank();
    }
}
