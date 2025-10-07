// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {CCIPLocalSimulatorFork, Register} from "../lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

import {RegistryModuleOwnerCustom} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/src/v0.8/ccip/tokenAdminRegistry/TokenAdminRegistry.sol";

contract TokenAndPoolDeployer is Script {
    function run()
        external
        returns (RebaseTokenPool rebaseTokenPool, RebaseToken rebaseToken)
    {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork
            .getNetworkDetails(block.chainid);

        vm.startBroadcast();
        rebaseToken = new RebaseToken();
        rebaseTokenPool = new RebaseTokenPool(
            IERC20(address(rebaseToken)),
            new address[](0), // we leave the allowList empty -> so that anyone can send tokens cross-chain
            networkDetails.rmnProxyAddress, // RMN proxy address on local network (the script where this scsript is being run on)
            networkDetails.routerAddress // Router address on local network (the script where this scsript is being run on)
        );
        rebaseToken.grantMintAndBurnRole(address(rebaseTokenPool));

        RegistryModuleOwnerCustom registryModuleOwnerCustom = new RegistryModuleOwnerCustom(
                networkDetails.registryModuleOwnerCustomAddress
            );

        // n.b. whoever's calling this contract is going to be automatically the owner because they just deployed the token and the pool - so they are the owner ? of both contracts ?
        // we set the ccip admin via registerAdminViaOwner
        registryModuleOwnerCustom.registerAdminViaOwner(address(rebaseToken));

        // we get th address of the TokenAdminRegistry from the network details
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress)
            .acceptAdminRole(address(rebaseToken));

        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(
            address(rebaseToken),
            address(rebaseTokenPool)
        );

        vm.stopBroadcast();
        return (rebaseTokenPool, rebaseToken);
    }
}

// we're making a separate deployer for the vault because we wanna create it only on the source chain, not on the destination chain
contract VaultDeployer is Script {
    function run(address _rebaseTokenAddress) external returns (Vault vault) {
        vm.startBroadcast();
        vault = new Vault(IRebaseToken(_rebaseTokenAddress));
        IRebaseToken(_rebaseTokenAddress).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();

        return vault;
    }
}
