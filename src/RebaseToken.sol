// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/* Layout of the contract file: */
// version
// imports
// interfaces, libraries, contract

// Inside Contract:
// Errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive() function (if exists)
// fallback() function (if exists)
// external
// public
// internal
// private
// view & pure functions

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {AccessControl} from "../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

/**
 * @title Rebase Token
 * @author Paolo Montecchiani
 * @notice This is going to be a Rebase Cross-Chain Token that incentivisses users to deposit into a vault
 * @notice The interest rate in the smart contract can only decrease
 * Each user will have their own interest rate that is the glboal interest rate at the time of deposit
 */
contract RebaseToken is ERC20, Ownable, AccessControl, IRebaseToken {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error RebaseToken__InterestRateCanOnlyDecrease(
        uint256 previousInterestRate,
        uint256 newInterestRate
    );

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    // we're going to be working with 18 decimals precision - remember that we cannot work with decimals in solidity - e.g. 1.1 would be converted to 11 * 10^17

    // -------------------------------------------
    // ** this INTEREST RATE here below is actually an INTEREST RATE per UNIT OF TIME (per seconds) ** -> it's actually 5 PERCENT per SECOND!
    // --------------------------------------------
    uint256 private s_interestRate = 5e10; // so, in this case 5e10 represents 0.00000005

    uint256 private constant PRECISION_FACTOR = 1e18;

    // this is how it's done to create a specific role
    bytes32 private constant MINT_AND_BURN_ROLE =
        keccak256("MINT_AND_BURN_ROLE");

    mapping(address user => uint256 userInterestRate)
        private s_userTouserInterestRate;
    mapping(address user => uint256 lastUpdatedTimeStamp)
        private s_userTouserLastUpdatedTimestamp;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event InterestRateUpdated(uint256 indexed newInterestRate);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               Constructor
    //////////////////////////////////////////////////////////////*/

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                          External Functions
    //////////////////////////////////////////////////////////////*/

    function grantMintAndBurnRole(address _account) external onlyOwner {
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
     * @notice This function sets the interest rate in the contract
     * @param _newInterestRate the new interest rate that will be set
     * @dev The interest rate can only decrease
     */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // this check is because we said we want our interest rate here to only be able to decrease over time
        if (_newInterestRate > s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(
                s_interestRate,
                _newInterestRate
            );
        }

        s_interestRate = _newInterestRate;
        emit InterestRateUpdated(_newInterestRate);
    }

    /**
     * @notice this function is to mint tokens to the user when they deposit into the vault
     * @param _to the user to mint the tokens to
     * @param _amount the amount of tokens to mint
     */

    function mint(
        address _to,
        uint256 _amount,
        uint256 _userInterestRate
    ) external onlyRole(MINT_AND_BURN_ROLE) {
        // we want to FIRST mint the accrued interests (accrued up to this point and since the last time they performed any actions - minting, burning, transferring...) to the user, so that all of the state is up to date BEFORE they mint any new tokens
        _mintAccruedInterests(_to);
        // sets the interest rate for the user equal to the s_interest rate in the smart contract at the time they call mint()
        s_userTouserInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /**
     * @notice burns the user tokens when they withdraw from the vault
     * @notice this function is gonna be called when we transfer tokens cross-chain, because we are going to be creating a "burn and mint token mechanism" for bridging our tokens.
     * @notice we'll assume that this burn() function is ONLY going to be called when a user is redeeming their rewards and their deposit - so they would 1. go to some vault 2. they would call redeem with an amount and 3. then burn() would be called by that vault
     * @param _from the user to burn the tokens from
     * @param _amount the amount of tokens to burn
     */
    function burn(
        address _from,
        uint256 _amount
    ) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterests(_from);
        _burn(_from, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            Public Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice transfer tokens from one user to another
     * @param _recipient the user that will receive the tokens
     * @param _amount the amount transferred
     * @return true if the transfer was successful
     */

    function transfer(
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        _mintAccruedInterests(msg.sender);
        _mintAccruedInterests(_recipient);
        if (_amount == type(uint256).max) {
            _amount = balanceOf(msg.sender);
        }

        // if the _recipient doesn't have an interest rate yet (e.g. they haven't yet deposited), we want to set it equal to the msg.sender's interest rate
        if (s_userTouserInterestRate[_recipient] == 0) {
            s_userTouserInterestRate[_recipient] = s_userTouserInterestRate[
                msg.sender
            ];
        }

        return super.transfer(_recipient, _amount);
    }

    /**
     * @notice transfers tokens from one user to another
     * @param _sender the sender of the tokens
     * @param _recipient the recipient of the tokens
     * @param _amount the amount transferred
     * @return true if the transfer was successful
     */

    function transferFrom(
        address _sender,
        address _recipient,
        uint256 _amount
    ) public override returns (bool) {
        if (_amount == type(uint256).max) {
            _amount = balanceOf(_sender);
        }
        // accumulates the balance of the user so it is up to date with any interest accumulated.
        _mintAccruedInterests(_sender);
        _mintAccruedInterests(_recipient);
        if (balanceOf(_recipient) == 0) {
            // Update the users interest rate only if they have not yet got one (or they tranferred/burned all their tokens). Otherwise people could force others to have lower interest.
            s_userTouserInterestRate[_recipient] = s_userTouserInterestRate[
                _sender
            ];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                           Internal Functions
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            Private Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice mints the accrued interest to the user since the last time they interacted with the protocol (e.g. burn, mint, etc...)
     * @param _user the user to mint accrued tokens to
     * @dev follows the CEI pattern (Checks, Effects, Interactions)
     */

    function _mintAccruedInterests(address _user) internal {
        // (1) find the current balance of rebase tokens that have been minted to them (aka the principal balance)
        uint256 previousPrincipalBalance = super.balanceOf(_user);

        // (2) calculate their current balance including any interests (aka principal + interest) -> this will be returned by the balanceOf() function
        uint256 currentBalancePlusInterest = balanceOf(_user);

        // (3) calculate the number of tokens that need to be minted to the user -> which is calculated by doing (2) - (1) -> which gives us the number of tokens that need to be minted
        uint256 accruedTokensToMintToTheUser = currentBalancePlusInterest -
            previousPrincipalBalance;

        /* EFFECTS */
        // (4) we're going to set the user's last updated timestamp in _mintAccruedInterest()
        s_userTouserLastUpdatedTimestamp[_user] = block.timestamp;

        /* INTERACTIONS */
        // (5) and then we can call _mint() to mint the EXTRA tokens to the user
        // if (s_userTouserLastUpdatedTimestamp[_user] == 0) {
        //     _mint(_user, 0);
        // } else {
        //     _mint(_user, accruedTokensToMintToTheUser);
        // }

        _mint(_user, accruedTokensToMintToTheUser);
    }

    /**
     * @notice calculate the interest that has accumulated since the last update
     * @param _user The user to calculate the interest accumulated
     * @return linearInterest The interest rate that has accumulated since last update
     */
    function _calculateUserAccumulatedInterestSinceLastUpdate(
        address _user
    ) private view returns (uint256 linearInterest) {
        // we need to calculate the interest that has accumulated since the last update
        // this is going to be LINEAR GROWTH with TIME
        // (1) calculate the time since the last update
        // (2) calculate the amount of linear growth

        // e.g. if my deposit is 10 tokens
        // and my interest rate is 0.5 tokens per second
        // and time elapsed is 2 seconds
        // then the calculation is gonna be:
        // principalAmount + (principalAmount * interestRate * timeElapsed)
        // or principalAmount * (1 + (interestRate * timeElapsed))
        // 10 + (10 * 0.5 * 2) = 10 + 10 = 20

        uint256 timeElapsed = (block.timestamp -
            getUserLastUpdatedTimestamp(_user));
        // we're using PRECISION_FACTOR (aka 1e18) cause we're in 18 decimal precision
        // note that the interest rate that we get from getUserInterestRate(_user) is ALREADY at 18 decimale precision -> so we needed to make sure that 1 was at THE SAME "magnitude" (aka 1e18) to be able to calculate/operate properly
        return
            PRECISION_FACTOR * 1 + (getUserInterestRate(_user) * timeElapsed);
    }

    /*//////////////////////////////////////////////////////////////
                           Pure & View Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice retrieves the smart contract's interest rate
     * @return smartContractInterestRate returns the interest rate of the smart contract
     */
    function getSmartContractInterestRate()
        external
        view
        returns (uint256 smartContractInterestRate)
    {
        return s_interestRate;
    }

    /**
     * @notice retrieves a user's interest rate
     * @param _user the address for which we're looking to return the attributed interest rate
     */
    function getUserInterestRate(
        address _user
    ) public view returns (uint256 userInterestRate) {
        return s_userTouserInterestRate[_user];
    }

    function getUserLastUpdatedTimestamp(
        address _user
    ) public view returns (uint256 userLastUpdatedTimestamp) {
        return s_userTouserLastUpdatedTimestamp[_user];
    }

    /**
     * @notice This function will calculate the balance for the user INCLUDING any interest that has been accumulated since last update - which is going to be
     * PRINCIPAL balance + some interest that has accrued
     * @param _user The user to calculate the balance for
     * @return balancePlusAccruedInterest the balance of the user including the interest that they have accumulated since last update
     */
    function balanceOf(
        address _user
    )
        public
        view
        override(ERC20, IRebaseToken)
        returns (uint256 balancePlusAccruedInterest)
    {
        // get the current PRINCIPAL balance: aka the number of tokens that have actually been minted to the user aka the number of tokens that are actually reflected in that balance mapping
        // inside the inherited ERC20, there is a _balance mapping -> and that's the state variable that will keep track of the actual tokens that have been minted to them
        // this new balanceOf() function will return _balance + any interest that has accrued since the last time they performed any action like minting, burning, etc...
        uint256 principal = super.balanceOf(_user);

        // multiplies (and returns) the principal balance by the interest that has accumulated in the time since the balance was last updated

        // note, since we're doing a multiplication here where we have PRECISION_FACTOR (from principal) times PRECISION_FACTOR (from _calculateUserAccumulatedInterestSinceLastUpdate(_user)) -> then we MUST DIVIDE by PRECISION_FACTOR to scale things back from 1e36 to 1e18
        return
            (principal *
                _calculateUserAccumulatedInterestSinceLastUpdate(_user)) /
            PRECISION_FACTOR;
    }

    /**
     * @param _user the user we're looking at to check their the principal balance (aka the number of tokens minted to the user, NOT including ny interest they accrued since the LAST TIME they interacted with the protocol)
     * @return balance the principal balance deposited by the user
     */
    function getUserPrincipalBalanceOf(
        address _user
    ) external view returns (uint256 balance) {
        balance = super.balanceOf(_user);
    }

    function getUserAccumulatedInterestSinceLastUpdate(
        address _user
    ) external view returns (uint256 linearInterest) {
        return _calculateUserAccumulatedInterestSinceLastUpdate(_user);
    }

    function getInterestRate() external view returns (uint256 interestRate) {
        return s_interestRate;
    }
}
