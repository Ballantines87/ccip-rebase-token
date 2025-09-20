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

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

// (1) we need to pass an address to the constructor
// (2) then create a deposit function that mints tokens to the user equal to the amount of ETH the user has sent
// (3) then create a redeem function that burns tokens from the user and sends the user ETH
// (4) create a way to add rewards to the vault

contract Vault {
    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    error Vault_RedeemFailed(address user, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    IRebaseToken private immutable i_rebaseToken;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event Vault__Deposit(address indexed user, uint256 indexed amountDeposited);

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                              Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    /*//////////////////////////////////////////////////////////////
                    receive() Function (if it exists)
    //////////////////////////////////////////////////////////////*/

    /**  @notice Gestisce la ricezione di Ether inviati senza dati
    * @dev
    * - Questa funzione è eseguita automaticamente dal protocollo
    * - Viene scelta invece della fallback() solo se msg.data è vuoto
    * - Deve essere `external` e `payable`
    * 
    * @custom:usage Usata da send(), transfer() o call{value: ...}("") 
    * receive() external payable {
        // logica per ricevere Ether
      }
    *
    * @custom:example
    * - alice.transfer(1 ether) -> attiva receive()
    * - address(this).call{value: 1 ether}("") -> attiva receive()
    * - address(this).call{value: 1 ether}("ciao") -> attiva fallback()
        receive() external payable {
            // logica personalizzata
      }
    */

    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                    fallback() Function (if it exists)
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           External Functions
    //////////////////////////////////////////////////////////////*/

    function deposit() external payable {
        // (1) we need to use the amount of ETH that the user has sent to mint tokens to the user
        // address(this).call{value: msg.value}("");
        i_rebaseToken.mint(msg.sender, msg.value);
        emit Vault__Deposit(msg.sender, msg.value);
    }

    function redeem(uint256 _amount) external {
        // Follows CEI

        // (1) First, we need to burn the tokens from the user
        i_rebaseToken.burn(msg.sender, _amount);
        // (2) We need to send the user ETH
        // we could do payable(msg.sender).transfer(_amount) - however it's not optimal
        // and so we're doing a low-level call:
        (bool success, ) = payable(msg.sender).call{value: _amount}(""); // n.b. _amount is the ETH amount we want to send with this low-level call

        if (!success) {
            revert Vault_RedeemFailed(msg.sender, _amount);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           Public Functions
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           Internal Functions
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           Private Functions
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                           Pure & View Functions
    //////////////////////////////////////////////////////////////*/

    function getRebaseTokenAddress()
        external
        view
        returns (address rebaseTokenAddress)
    {
        return address(i_rebaseToken);
    }
}
