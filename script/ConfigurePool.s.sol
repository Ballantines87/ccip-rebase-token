// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/src/v0.8/ccip/libraries/RateLimiter.sol";

contract ConfigureTokenPool is Script {
    function run(
        address _localPoolAddress,
        uint64 _remoteChainSelector,
        address _remotePoolAddress,
        address _remoteTokenAddress,
        bool _outboundRateLimiterIsEnabled,
        uint128 _outboundRateLimiterCapacity,
        uint128 _outboundRateLimiterRate,
        bool _inboundRateLimiterIsEnabled,
        uint128 _inboundRateLimiterCapacity,
        uint128 _inboundRateLimiterRate
    ) external {
        vm.startBroadcast();
        TokenPool.ChainUpdate[]
            memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        bytes memory remotePoolAddress = abi.encode(_remotePoolAddress);
        bytes memory remoteTokenAddress = abi.encode(_remoteTokenAddress);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: _remoteChainSelector,
            allowed: true,
            remotePoolAddress: remotePoolAddress,
            remoteTokenAddress: remoteTokenAddress,
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: _outboundRateLimiterIsEnabled,
                capacity: _outboundRateLimiterCapacity, // this is the max amount of tokens that can be sent in a single transaction
                rate: _outboundRateLimiterRate // this is the rate at which the tokens are replenished - so, e.g., 100k tokens per second
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: _inboundRateLimiterIsEnabled,
                capacity: _inboundRateLimiterCapacity, // this is the max amount of tokens that can be sent in a single transaction
                rate: _inboundRateLimiterRate // this is the rate at which the tokens are replenished
            })
        });

        TokenPool(_localPoolAddress).applyChainUpdates(chainsToAdd);
        vm.stopBroadcast();
    }
}
