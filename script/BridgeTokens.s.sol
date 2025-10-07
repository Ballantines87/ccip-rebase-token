// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {Client} from "@ccip/contracts/src/v0.8/ccip/libraries/Client.sol";

// N.B. for some reason the router interface is called IRouterClient and not simply IRouter
import {IRouterClient} from "@ccip/contracts/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Register} from "lib/chainlink-local/src/ccip/Register.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

contract BridgeTokens is Script {
    function run(
        address _receiverAddress,
        address _tokenToSendAddress,
        uint256 _amountOfTokenToSend,
        uint64 _destinationChainSelector,
        address _linkTokenAddress,
        address _routerAddress
    ) external {
        vm.startBroadcast();

        Client.EVMTokenAmount[]
            memory _tokenAmounts = new Client.EVMTokenAmount[](1);

        _tokenAmounts[0] = Client.EVMTokenAmount({
            token: _tokenToSendAddress,
            amount: _amountOfTokenToSend
        });

        // 1) we need to create the message to send cross-chain (using Client.EVM2AnyMessage)
        // the array of tokens and their amounts that we're sending cross-chain - used inside Client.EVM2AnyMessage to construct the message

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiverAddress), // abi.encode(receiver address) for dest EVM chains
            data: "", // Data payload - we're not sending any data here
            tokenAmounts: _tokenAmounts, // Token transfers
            feeToken: _linkTokenAddress, // Address of feeToken - the $LINK address.
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0})) // that's the gas limit for receiving data -> but since we DON'T't have any data (see the data field which is ""), we can set this gasLimit to 0
        });

        // 2) now we can GET the FEES from the Router -> so we need to call the router contract -> we can get it from the routerAddress -> but then we need to cast it to the correct interface - which is IRouterClient - so that we can call the getFee() function on it

        IRouterClient router = IRouterClient(_routerAddress);
        uint256 ccipFee = router.getFee(_destinationChainSelector, message);

        // 3) The user (the caller?) approves LINK (with which, in this example, we'll pay our fees) for the router to be able to spend our fees for CCIP
        IERC20(_linkTokenAddress).approve(_routerAddress, ccipFee);

        // 4) The user (the caller?) approves RebaseToken for its associated pool - Approve the router to burn tokens on users behalf
        IERC20(address(_tokenAmounts[0].token)).approve(
            _routerAddress,
            _tokenAmounts[0].amount
        );

        // 5) now we can send the tokens cross-chain by calling the ccipSend() function on the router, by passing the chainSelector and the message
        IRouterClient(_routerAddress).ccipSend(
            _destinationChainSelector, // The destination chain ID
            message // The cross-chain CCIP message including data and/or tokens
        );

        vm.stopBroadcast();
    }
}
