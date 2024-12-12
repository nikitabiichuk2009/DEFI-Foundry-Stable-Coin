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

contract DSCEngineTest is Test, Helpers {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address weth;
    address wbtc;
    address wethUsdPriceFeedAddress;
    address wbtcUsdPriceFeedAddress;

    address public user = makeAddr("user");

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();

        (wethUsdPriceFeedAddress, wbtcUsdPriceFeedAddress, weth, wbtc,) = helperConfig.activeNetworkConfig();

        vm.startPrank(dsc.owner());
        dsc.transferOwnership(address(dscEngine));
        vm.stopPrank();
        ERC20Mock(weth).mint(user, 1000 ether);
    }

    function testGetUsdValueOfCollateral() public view {
        uint256 ethAmount = 15e18;
        // Expected conversion: 15 * 2000 = 30000e18 (with DECIMALS=8)
        uint256 expectedAdjustedPrice = (uint256(ETH_PRICE) * 1e18) / (10 ** uint256(DECIMALS));
        uint256 expectedValue = (expectedAdjustedPrice * ethAmount) / 1e18;
        uint256 wethValue = dscEngine.getUsdValueOfCollateral(weth, ethAmount);
        assertEq(wethValue, expectedValue);
    }

    function testDepositCollateralEmitsEventAndTransfersCollateral() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 10e18);
        vm.expectEmit(true, true, false, true);
        emit DSCEngine.CollateralDeposited(user, weth, 10e18);
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

    function testMintDscRequiresAmountGreaterThanZero() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__AmountCannotBeZero.selector);
        dscEngine.mintDsc(0);
        vm.stopPrank();
    }

    function testMintDscRevertsIfHealthFactorBroken() public {
        vm.startPrank(user);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.mintDsc(100e18);
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

        assertEq(dsc.balanceOf(user), 10e18);
        assertEq(dscEngine.getCollateralBalanceOfUser(user, weth), 100e18);
    }

    function testDepositCollateralAndMintDscWorks() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateralAndMintDsc(weth, 100e18, 10e18);
        vm.stopPrank();

        assertEq(dscEngine.getCollateralBalanceOfUser(user, weth), 100e18);
        assertEq(dsc.balanceOf(user), 10e18);
    }

    function testGetHealthFactor() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 100e18);
        dscEngine.depositCollateral(weth, 100e18);

        dscEngine.mintDsc(10e18);
        uint256 healthFactor = dscEngine.getHealthFactor(user);
        vm.stopPrank();

        assertTrue(healthFactor >= uint256(1));
    }

    function testFailIfUserTriesToMintMoreThanCollateralAllows() public {
        vm.startPrank(user);
        ERC20Mock(weth).approve(address(dscEngine), 10e18);
        dscEngine.depositCollateral(weth, 10e18);

        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorIsBroken.selector);
        dscEngine.mintDsc(20000e18);

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
}
