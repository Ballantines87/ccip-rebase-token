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
import {Register} from "lib/chainlink-local/src/ccip/Register.sol";

import {CCIPLocalSimulatorFork} from "../lib/chainlink-local/src/ccip/CCIPLocalSimulatorFork.sol";

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";

contract CrossChainTest is Test {
    address OWNER = makeAddr("OWNER");
    address USER = makeAddr("USER");

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

        /*//////////////////////////////////////////////////////////////
                        CONFIGURING THE TOKEN POOLS
        //////////////////////////////////////////////////////////////*/

        // 3) AFTER we DEPLOYED ALL OF THEM, we need to configure BOTH Token Pools by calling the applyChainUpdates() function (which is inside the TokenPool, which we are inheriting by the RebaseTokenPool) and thus setting cross-chain transfers parameters such as: pool rate limits and enabled destionation chains -> we'll actually use the configureTokenPool() helper function below to do that.

        configureTokenPool(
            sepoliaFork,
            address(sepoliaRebaseTokenPool),
            ccipLocalSimulatorFork
                .getNetworkDetails(arbSepoliaFork)
                .chainSelector,
            address(arbSepoliaRebaseTokenPool),
            address(arbSepoliaRebaseToken)
        );

        configureTokenPool(
            arbSepoliaFork,
            address(arbSepoliaRebaseTokenPool),
            ccipLocalSimulatorFork.getNetworkDetails(sepoliaFork).chainSelector,
            address(sepoliaRebaseTokenPool),
            address(sepoliaRebaseToken)
        );

        vm.stopPrank();
    }

    // Helper function to configure the token pools on both chains
    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteToken
    ) public {
        // we're making sure we're working on the correct local fork - whether it's Sepolia or Arbitrum Sepolia t—hat we're working on
        vm.selectFork(fork);

        // this is goona be an array of 1 element of TokenPool.ChainUpdate structs - because we can update multiple chains at once - but in our case we're just updating one chain at a time - either sepolia or arbitrum sepolia - depending on which fork we're working on
        TokenPool.ChainUpdate[]
            memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        bytes memory remotePoolAddress = abi.encode(remotePool);
        bytes memory remoteTokenAddress = abi.encode(remoteToken);

        // struct ChainUpdate {
        //     uint64 remoteChainSelector; // ──╮ Remote chain selector
        //     bool allowed; // ────────────────╯ Whether the chain should be enabled
        //     bytes remotePoolAddress; //        Address of the remote pool, ABI encoded in the case of a remote EVM chain.
        //     bytes remoteTokenAddress; //       Address of the remote token, ABI encoded in the case of a remote EVM chain.
        //     RateLimiter.Config outboundRateLimiterConfig; // Outbound rate limited config, meaning the rate limits for all of the onRamps for the given chain
        //     RateLimiter.Config inboundRateLimiterConfig; // Inbound rate limited config, meaning the rate limits for all of the offRamps for the given chain
        //   };

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            allowed: true,
            remotePoolAddress: remotePoolAddress,
            remoteTokenAddress: remoteTokenAddress,
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false, // we are NOT enabling the rate limiter in this demo, however in production you should ALWAYS enable it to avoid DDOS attacks
                capacity: 0, // this is the max amount of tokens that can be sent in a single transaction
                rate: 0 // this is the rate at which the tokens are replenished - so, e.g., 100k tokens per second
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: false, // we are NOT enabling the rate limiter in this demo, however in production you should ALWAYS enable it to avoid DDOS attacks
                capacity: 0, // this is the max amount of tokens that can be sent in a single transaction
                rate: 0 // this is the rate at which the tokens are replenished
            })
        });

        vm.prank(OWNER);
        // here we need to pass the LOCAL Token Pool
        TokenPool(localPool).applyChainUpdates(chainsToAdd);
    }

    // the function that will allow us to bridge tokens from sepolia to arbitrum sepolia and vice versa
    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) public {
        // 1) first we select the fork that we're working on
        vm.selectFork(localFork);

        // 2) we need to create the message to send cross-chain (using Client.EVM2AnyMessage)

        // the array of tokens and their amounts that we're sending cross-chain - used inside Client.EVM2AnyMessage to construct the message
        Client.EVMTokenAmount[]
            memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: address(localToken), // token address on the local chain.
            amount: amountToBridge // Amount of tokens.
        });

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(USER), // we're sending the tokens to the USER address on the destination chain (we're assuming the address is the same on both chains)
            data: "", // we're not sending any extra data with this cross-chain transfer in this demo
            tokenAmounts: tokenAmounts, // the array of tokens and their amounts that we're sending cross-chain
            feeToken: localNetworkDetails.linkAddress, // we want to pay this in LINK tokens -> so we're going to use localNetworkDetails.linkAddress to get the LINK address
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // Populate this extraArgs with _argsToBytes(EVMExtraArgsV1)
        });

        // 3) now we can GET the FEES -> so we need to call the router contract -> we can get it from the localNetworkDetails.routerAddress -> but then we need to cast it to the correct interface - which is IRouterClient - so that we can call the getFee() function on it

        IRouterClient router = IRouterClient(localNetworkDetails.routerAddress);

        uint256 fee = router.getFee(
            remoteNetworkDetails.chainSelector, // The destination chainSelector
            message // The cross-chain CCIP message (aka Client.EVM2AnyMessage) including data and/or tokens
        );

        // N.B. we (as the USER) need to have some LINK tokens on the local chain to be able to PAY FOR THE FEES - so we're gonna use requestLinkFromFaucet(...) on our CCIPLocalSimulatorFork contract to request some LINK tokens from the faucet (it's kinda like vm.deal)
        bool linkTokensSuccessfullySentToUser = ccipLocalSimulatorFork
            .requestLinkFromFaucet(USER, 100e18); // 100 LINK

        if (!linkTokensSuccessfullySentToUser) {
            revert("Failed to get LINK tokens from the faucet");
        }

        // 4) we need (as the USER) to approve the router address to be able to spend the user's LINK tokens - so that it can pay for the fees
        vm.prank(USER);
        IERC20(localNetworkDetails.linkAddress).approve(
            localNetworkDetails.routerAddress,
            fee
        );

        // 5) we need (as the USER) to approve the router address to be able to spend the localTokens - so that it can pull the amountToBridge of tokens from the user

        vm.prank(USER);
        IERC20(address(localToken)).approve(
            localNetworkDetails.routerAddress,
            amountToBridge
        );

        // 6) now we can send the tokens cross-chain by calling the ccipSend() function on the router

        // BUT we also wanna make sure that all of the state is as expected -> so we want to i) get some balances and ii) do some assertions

        // 6.1) We want to get the localToken BALANCE BEFORE we do any cross-chain message ...
        uint256 localTokenBalanceBeforeBridging = localToken.balanceOf(USER);

        // 6.2) ... and then we send (as the USER) the message cross-chain by calling the ccipSend() function on the router ..

        vm.prank(USER);
        bytes32 messageId = router.ccipSend{value: fee}(
            remoteNetworkDetails.chainSelector, // The destination chain ID
            message // The cross-chain CCIP message including data and/or tokens
        );

        // 6.3) And we want to get the balance AFTER ...
        uint256 localTokenBalanceAfterBridging = localToken.balanceOf(USER);

        // ... and verify that's correctly decreased by amountToBridge
        assertEq(
            localTokenBalanceAfterBridging,
            localTokenBalanceBeforeBridging - amountToBridge
        );

        // 6.4) we get the INTEREST RATE of the user on the LOCAL chain BEFORE the transfer, as we'll later verify that's the SAME as the interest rate on the REMOTE chain AFTER the transfer
        uint256 userInterestRateOnLocalChain = RebaseToken(localToken)
            .getUserInterestRate(USER);

        // 7) now, since we're using chainlink-local to PRETEND that we're sending a CROSS-CHAIN message -> we actually need to make sure it propagates (and that's a funny little thing you have to do in the tests, when you're using chainlink-local and you're testing ccip)

        // 7.1) we go onto the other chain

        // 7.2) we get the initial balance on the remote chain (BEFORE the bridge)
        uint256 remoteTokenBalanceBeforeBridging = remoteToken.balanceOf(USER);

        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 20 minutes); // we warp the time by, e.g., 20 minutes, as it normally takes some time for the message to be propagated cross-chain
        vm.roll(block.number + 1); // we also roll the block number forward by 1 - otherwise the message won't be found

        // 7.3) now we get the message cross-chain, so that we can get the balance AFTER the cross-chain message
        // N.B: switchChainAndRouteMessage() will i) SWITCH to the remoteFork (but we already did it above, even it's redundant, to simulate the passage of time on the remote chain), ii) find the message by its ID, and iii) route it to the correct Token Pool contract on the remote chain
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);

        uint256 remoteTokenBalanceAfterBridging = remoteToken.balanceOf(USER);

        // 7.4) ... and we verify that's correctly increased by amountToBridge
        assertEq(
            remoteTokenBalanceAfterBridging,
            remoteTokenBalanceBeforeBridging + amountToBridge
        );

        // 7.5) we get the INTEREST RATE of the user on the REMOTE chain AFTER the transfer, as we'll verify then that's the SAME as the interest rate on the LOCAL chain before the transfer

        uint256 userInterestRateOnRemoteChain = RebaseToken(remoteToken)
            .getUserInterestRate(USER);

        // 7.6) Now we verify that the interest rate of the user on the remote chain, AFTER having bridged, is the SAME as the interest rate of the user on the source/local chain

        assertEq(userInterestRateOnRemoteChain, userInterestRateOnLocalChain);
    }
}
