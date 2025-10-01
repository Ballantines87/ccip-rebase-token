// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "lib/ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";

contract RebaseTokenPool is TokenPool {
    constructor(
        IERC20 _token,
        address[] memory _allowList, // the allowList is the people you are allowed to send tokens to cross-chain. usually it's anyone (so we leave this to be an empty array) but you can restrict it to a few addresses (e.g. kinda like a whitelist) if you want
        address _rmn, // the RMN contract address is the Risk Management Network -> which is just the decentralized oracle network where they check that nothing malicious is happening witht the cross-chain transfer (e.g. double spending, etc)
        address _router // the router is the main smart contract that handles the cross-chain transfer logic and with which the users are going to be interacting with CCIP. There's going to be one deployed on every single chain.
    ) TokenPool(_token, _allowList, _rmn, _router) {}

    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) external override returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut) {}

    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) external override returns (Pool.ReleaseOrMintOutV1 memory) {}
}
