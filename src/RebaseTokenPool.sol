// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TokenPool} from "@ccip/contracts/src/v0.8/ccip/pools/TokenPool.sol";
import {IERC20} from "@ccip/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {Pool} from "@ccip/contracts/src/v0.8/ccip/libraries/Pool.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    constructor(
        IERC20 _token,
        address[] memory _allowList, // the allowList is the people you are allowed to send tokens to cross-chain. usually it's anyone (so we leave this to be an empty array) but you can restrict it to a few addresses (e.g. kinda like a whitelist) if you want
        address _rmn, // the RMN contract address is the Risk Management Network -> which is just the decentralized oracle network where they check that nothing malicious is happening witht the cross-chain transfer (e.g. double spending, etc)
        address _router // the router is the main smart contract that handles the cross-chain transfer logic and with which the users are going to be interacting with CCIP. There's going to be one deployed on every single chain.
    ) TokenPool(_token, _allowList, _rmn, _router) {}

    function lockOrBurn(
        Pool.LockOrBurnInV1 calldata lockOrBurnIn
    ) external override returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut) {
        // this is called inside the lockOrBurn function -> because this is where the risk management network (RMN) checks happen and all validation occurs, to make sure our cross-chain mesages are secure -> so if this fails, the whole transaction reverts
        _validateLockOrBurn(lockOrBurnIn);

        // if we need to send some extra data to the destination chain, we can do it here -> and in the case of our rebase token, we need to be able to calculate the amount of tokens and how much interest they are earning -> so we need to calculate the user's interest rate -> and we can use that helpful getUserInterestRate() function that we created in our RebaseToken contract

        address receiver = abi.decode(lockOrBurnIn.receiver, (address)); // we need to decode the receiver because it's in bytes format - which means that it has been previously encoded via abi.encode() into bytes -> so we call abi.decode() to get the original address back

        uint256 userInterestRate = IRebaseToken(address(i_token))
            .getUserInterestRate(receiver);

        // now that we got the user's interest rate we can go ahead and burn our tokens
        // N.B. notice that we do .burn(address(this),...) -> because the way this CCIP works is 1) first the user does a token approval 2) then they send the tokens to CCIP 3) and then the CCIP will send to the Token Pool contract -> So actually it needs to be address(this) because the tokens are sent in the Token Pool contract when it is doing the cross-chain transfers -> which is why, when we do the cross-chain transfers - in our script and in our tests - we will need to approve the router for the amount of tokens that we wanna send cross-chain - hence the Token Pool contract (aka address(this)) is the one that needs to burn them
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);
    }

    function releaseOrMint(
        Pool.ReleaseOrMintInV1 calldata releaseOrMintIn
    ) external override returns (Pool.ReleaseOrMintOutV1 memory) {
        // this is called inside the releaseOrMint function -> because this is where the risk management network (RMN) checks happen and all validation occurs, to make sure our cross-chain mesages are secure -> so if this fails, the whole transaction reverts
        _validateReleaseOrMint(releaseOrMintIn);
    }
}
