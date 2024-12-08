// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/*
 * @title DecentralizedStableCoin
 * @author @nikitabiichuk2009
 * @dev This is the DecentralizedStableCoin contract
 * @dev This contract is meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stable coin
 */

contract DecentralizedStableCoin is ERC20, ERC20Burnable, Ownable {
    error DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance(uint256 balance, uint256 amount);
    error DecentralizedStableCoin__MintAmountMustBeGreaterThanZero();

    constructor(address initialOwner) ERC20("DecentralizedStableCoinNikitaBiichuk", "DSCNB") Ownable(initialOwner) {}

    function burn(uint256 amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (amount <= 0) {
            revert DecentralizedStableCoin__BurnAmountMustBeGreaterThanZero();
        }
        if (balance < amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance(balance, amount);
        }
        super.burn(amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (amount <= 0) {
            revert DecentralizedStableCoin__MintAmountMustBeGreaterThanZero();
        }

        _mint(to, amount);
        return true;
    }
}
