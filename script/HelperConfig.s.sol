// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

abstract contract Helpers {
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_PRICE = 2000e8;
    int256 public constant BTC_PRICE = 100000e8;
}

contract HelperConfig is Script, Helpers {
    struct NetworkConfig {
        address wethUsdPriceFeedAddress;
        address wbtcUsdPriceFeedAddress;
        address wethAddress;
        address wbtcAddress;
        uint256 deployerKey;
    }

    NetworkConfig public activeNetworkConfig;

    constructor() {
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethUsdPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcUsdPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            wethAddress: 0xb16F35c0Ae2912430DAc15764477E179D9B9EbEa,
            wbtcAddress: 0x6085268aB3e3b414A08762b671DC38243B29621c,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethUsdPriceFeedAddress != address(0)) {
            return activeNetworkConfig;
        }
        vm.startBroadcast();
        MockV3Aggregator ethPriceFeedMock = new MockV3Aggregator(DECIMALS, ETH_PRICE);
        MockV3Aggregator btcPriceFeedMock = new MockV3Aggregator(DECIMALS, BTC_PRICE);
        ERC20Mock wethMock = new ERC20Mock("Wrapped Ether", "WETH", msg.sender, 10000 ether);
        ERC20Mock wbtcMock = new ERC20Mock("Wrapped Bitcoin", "WBTC", msg.sender, 1000 ether);
        vm.stopBroadcast();
        return NetworkConfig({
            wethUsdPriceFeedAddress: address(ethPriceFeedMock),
            wbtcUsdPriceFeedAddress: address(btcPriceFeedMock),
            wethAddress: address(wethMock),
            wbtcAddress: address(wbtcMock),
            deployerKey: 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 // default anvil key
        });
    }
}
