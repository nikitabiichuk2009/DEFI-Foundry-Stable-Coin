// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Handler is going to narrow down the way we call the functions

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    uint96 private constant MAX_ALLOWED_COLLATERAL_BE_DEPOSITED = type(uint96).max;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory allowedCollateralTokens = dsce.getAllowedCollateralTokens();
        weth = allowedCollateralTokens[0];
        wbtc = allowedCollateralTokens[1];
    }

    function depositCollateral(uint256 tokenCollateralAddressSeed, uint256 amountCollateral) public {
        address tokenCollateralAddress = _getCollateralFromSeed(tokenCollateralAddressSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_ALLOWED_COLLATERAL_BE_DEPOSITED);
        vm.startPrank(msg.sender);
        ERC20Mock(tokenCollateralAddress).mint(msg.sender, amountCollateral);
        ERC20Mock(tokenCollateralAddress).approve(address(dsce), amountCollateral);

        dsce.depositCollateral(tokenCollateralAddress, amountCollateral);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 tokenCollateralAddressSeed) public view returns (address) {
        if (tokenCollateralAddressSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }
}
