// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSC is Script {
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {
        HelperConfig helperConfig = new HelperConfig();
        (
            address wethUsdPriceFeedAddress,
            address wbtcUsdPriceFeedAddress,
            address wethAddress,
            address wbtcAddress,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        tokenAddresses = [wethAddress, wbtcAddress];
        priceFeedAddresses = [wethUsdPriceFeedAddress, wbtcUsdPriceFeedAddress];
        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin(msg.sender);
        DSCEngine dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
        if (block.chainid == 11155111) {
            dsc.transferOwnership(address(dscEngine));
        }

        vm.stopBroadcast();
        return (dsc, dscEngine, helperConfig);
    }
}
