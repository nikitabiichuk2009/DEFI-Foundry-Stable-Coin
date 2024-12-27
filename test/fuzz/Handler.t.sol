// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Handler is going to narrow down the way we call the functions

import {Test} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    uint96 private constant MAX_ALLOWED_COLLATERAL_BE_DEPOSITED = type(uint96).max;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;
    address[] usersWithCollateral;
    MockV3Aggregator wethUsdPriceFeed;
    MockV3Aggregator wbtcUsdPriceFeed;

    constructor(DSCEngine _dsce, DecentralizedStableCoin _dsc) {
        dsce = _dsce;
        dsc = _dsc;

        address[] memory allowedCollateralTokens = dsce.getAllowedCollateralTokens();
        weth = allowedCollateralTokens[0];
        wbtc = allowedCollateralTokens[1];
        wethUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(weth));
        wbtcUsdPriceFeed = MockV3Aggregator(dsce.getCollateralTokenPriceFeed(wbtc));
    }

    function depositCollateral(uint256 tokenCollateralAddressSeed, uint256 amountCollateral) public {
        address tokenCollateralAddress = _getCollateralFromSeed(tokenCollateralAddressSeed);
        amountCollateral = bound(amountCollateral, 1, MAX_ALLOWED_COLLATERAL_BE_DEPOSITED);
        vm.startPrank(msg.sender);
        ERC20Mock(tokenCollateralAddress).mint(msg.sender, amountCollateral);
        ERC20Mock(tokenCollateralAddress).approve(address(dsce), amountCollateral);

        dsce.depositCollateral(tokenCollateralAddress, amountCollateral);
        vm.stopPrank();
        if (usersWithCollateral.length > 0) {
            for (uint256 i = 0; i < usersWithCollateral.length; i++) {
                if (usersWithCollateral[i] == msg.sender) {
                    return;
                }
            }
        }
        usersWithCollateral.push(msg.sender);
    }

    function mintDsc(uint256 amountDsc, uint256 usersAddressSeed) public {
        if (usersWithCollateral.length == 0) {
            return;
        }
        address sender = usersWithCollateral[usersAddressSeed % usersWithCollateral.length];
        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dsce.getAccountInformation(sender);
        int256 maxDscToMint = ((int256(totalCollateralValueInUsd) * int256(dsce.getLiquidationThreshold())) / 100)
            - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        amountDsc = bound(amountDsc, 0, uint256(maxDscToMint));
        if (amountDsc == 0) {
            return;
        }
        vm.prank(sender);
        dsce.mintDsc(amountDsc);
    }

    function redeemCollateral(uint256 tokenCollateralAddressSeed, uint256 amountCollateral, uint256 usersAddressSeed)
        public
    {
        if (usersWithCollateral.length == 0) {
            return;
        }
        address sender = usersWithCollateral[usersAddressSeed % usersWithCollateral.length];
        address tokenCollateralAddress = _getCollateralFromSeed(tokenCollateralAddressSeed);

        uint256 userCollateralBalance = dsce.getCollateralBalanceOfUser(sender, tokenCollateralAddress);

        if (userCollateralBalance == 0) {
            return;
        }

        (uint256 totalDscMinted, uint256 totalCollateralValueInUsd) = dsce.getAccountInformation(sender);
        uint256 liquidationThreshold = dsce.getLiquidationThreshold();

        uint256 maxCollateralRedeemableUsd = 0;
        uint256 maxCollateralToRedeem = 0;

        if (totalDscMinted == 0) {
            maxCollateralToRedeem = userCollateralBalance;
        } else {
            uint256 requiredCollateralUsdValue = (totalDscMinted * 100) / liquidationThreshold;

            if (totalCollateralValueInUsd < requiredCollateralUsdValue) {
                return;
            }

            maxCollateralRedeemableUsd = totalCollateralValueInUsd - requiredCollateralUsdValue;
            maxCollateralToRedeem = dsce.getTokenAmountFromUsd(tokenCollateralAddress, maxCollateralRedeemableUsd);

            maxCollateralToRedeem = maxCollateralToRedeem > userCollateralBalance ? 0 : maxCollateralToRedeem;
        }

        if (maxCollateralToRedeem == 0) {
            return;
        }

        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }

        vm.prank(sender);
        dsce.redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function burnDscWithHealthFactorCheck(uint256 amountDsc, uint256 usersAddressSeed) public {
        if (usersWithCollateral.length == 0) {
            return;
        }

        address sender = usersWithCollateral[usersAddressSeed % usersWithCollateral.length];
        (uint256 totalDscMinted,) = dsce.getAccountInformation(sender);

        if (totalDscMinted == 0) {
            return;
        }
        amountDsc = bound(amountDsc, 0, totalDscMinted);

        if (amountDsc == 0) {
            return;
        }

        vm.startPrank(sender);
        dsc.approve(address(dsce), amountDsc);
        dsce.burnDsc(amountDsc);
        vm.stopPrank();
    }

    function _getCollateralFromSeed(uint256 tokenCollateralAddressSeed) public view returns (address) {
        if (tokenCollateralAddressSeed % 2 == 0) {
            return weth;
        }
        return wbtc;
    }

    // Breaks our protocol
    // function updateCollateralPrice(uint96 newPrice, uint256 tokenCollateralAddressSeed) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     if (tokenCollateralAddressSeed % 2 == 0) {
    //         wethUsdPriceFeed.updateAnswer(newPriceInt);
    //     } else {
    //         wbtcUsdPriceFeed.updateAnswer(newPriceInt);
    //     }
    // }
}
