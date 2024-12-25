// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../script/DeployDSC.s.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {Helpers} from "../script/HelperConfig.s.sol";
import {ERC20Mock} from "./mocks/ERC20Mock.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test, Helpers {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address weth;
    address wbtc;
    address wethUsdPriceFeedAddress;
    address wbtcUsdPriceFeedAddress;
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    address public user = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();

        (wethUsdPriceFeedAddress, wbtcUsdPriceFeedAddress, weth, wbtc,) = helperConfig.activeNetworkConfig();

        vm.startPrank(dsc.owner());
        dsc.transferOwnership(address(dscEngine));
        vm.stopPrank();
        ERC20Mock(weth).mint(user, 1000 ether);
        ERC20Mock(wbtc).mint(user, 1000 ether);
    }

    function testConsctructorRevertsIfTokenAddressesAndPriceFeedAddressesLengthsAreNotTheSame() public {
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeedAddress, wbtcUsdPriceFeedAddress];
        priceFeedAddresses.push(weth); // add redundant address
        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsMustBeTheSame.selector);
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    function testConsctructorRevertsIfDscAddressIsZero() public {
        tokenAddresses = [weth, wbtc];
        priceFeedAddresses = [wethUsdPriceFeedAddress, wbtcUsdPriceFeedAddress];
        vm.expectRevert(DSCEngine.DSCEngine__DscAddressCannotBeZero.selector);
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(0));
    }

    function testGetUsdValueOfCollateral() public view {
        uint256 ethAmount = 15e18;
        // Expected conversion: 15 * 2000 = 30000e18 (with DECIMALS=8)
        uint256 expectedAdjustedPrice = (uint256(ETH_PRICE) * 1e18) / (10 ** uint256(DECIMALS));
        uint256 expectedValue = (expectedAdjustedPrice * ethAmount) / 1e18;
        uint256 wethValue = dscEngine.getUsdValueOfCollateral(weth, ethAmount);
        assertEq(wethValue, expectedValue, "Weth value mismatch");
    }

    function testGetCollateralValueInUsd() public {
        uint256 ethAmount = 10 ether;
        uint256 wbtcAmount = 1 ether;

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), ethAmount);
        ERC20Mock(wbtc).approve(address(dscEngine), wbtcAmount);
        dscEngine.depositCollateral(weth, ethAmount);
        dscEngine.depositCollateral(wbtc, wbtcAmount);
        vm.stopPrank();

        uint256 expectedAdjustedETHPrice = (uint256(ETH_PRICE) * 1e18) / (10 ** uint256(DECIMALS));
        uint256 expectedEthValue = (expectedAdjustedETHPrice * ethAmount) / 1e18;
        uint256 expectedAdjustedBTCPrice = (uint256(BTC_PRICE) * 1e18) / (10 ** uint256(DECIMALS));
        uint256 expectedWbtcValue = (expectedAdjustedBTCPrice * wbtcAmount) / 1e18;
        uint256 expectedTotalValue = expectedEthValue + expectedWbtcValue;

        uint256 actualCollateralValue = dscEngine.getCollateralValueInUsd(user);
        assertEq(actualCollateralValue, expectedTotalValue, "Collateral value does not match expected");
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 1000e18;
        uint256 tokenAmount = dscEngine.getTokenAmountFromUsd(weth, usdAmount);
        uint256 adjustedPrice = (uint256(ETH_PRICE) * 1e18) / (10 ** uint256(DECIMALS));
        uint256 expectedTokenAmount = (usdAmount * 1e18) / adjustedPrice;
        assertEq(tokenAmount, expectedTokenAmount, "Token amount does not match expected");
    }

    function testRevertsWithUnApprovedCollateral() public {
        ERC20Mock fakeToken = new ERC20Mock("FakeToken", "FT", user, 20 ether);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedCollateral.selector, address(fakeToken)));
        dscEngine.depositCollateral(address(fakeToken), 10e18);
        vm.stopPrank();
    }

    function testDepositCollateralRequiresAmountGreaterThanZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmountCannotBeZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testCannotDepositWithoutApproval() public {
        vm.startPrank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(dscEngine),
                ERC20Mock(weth).allowance(user, address(dscEngine)),
                10e18
            )
        );
        dscEngine.depositCollateral(weth, 10e18);
        vm.stopPrank();
    }

    function testDepositCollateralRequiresNonZeroAmount() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 10e18);
        vm.expectRevert(DSCEngine.DSCEngine__AmountCannotBeZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testDepositCollateralRequiresAllowedCollateral() public {
        address fakeToken = address(0x999);
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 10e18);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedCollateral.selector, fakeToken));
        dscEngine.depositCollateral(fakeToken, 10e18);
        vm.stopPrank();
    }

    function testDepositCollateralEmitsEventAndTransfersCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 10e18);
        vm.expectEmit(true, true, false, true);
        emit DSCEngine.CollateralDeposited(user, weth, 10e18);
        dscEngine.depositCollateral(weth, 10e18);
        vm.stopPrank();

        assertEq(dscEngine.getCollateralBalanceOfUser(user, weth), 10e18, "Collateral balance mismatch");
    }

    function testMintDscRequiresAmountGreaterThanZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmountCannotBeZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testMintDscRevertsIfHealthFactorBroken() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 10e18);
        dscEngine.depositCollateral(weth, 10e18);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.mintDsc(10000000e18);
        vm.stopPrank();
    }

    function testMintDscWorksWithSufficientCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        vm.expectEmit(true, true, false, true);
        emit DSCEngine.UserMintedDsc(user, 10e18);
        dscEngine.mintDsc(10e18);
        vm.stopPrank();

        assertEq(dsc.balanceOf(user), 10e18, "DSC balance mismatch");
        assertEq(dscEngine.getCollateralBalanceOfUser(user, weth), 100e18, "Collateral balance mismatch");
    }

    function testDepositCollateralAndMintDscWorks() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateralAndMintDsc(weth, 100e18, 10e18);
        vm.stopPrank();

        assertEq(dscEngine.getCollateralBalanceOfUser(user, weth), 100e18, "Collateral balance mismatch");
        assertEq(dsc.balanceOf(user), 10e18, "DSC balance mismatch");
    }

    function testRevertsIfWrongCollateralIsRedeemed() public {
        ERC20Mock fakeToken = new ERC20Mock("FakeToken", "FT", user, 20 ether);
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedCollateral.selector, address(fakeToken)));
        dscEngine.redeemCollateral(address(fakeToken), 10e18);
        vm.stopPrank();
    }

    function testRedeemCollateralRequiresAmountGreaterThanZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 10e18);
        dscEngine.depositCollateral(weth, 10e18);

        vm.expectRevert(DSCEngine.DSCEngine__AmountCannotBeZero.selector);
        dscEngine.redeemCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralRevertsIfInsufficientAmount() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 10e18);
        dscEngine.depositCollateral(weth, 10e18);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientRedeemAmount.selector, 10e18, 20e18));
        dscEngine.redeemCollateral(weth, 20e18);
        vm.stopPrank();
    }

    function testRedeemCollateralEmitsEventAndTransfersCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 50e18);
        dscEngine.depositCollateral(weth, 50e18);
        dscEngine.mintDsc(10e18);

        uint256 userBalanceBefore = ERC20Mock(weth).balanceOf(user);
        uint256 engineBalanceBefore = ERC20Mock(weth).balanceOf(address(dscEngine));

        vm.expectEmit(true, true, true, true);
        emit DSCEngine.CollateralRedeemed(user, user, weth, 10e18);
        dscEngine.redeemCollateral(weth, 10e18);

        uint256 userBalanceAfter = ERC20Mock(weth).balanceOf(user);
        uint256 engineBalanceAfter = ERC20Mock(weth).balanceOf(address(dscEngine));
        uint256 userCollateralBalance = dscEngine.getCollateralBalanceOfUser(user, weth);
        vm.stopPrank();

        assertEq(userBalanceAfter, userBalanceBefore + 10e18, "User balance should increase by redeemed amount");
        assertEq(engineBalanceAfter, engineBalanceBefore - 10e18, "Engine balance should decrease by redeemed amount");
        assertEq(userCollateralBalance, 40e18, "User's collateral balance in DSC engine should be 40e18 now");
    }

    function testRedeemCollateralRevertsIfHealthFactorIsBroken() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        // For instance, if 100e18 ETH ~ $200,000 @ $2000 per ETH, and user mints 100,000 DSC, health factor ~2
        dscEngine.mintDsc(100000e18);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        // redeem nearly everything
        dscEngine.redeemCollateral(weth, 90e18);

        vm.stopPrank();
    }

    function testBurnDscRequiresAmountGreaterThanZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmountCannotBeZero.selector);
        dscEngine.burnDsc(0);
        vm.stopPrank();
    }

    function testBurnDscRevertsIfInsufficientDscBalance() public {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientBurnAmount.selector, 0, 10e18));
        dscEngine.burnDsc(10e18);
        vm.stopPrank();
    }

    function testBurnDscEmitsEventAndReducesBalance() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        dscEngine.mintDsc(50e18);

        assertEq(dsc.balanceOf(user), 50e18, "User should have 50e18 DSC before burning");

        dsc.approve(address(dscEngine), 20e18);

        vm.expectEmit(true, true, false, true);
        emit DSCEngine.UserBurnedDsc(user, 20e18);

        dscEngine.burnDsc(20e18);
        vm.stopPrank();

        assertEq(dsc.balanceOf(user), 30e18, "User should have 30e18 DSC after burning");
    }

    function testRedeemCollateralForDscRevertsIfBurnAmountIsZero() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        dscEngine.mintDsc(10e18);

        vm.expectRevert(DSCEngine.DSCEngine__AmountCannotBeZero.selector);
        dscEngine.redeemCollateralForDsc(weth, 10e18, 0);
        vm.stopPrank();
    }

    function testRedeemCollateralForDscRevertsIfNotEnoughDscToBurn() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        dscEngine.mintDsc(10e18);

        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__InsufficientBurnAmount.selector, 10e18, 20e18));
        dscEngine.redeemCollateralForDsc(weth, 10e18, 20e18);
        vm.stopPrank();
    }

    function testRedeemCollateralForDscWorksProperly() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        dscEngine.mintDsc(50e18);

        uint256 userCollateralBalanceBefore = dscEngine.getCollateralBalanceOfUser(user, weth);
        uint256 userDscBalanceBefore = dsc.balanceOf(user);
        uint256 userWethBalanceBefore = ERC20Mock(weth).balanceOf(user);

        dsc.approve(address(dscEngine), 20e18);
        dscEngine.redeemCollateralForDsc(weth, 10e18, 20e18);

        uint256 userCollateralBalanceAfter = dscEngine.getCollateralBalanceOfUser(user, weth);
        uint256 userDscBalanceAfter = dsc.balanceOf(user);
        uint256 userWethBalanceAfter = ERC20Mock(weth).balanceOf(user);

        assertEq(userDscBalanceAfter, userDscBalanceBefore - 20e18, "User DSC balance should decrease by burn amount");
        assertEq(
            userCollateralBalanceAfter, userCollateralBalanceBefore - 10e18, "User collateral in engine should decrease"
        );
        assertEq(
            userWethBalanceAfter, userWethBalanceBefore + 10e18, "User WETH balance should increase by redeemed amount"
        );

        uint256 healthFactorAfter = dscEngine.getHealthFactor(user);
        assertTrue(healthFactorAfter >= 1e18, "Health factor should remain above 1 after redeem");

        vm.stopPrank();
    }

    function testRedeemCollateralForDscRevertsIfHealthFactorBroken() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        dscEngine.mintDsc(50000e18);

        dsc.approve(address(dscEngine), 1e18);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.redeemCollateralForDsc(weth, 90e18, 1e18); // Burn only 1 DSC but try to redeem 90 WETH
        vm.stopPrank();
    }

    function testLiquidateDscRevertsIfDebtToCoverIsZero() public {
        address liquidator = makeAddr("liquidator");
        uint256 depositAmount = 100e18;

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), depositAmount);
        dscEngine.depositCollateral(weth, depositAmount);
        vm.stopPrank();

        vm.startPrank(liquidator);
        vm.expectRevert(DSCEngine.DSCEngine__AmountCannotBeZero.selector);
        dscEngine.liquidateDsc(weth, user, 0);
        vm.stopPrank();
    }

    function testLiquidateDscRevertsIfInvalidCollateralToken() public {
        ERC20Mock fakeToken = new ERC20Mock("FakeToken", "FT", user, 20 ether);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__NotAllowedCollateral.selector, address(fakeToken)));
        dscEngine.liquidateDsc(address(fakeToken), user, 10e18);
    }

    function testRevertsIfLiquidatorHealthFactorIsBroken() public {
        address liquidator = makeAddr("liquidator");
        ERC20Mock(weth).mint(liquidator, 10000 ether);
        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), 1e18);
        // 2000 $ liquidator has than mints 500 DSC 2000/2 = 1000 $
        // 1000 $ - 500 DSC after minting = 500 $
        dscEngine.depositCollateralAndMintDsc(weth, 1e18, 500e18);
        // now decreased price from 2000 $ to 100 $
        MockV3Aggregator(wethUsdPriceFeedAddress).updateAnswer(100e8);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.liquidateDsc(weth, user, 1e18);
        vm.stopPrank();
    }

    function testLiquidateDscRevertsIfHealthFactorIsNotBroken() public {
        address liquidator = makeAddr("liquidator");
        ERC20Mock(weth).mint(liquidator, 10000 ether);
        uint256 depositAmount = 100e18;
        uint256 mintAmount = 50e18;
        uint256 debtToCover = 1e18;

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), depositAmount);
        dscEngine.depositCollateralAndMintDsc(weth, depositAmount, mintAmount);
        vm.stopPrank();

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), depositAmount);
        dscEngine.depositCollateralAndMintDsc(weth, depositAmount, debtToCover);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsNotBroken.selector);
        dscEngine.liquidateDsc(weth, user, debtToCover);
        vm.stopPrank();
    }

    function testHealthFactorDoesNotImproveAfterLiquidation() public {
        address liquidator = makeAddr("liquidator");
        vm.deal(liquidator, 1000 ether);
        ERC20Mock(weth).mint(liquidator, 1000 ether);
        uint256 depositAmount = 1e18;
        uint256 liquidatorDepositAmount = 500e18;
        uint256 mintAmount = 500e18;
        uint256 debtToCover = 1e18;

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), depositAmount);
        dscEngine.depositCollateralAndMintDsc(weth, depositAmount, mintAmount);
        MockV3Aggregator(wethUsdPriceFeedAddress).updateAnswer(500e8);

        vm.stopPrank();

        uint256 healthFactorBefore = dscEngine.getHealthFactor(user);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), liquidatorDepositAmount);
        dscEngine.depositCollateralAndMintDsc(weth, liquidatorDepositAmount, debtToCover);
        dsc.approve(address(dscEngine), debtToCover);
        vm.expectRevert(
            abi.encodeWithSelector(
                DSCEngine.DSCEngine__HealthFactorIsNotImproved.selector, healthFactorBefore, uint256(499899799599198396)
            )
        );
        dscEngine.liquidateDsc(weth, user, debtToCover);

        vm.stopPrank();
    }

    function testLiquidateDscWorksProperly() public {
        address liquidator = makeAddr("liquidator");
        ERC20Mock(weth).mint(liquidator, 10000 ether);

        uint256 userDepositAmount = 1e18;
        uint256 liquidatorDepositAmount = 5000e18;
        uint256 userMintAmount = 500e18;
        uint256 debtToCover = 400e18;

        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), userDepositAmount);
        dscEngine.depositCollateralAndMintDsc(weth, userDepositAmount, userMintAmount);
        vm.stopPrank();

        MockV3Aggregator(wethUsdPriceFeedAddress).updateAnswer(700e8);

        uint256 userCollateralBefore = dscEngine.getCollateralBalanceOfUser(user, weth);
        uint256 userHealthFactorBefore = dscEngine.getHealthFactor(user);

        vm.startPrank(liquidator);
        ERC20Mock(weth).approve(address(dscEngine), liquidatorDepositAmount);
        dscEngine.depositCollateralAndMintDsc(weth, liquidatorDepositAmount, debtToCover);
        uint256 liquidatorCollateralBefore = ERC20Mock(weth).balanceOf(liquidator);
        uint256 liquidatorDscBefore = dsc.balanceOf(liquidator);
        dsc.approve(address(dscEngine), debtToCover);

        dscEngine.liquidateDsc(weth, user, debtToCover);
        vm.stopPrank();

        uint256 userCollateralAfter = dscEngine.getCollateralBalanceOfUser(user, weth);
        uint256 userHealthFactorAfter = dscEngine.getHealthFactor(user);

        uint256 liquidatorCollateralAfter = ERC20Mock(weth).balanceOf(liquidator);
        uint256 liquidatorDscAfter = dsc.balanceOf(liquidator);
        uint256 tokenAmountFromDebtCovered = dscEngine.getTokenAmountFromUsd(weth, debtToCover);
        uint256 bonus = (tokenAmountFromDebtCovered * 10) / 100;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonus;

        assertEq(
            userCollateralAfter,
            userCollateralBefore - totalCollateralToRedeem,
            "User collateral should decrease by totalCollateralToRedeem"
        );
        assertEq(
            liquidatorCollateralAfter,
            liquidatorCollateralBefore + totalCollateralToRedeem,
            "Liquidator should receive the redeemed collateral + bonus"
        );
        assertEq(
            liquidatorDscAfter,
            liquidatorDscBefore - debtToCover,
            "Liquidator DSC balance should decrease by the covered debt"
        );
        assertGt(userHealthFactorAfter, userHealthFactorBefore, "User health factor should improve after liquidation");
    }

    function testGetHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);

        dscEngine.mintDsc(10e18);
        uint256 healthFactor = dscEngine.getHealthFactor(user);
        vm.stopPrank();

        assertTrue(healthFactor >= uint256(1e18));
    }

    function testGetHealthFactorReturnsMaxIfNoDscMinted() public {
        vm.startPrank(user);
        uint256 healthFactor = dscEngine.getHealthFactor(user);
        vm.stopPrank();

        assertEq(healthFactor, type(uint256).max);
    }

    function testGetCollateralBalanceOfUser() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        vm.stopPrank();
        assertEq(dscEngine.getCollateralBalanceOfUser(user, weth), 100e18, "Collateral balance mismatch");
    }

    function testGetAccountInformation() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);
        dscEngine.mintDsc(10e18);
        vm.stopPrank();

        uint256 adjustedPrice = (uint256(ETH_PRICE) * 1e18) / (10 ** uint256(DECIMALS));
        uint256 expectedTotalCollateralValueInUsd = (adjustedPrice * 100e18) / 1e18;

        (uint256 totalDcsMinted, uint256 totalCollateralValueInUsd) = dscEngine.getAccountInformation(user);
        assertEq(totalDcsMinted, 10e18, "Total DSC minted mismatch");
        assertEq(totalCollateralValueInUsd, expectedTotalCollateralValueInUsd, "Total collateral value mismatch");
    }

    function testGetMinHealthFactor() public view {
        assertEq(dscEngine.getMinHealthFactor(), 1e18, "Min health factor mismatch");
    }

    function testGetLiquidationThreshold() public view {
        assertEq(dscEngine.getLiquidationThreshold(), 50, "Liquidation threshold mismatch");
    }

    function testGetLiquidationBonus() public view {
        assertEq(dscEngine.getLiquidationBonus(), 10, "Liquidation bonus mismatch");
    }

    function testGetDscStableCoin() public view {
        assertEq(address(dscEngine.getDscStableCoin()), address(dsc), "DSC stable coin mismatch");
    }

    function testGetAllowedCollateralTokens() public view {
        assertEq(dscEngine.getAllowedCollateralTokens()[0], weth, "WETH should be allowed");
        assertEq(dscEngine.getAllowedCollateralTokens()[1], wbtc, "WBTC should be allowed");
    }
}
