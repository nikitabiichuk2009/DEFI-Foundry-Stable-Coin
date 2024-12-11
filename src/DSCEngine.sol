// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
/*
 * @title DecentralizedStableCoin
 * @author @nikitabiichuk2009
 * @dev This is the DSCEngine contract
 * @dev This contract is designed to be as minimal as possible, and have the tokens maintain 1 token = $1
 * @dev This contract is exogenous collateral-based dollar-pegged
 */

contract DSCEngine is ReentrancyGuard {
    error DSCEngine__AmountCannotBeZero();
    error DSCEngine__NotAllowedCollateral(address tokenCollateralAddress);
    error DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsMustBeTheSame();
    error DSCEngine__DscAddressCannotBeZero();
    error DSCEngine__TransferWhenDepositingCollateralFailed();
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__TransferWhenMintingDscFailed();
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_amountDscMinted;
    address[] private s_collateralTokens;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1;
    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );

    modifier amountGreaterThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__AmountCannotBeZero();
        }
        _;
    }

    modifier isAllowedCollateral(address tokenCollateralAddress) {
        if (s_priceFeeds[tokenCollateralAddress] == address(0)) {
            revert DSCEngine__NotAllowedCollateral(tokenCollateralAddress);
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesLengthsMustBeTheSame();
        }
        if (dscAddress == address(0)) {
            revert DSCEngine__DscAddressCannotBeZero();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    function depositCollateralAndMintDsc() external {}

    /*
     * @notice Deposit Collateral for a user
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        amountGreaterThanZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferWhenDepositingCollateralFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /*
     * @notice Mint DSC
     * @param amountDscToMint The amount of DSC to mint
     *@notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) external amountGreaterThanZero(amountDscToMint) nonReentrant {
        s_amountDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        bool success = i_dsc.transfer(msg.sender, amountDscToMint);
        if (!success) {
            revert DSCEngine__TransferWhenMintingDscFailed();
        }
    }

    function burnDsc() external {}

    function liquidateDsc() external {}

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDcsMinted, uint256 totalCollateralValueInUsd)
    {
        totalDcsMinted = s_amountDscMinted[user];
        totalCollateralValueInUsd = getCollateralValueInUsd(user);
        return (totalDcsMinted, totalCollateralValueInUsd);
    }

    function getCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
        totalCollateralValueInUsd = 0;
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address tokenCollateralAddress = s_collateralTokens[i];
            uint256 amountCollateral = s_collateralDeposited[user][tokenCollateralAddress];
            totalCollateralValueInUsd += getUsdValueOfCollateral(tokenCollateralAddress, amountCollateral);
        }
    }

    function getUsdValueOfCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        // Convert the price to a 1e18 scale
        uint256 adjustedPrice = (uint256(price) * 1e18) / (10 ** uint256(decimals));
        return (adjustedPrice * amountCollateral) / 1e18;
    }

    // returns how close to liquidation the user is
    // if user goes below 1, they are liquidatable
    function _getHealthFactor(address user) private view returns (uint256) {
        (uint256 totalDcsMinted, uint256 totalCollateralValueInUsd) = _getAccountInformation(user);
        uint256 collateralAdjustedForThreshold = (totalCollateralValueInUsd * LIQUIDATION_THRESHOLD) / 100;
        return (collateralAdjustedForThreshold * 1e18) / totalDcsMinted;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _getHealthFactor(user);
        if (healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken();
        }
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactor(user);
    }
}
