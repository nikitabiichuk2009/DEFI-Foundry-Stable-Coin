// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

// 1. The total supply of DSC should be less than the total value of collateral

// 2. Getter view functions should never revert <- evergreen invariant

contract InvariantsTest is StdInvariant, Test {
    DeployDSC deployer;
    DSCEngine dsce;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        // targetContract(address(dsce));
        (,, weth, wbtc,) = config.activeNetworkConfig();
        vm.startPrank(dsc.owner());
        dsc.transferOwnership(address(dsce));
        vm.stopPrank();
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreCollateralThanTotalSupply() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWETHCollateral = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWBTCCollateral = IERC20(wbtc).balanceOf(address(dsce));
        uint256 totalWETHValue = dsce.getUsdValueOfCollateral(weth, totalWETHCollateral);
        uint256 totalWBTCValue = dsce.getUsdValueOfCollateral(wbtc, totalWBTCCollateral);
        uint256 totalCollateralValue = totalWETHValue + totalWBTCValue;
        assert(totalCollateralValue >= totalSupply);
    }
}
