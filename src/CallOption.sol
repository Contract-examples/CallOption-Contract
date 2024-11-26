// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuardTransient } from "@openzeppelin/contracts/utils/ReentrancyGuardTransient.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";

contract CallOption is ERC20, Ownable, ReentrancyGuardTransient {
    uint256 public strikePrice; // strike price
    uint256 public expirationDate; // expiration date
    bool public isExpired;

    // event
    event OptionMinted(address indexed minter, uint256 ethAmount, uint256 tokenAmount);
    event OptionExercised(address indexed exerciser, uint256 tokenAmount, uint256 ethAmount);
    event OptionExpired(uint256 remainingEth);

    // error
    error NotExpiredYet();
    error AlreadyExpired();
    error NotExpirationDate();
    error InsufficientPayment();
    error ExerciseFailed();

    constructor(
        string memory name,
        string memory symbol,
        uint256 _strikePrice,
        uint256 _expirationDays
    )
        ERC20(name, symbol)
        Ownable(msg.sender)
    {
        strikePrice = _strikePrice;
        expirationDate = block.timestamp + (_expirationDays * 1 days);
    }

    // mint option token
    function mintOptions() external payable onlyOwner nonReentrant {
        if (isExpired) revert AlreadyExpired();

        // mint 1 option token for each ETH
        uint256 tokenAmount = msg.value;
        _mint(msg.sender, tokenAmount);

        emit OptionMinted(msg.sender, msg.value, tokenAmount);
    }

    // user exercise
    function exercise(uint256 tokenAmount) external payable nonReentrant {
        // check if expired
        if (block.timestamp < expirationDate) revert NotExpirationDate();
        if (isExpired) revert AlreadyExpired();

        // check if payment is enough
        uint256 requiredPayment = (tokenAmount * strikePrice) / 1 ether;
        if (msg.value < requiredPayment) revert InsufficientPayment();

        // burn option token
        _burn(msg.sender, tokenAmount);

        // transfer ETH to user
        Address.sendValue(payable(msg.sender), tokenAmount);

        // if user paid more ETH, return the excess
        uint256 excess = msg.value - requiredPayment;
        if (excess > 0) {
            Address.sendValue(payable(msg.sender), excess);
        }

        emit OptionExercised(msg.sender, tokenAmount, tokenAmount);
    }

    // project expire
    function expire() external onlyOwner nonReentrant {
        if (block.timestamp <= expirationDate) revert NotExpiredYet();
        if (isExpired) revert AlreadyExpired();

        isExpired = true;
        uint256 remainingEth = address(this).balance;

        // transfer all remaining ETH to owner
        if (remainingEth > 0) {
            Address.sendValue(payable(owner()), remainingEth);
        }

        emit OptionExpired(remainingEth);
    }

    function getBalance() public view returns (uint256) {
        return address(this).balance;
    }

    receive() external payable { }
}
