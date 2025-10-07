// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {Ownable} from "../lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {IAccessControl} from "../lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract RebaseTokenTest is Test {
    RebaseToken rebaseToken;
    Vault vault;

    address public OWNER = makeAddr("OWNER");
    address public USER = makeAddr("USER");

    function setUp() external {
        vm.startPrank(OWNER);
        rebaseToken = new RebaseToken();
        vault = new Vault(rebaseToken);

        rebaseToken.grantMintAndBurnRole(address(vault));

        vm.stopPrank();
    }

    // this function is a helper function for us to pre-fund the vault with rewards
    function addRewardsToTheVault(uint256 rewardsAmount) public {
        // we don't need to anything with 'success' cause if it doesn't work it will simply fail in our test and revert
        (bool success, ) = payable(address(vault)).call{value: rewardsAmount}(
            ""
        ); // 1 ether == 1e18

        if (!success) {
            revert();
        }
    }

    // n.b. notice that "amount" is fuzzed
    function testDepositLinear(uint256 amount) public {
        amount = bound(amount, 1e5, type(uint96).max);
        vm.deal(USER, amount);

        // (1) deposit
        vm.startPrank(USER);
        vault.deposit{value: amount}();

        // (2) check our rebase tokens balance
        uint256 startBalance = rebaseToken.balanceOf(USER);
        console.log("startBalance: %s", startBalance);
        assertEq(startBalance, amount); // should be equal because no time has passed

        // (3) warp the time and check the balance again
        vm.warp(block.timestamp + 1 hours);
        vm.roll(1);
        uint256 middleBalance = rebaseToken.balanceOf(USER); // we check the balance again
        assertGt(middleBalance, startBalance); // assertGt() means assert greater than

        // (4) warp the time by the same amount and check the balance again

        vm.warp(block.timestamp + 1 hours);
        vm.roll(1);
        uint256 endingBalance = rebaseToken.balanceOf(USER); // we check the balance again one last time
        assertGt(endingBalance, middleBalance);

        // should be equal because the interests increase linearly and the amount of time passed is the same
        assertApproxEqAbs( // means "approximately equal in absolute value"
            middleBalance - startBalance,
            endingBalance - middleBalance,
            1 // 1 here is the "tolerance" difference between the 2 values, in this case 1 wei
        );
        vm.stopPrank();
    }

    function testRedeemStraightAway(uint256 amount) external {
        amount = bound(amount, 1e5, type(uint96).max);

        vm.startPrank(USER);
        vm.deal(USER, amount);

        // 1 - deposit
        vault.deposit{value: amount}();
        // rebaseToken.balanceOf(USER) gives us the balance of the Rebase Token of the user after depositing
        assertEq(rebaseToken.balanceOf(USER), amount);

        // 2 - redeem
        vault.redeem(type(uint256).max);
        vm.stopPrank();
        // address(USER).balance gives us the ETH balance of the user at his/her address after redeeming
        assertEq(address(USER).balance, amount);
    }

    function testRedeemAfterTimeHasPassed(
        uint256 depositAmount,
        uint256 timePassed
    ) external {
        timePassed = bound(timePassed, 1000, type(uint96).max); // maximum time of 2.5 times 10^21 years!!
        depositAmount = bound(depositAmount, 1e5, type(uint96).max);

        vm.deal(USER, depositAmount);

        // 1 - deposit
        vm.prank(USER);
        vault.deposit{value: depositAmount}();
        // rebaseToken.balanceOf(USER) gives us the balance of the Rebase Token of the user after depositing

        // 2 - warp the time
        vm.warp(block.timestamp + timePassed);
        vm.roll(1);
        uint256 userBalanceAfterSomeTime = rebaseToken.balanceOf(USER); // principal + interests

        // (2.b) we also add the user's rewards to our vault
        vm.deal(OWNER, userBalanceAfterSomeTime - depositAmount);
        vm.prank(OWNER);
        addRewardsToTheVault(userBalanceAfterSomeTime - depositAmount);

        // 3 - redeem
        vm.prank(USER);
        vault.redeem(type(uint256).max);

        // address(USER).balance gives us the ETH balance of the user at his/her address after redeeming

        uint256 userEthBalanceAfterRedeeming = address(USER).balance;

        assertEq(userEthBalanceAfterRedeeming, userBalanceAfterSomeTime);
        assertGt(userEthBalanceAfterRedeeming, depositAmount);
    }

    function testTransfer(uint256 amount, uint256 amountToSend) external {
        amount = bound(amount, 1e5 + 1e5, type(uint96).max);
        amountToSend = bound(amountToSend, 1e5, amount - 1e5); // that is, amountToSend has to always be less than amount
        address recipient = makeAddr("USER_2");

        // 1. deposit
        vm.deal(USER, amount);
        vm.prank(USER);
        vault.deposit{value: amount}();

        // we check the initial balances
        uint256 userInitialBalance = rebaseToken.balanceOf(USER);
        uint256 recipientInitialBalance = rebaseToken.balanceOf(recipient);

        assertEq(userInitialBalance, amount);
        assertEq(recipientInitialBalance, 0);

        // owner reduces the interest rate from 5e10 to, e.g., 4e10
        vm.prank(OWNER);
        rebaseToken.setInterestRate(4e10);

        // 2. transfer
        vm.prank(USER);
        bool successfulTransfer = rebaseToken.transfer(recipient, amountToSend);
        if (!successfulTransfer) {
            revert("Unsuccessful transfer");
        }

        uint256 userFinalBalance = rebaseToken.balanceOf(USER);
        uint256 recipientFinalBalance = rebaseToken.balanceOf(recipient);
        assertEq(
            userInitialBalance + recipientInitialBalance,
            recipientFinalBalance + userFinalBalance
        );

        assertEq(userFinalBalance, userInitialBalance - amountToSend);
        assertEq(recipientFinalBalance, amountToSend);

        // 3. check the interest rates of the recipient -> we need to check that t's been inherited from USER and so that's still 5e10 and not 4e10
        assertEq(rebaseToken.getUserInterestRate(recipient), 5e10);
        assertEq(rebaseToken.getUserInterestRate(USER), 5e10);
    }

    function testWeCannotSetInterestRateIfNotOwner() external {
        vm.prank(USER);
        vm.expectPartialRevert(Ownable.OwnableUnauthorizedAccount.selector);
        rebaseToken.setInterestRate(4e10);
    }

    function testCannotCallMintAndBurnIfNotOwner() external {
        vm.prank(USER);
        vm.expectPartialRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector
        );
        rebaseToken.mint(USER, 100, rebaseToken.getInterestRate());
        vm.expectPartialRevert(
            IAccessControl.AccessControlUnauthorizedAccount.selector
        );
        rebaseToken.burn(USER, 100);
    }
}
