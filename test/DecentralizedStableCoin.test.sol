// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoinTest is Test {
    DecentralizedStableCoin public dsc;

    address bob = makeAddr("bob");
    address alice = makeAddr("alice");
    uint256 constant INITIAL_BALANCE = 1000 ether;

    function setUp() external {
        dsc = new DecentralizedStableCoin(address(this));

        dsc.mint(bob, INITIAL_BALANCE);
        dsc.mint(alice, INITIAL_BALANCE);
    }

    function testNameIsCorrect() public view {
        assertEq(dsc.name(), "DecentralizedStableCoinNikitaBiichuk");
    }

    function testSymbolIsCorrect() public view {
        assertEq(dsc.symbol(), "DSCNB");
    }

    function testOwnerIsCorrect() public view {
        assertEq(dsc.owner(), address(this));
    }

    function testBobAndAliceBalance() public view {
        assertEq(dsc.balanceOf(bob), INITIAL_BALANCE);
        assertEq(dsc.balanceOf(alice), INITIAL_BALANCE);
    }

    function testMintFailsIfNotOwner() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        dsc.mint(bob, 1000 ether);
    }

    function testMintFailsWithZeroAmount() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MintAmountMustBeGreaterThanZero.selector);
        dsc.mint(bob, 0);
    }

    function testBurnFailsIfNotOwner() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        dsc.burn(100 ether);
    }

    function testBurnFailsWithZeroAmount() public {
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero.selector);
        dsc.burn(0);
    }

    function testBurnFailsWithInsufficientBalance() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector, 0, 100 ether
            )
        );
        dsc.burn(100 ether);
    }

    function testBurnWorks() public {
        uint256 mintAmount = 1000 ether;
        dsc.mint(address(this), mintAmount);

        // Verify  state
        assertEq(dsc.totalSupply(), INITIAL_BALANCE * 2 + mintAmount);
        assertEq(dsc.balanceOf(address(this)), mintAmount);

        uint256 burnAmount = 100 ether;
        uint256 initialSupply = dsc.totalSupply();
        uint256 initialBalance = dsc.balanceOf(address(this));

        dsc.burn(burnAmount);

        assertEq(dsc.balanceOf(address(this)), initialBalance - burnAmount);
        assertEq(dsc.totalSupply(), initialSupply - burnAmount);
    }

    function testTransferWorks() public {
        uint256 transferAmount = 100 ether;
        uint256 bobInitialBalance = dsc.balanceOf(bob);
        uint256 aliceInitialBalance = dsc.balanceOf(alice);

        vm.prank(bob);
        dsc.transfer(alice, transferAmount);

        assertEq(dsc.balanceOf(bob), bobInitialBalance - transferAmount);
        assertEq(dsc.balanceOf(alice), aliceInitialBalance + transferAmount);
    }

    function testTransferFailsWithInsufficientBalance() public {
        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, bob, INITIAL_BALANCE, INITIAL_BALANCE + 1 ether
            )
        );
        dsc.transfer(alice, INITIAL_BALANCE + 1 ether);
    }

    function testAllowanceWorks() public {
        uint256 initialAllowance = 1000 ether;
        vm.prank(alice);
        dsc.approve(bob, initialAllowance);

        assertEq(dsc.allowance(alice, bob), initialAllowance);

        vm.prank(bob);
        uint256 transferAmount = 500 ether;
        dsc.transferFrom(alice, bob, transferAmount);

        assertEq(dsc.balanceOf(bob), INITIAL_BALANCE + transferAmount);
        assertEq(dsc.balanceOf(alice), INITIAL_BALANCE - transferAmount);
    }

    function testTransferOwnershipWorks() public {
        dsc.transferOwnership(bob);
        assertEq(dsc.owner(), bob);
    }

    function testTransferOwnershipFailsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        dsc.transferOwnership(bob);
    }

    function testBurnFromWorks() public {
        uint256 burnAmount = 100 ether;
        uint256 initialSupply = dsc.totalSupply();
        uint256 bobInitialBalance = dsc.balanceOf(bob);

        vm.startPrank(bob);
        dsc.approve(address(this), burnAmount);
        vm.stopPrank();

        dsc.burnFrom(bob, burnAmount);

        assertEq(dsc.balanceOf(bob), bobInitialBalance - burnAmount);
        assertEq(dsc.totalSupply(), initialSupply - burnAmount);
        assertEq(dsc.allowance(bob, address(this)), 0);
    }
}
