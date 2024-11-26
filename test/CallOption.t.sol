// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import { CallOption } from "../src/CallOption.sol";

contract CallOptionTest is Test {
    CallOption public option;
    address public owner;
    address public user;

    string constant NAME = "ETH Call Option";
    string constant SYMBOL = "ETHCALL";
    uint256 constant STRIKE_PRICE = 2 ether; // exercise price is 2 ETH
    uint256 constant EXPIRATION_DAYS = 30; // 30 days to expire

    event OptionMinted(address indexed minter, uint256 ethAmount, uint256 tokenAmount);
    event OptionExercised(address indexed exerciser, uint256 tokenAmount, uint256 ethAmount);
    event OptionExpired(uint256 remainingEth);

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        // deploy contract
        vm.prank(owner);
        option = new CallOption(NAME, SYMBOL, STRIKE_PRICE, EXPIRATION_DAYS);

        // give some ETH to test accounts
        vm.deal(owner, 100 ether);
        vm.deal(user, 100 ether);
    }

    function test_InitialState() public {
        assertEq(option.name(), NAME);
        assertEq(option.symbol(), SYMBOL);
        assertEq(option.strikePrice(), STRIKE_PRICE);
        assertEq(option.owner(), owner);
        assertFalse(option.isExpired());
    }

    function test_MintOptions() public {
        uint256 mintAmount = 5 ether;

        vm.prank(owner);
        vm.expectEmit(true, false, false, true);
        emit OptionMinted(owner, mintAmount, mintAmount);
        option.mintOptions{ value: mintAmount }();

        assertEq(option.balanceOf(owner), mintAmount);
        assertEq(option.getBalance(), mintAmount);
    }

    function test_MintOptions_RevertIfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        option.mintOptions{ value: 1 ether }();
    }

    function test_Exercise() public {
        // mint some option tokens first
        uint256 mintAmount = 5 ether;
        vm.prank(owner);
        option.mintOptions{ value: mintAmount }();

        // transfer some option tokens to user
        vm.prank(owner);
        option.transfer(user, 2 ether);

        // warp to expiration date
        vm.warp(block.timestamp + 30 days);

        // user exercise
        uint256 exerciseAmount = 1 ether;
        uint256 paymentRequired = (exerciseAmount * STRIKE_PRICE) / 1 ether;

        vm.prank(user);
        vm.expectEmit(true, false, false, true);
        emit OptionExercised(user, exerciseAmount, exerciseAmount);
        option.exercise{ value: paymentRequired }(exerciseAmount);

        assertEq(option.balanceOf(user), 1 ether); // should have 1 ETH left
        assertEq(address(user).balance, 99 ether); // 100 - 2(payment) + 1(received) = 99
    }

    function test_Exercise_RevertIfNotExpired() public {
        vm.prank(owner);
        option.mintOptions{ value: 5 ether }();

        vm.prank(owner);
        option.transfer(user, 2 ether);

        vm.prank(user);
        vm.expectRevert();
        option.exercise{ value: 2 ether }(1 ether);
    }

    function test_Exercise_RevertIfInsufficientPayment() public {
        vm.prank(owner);
        option.mintOptions{ value: 5 ether }();

        vm.prank(owner);
        option.transfer(user, 2 ether);

        vm.warp(block.timestamp + 30 days);

        vm.prank(user);
        vm.expectRevert();
        option.exercise{ value: 1 ether }(1 ether); // payment is not enough
    }

    function test_Expire() public {
        // mint option tokens
        vm.prank(owner);
        option.mintOptions{ value: 5 ether }();

        // warp to expiration date
        vm.warp(block.timestamp + 31 days);

        uint256 initialOwnerBalance = address(owner).balance;

        vm.prank(owner);
        vm.expectEmit(false, false, false, true);
        emit OptionExpired(5 ether);
        option.expire();

        assertTrue(option.isExpired());
        assertEq(option.getBalance(), 0);
        assertEq(address(owner).balance, initialOwnerBalance + 5 ether);
    }

    function test_Expire_RevertIfNotExpired() public {
        vm.prank(owner);
        option.mintOptions{ value: 5 ether }();

        vm.prank(owner);
        vm.expectRevert();
        option.expire();
    }

    function test_Expire_RevertIfNotOwner() public {
        vm.prank(owner);
        option.mintOptions{ value: 5 ether }();

        vm.warp(block.timestamp + 31 days);

        vm.prank(user);
        vm.expectRevert();
        option.expire();
    }

    receive() external payable { }
}
