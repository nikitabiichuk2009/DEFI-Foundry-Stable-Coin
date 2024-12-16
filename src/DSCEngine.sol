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
    error DSCEngine__HealthFactorIsBroken();
    error DSCEngine__HealthFactorIsNotBroken();
    error DSCEngine__TransferFailed();
    error DSCEngine__InsufficientRedeemAmount(uint256 depositedAmount, uint256 requestedAmount);
    error DSCEngine__InsufficientBurnAmount(uint256 mintedAmount, uint256 requestedAmount);
    error DSCEngine__HealthFactorIsNotImproved(uint256 healthFactorBefore, uint256 healthFactorAfter);

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_amountDscMinted;
    address[] private s_collateralTokens;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    DecentralizedStableCoin private immutable i_dsc;

    event CollateralDeposited(
        address indexed user, address indexed tokenCollateralAddress, uint256 indexed amountCollateral
    );

    event UserMintedDsc(address indexed user, uint256 amountDscMinted);
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed tokenCollateralAddress,
        uint256 amountCollateral
    );
    event UserBurnedDsc(address indexed user, uint256 amountDscBurned);

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

    function depositCollateralAndMintDsc(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToMint
    ) external amountGreaterThanZero(amountCollateral) amountGreaterThanZero(amountDscToMint) {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
     * @notice Deposit Collateral for a user
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        amountGreaterThanZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    // health factor must be greater than 1 after redeeming collateral
    /*
     * @notice Redeem Collateral for a user
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to redeem
     */
    function _redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral, address from, address to)
        private
        amountGreaterThanZero(amountCollateral)
        nonReentrant
        isAllowedCollateral(tokenCollateralAddress)
    {
        if (s_collateralDeposited[from][tokenCollateralAddress] < amountCollateral) {
            revert DSCEngine__InsufficientRedeemAmount(
                s_collateralDeposited[from][tokenCollateralAddress], amountCollateral
            );
        }
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        public
        nonReentrant
        amountGreaterThanZero(amountCollateral)
        isAllowedCollateral(tokenCollateralAddress)
    {
        _redeemCollateral(tokenCollateralAddress, amountCollateral, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }
    /*
     * @notice Burn DSC for a user
     * @param amountDscToBurn The amount of DSC to burn
     */

    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom)
        public
        amountGreaterThanZero(amountDscToBurn)
        nonReentrant
    {
        if (s_amountDscMinted[msg.sender] < amountDscToBurn) {
            revert DSCEngine__InsufficientBurnAmount(s_amountDscMinted[msg.sender], amountDscToBurn);
        }
        s_amountDscMinted[onBehalfOf] -= amountDscToBurn;
        emit UserBurnedDsc(onBehalfOf, amountDscToBurn);
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function burnDsc(uint256 amountDscToBurn) public amountGreaterThanZero(amountDscToBurn) nonReentrant {
        _burnDsc(amountDscToBurn, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // not sure if this is needed
    }
    /*
     * @notice Redeem Collateral for DSC
     * @param tokenCollateralAddress The address of the collateral token
     * @param amountCollateral The amount of collateral to redeem
     * @param amountDscToBurn The amount of DSC to burn
     */

    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn)
        external
    {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    /*
     * @notice Mint DSC
     * @param amountDscToMint The amount of DSC to mint
     *@notice they must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountDscToMint) public amountGreaterThanZero(amountDscToMint) nonReentrant {
        s_amountDscMinted[msg.sender] += amountDscToMint;
        _revertIfHealthFactorIsBroken(msg.sender);
        emit UserMintedDsc(msg.sender, amountDscToMint);
        bool success = i_dsc.mint(msg.sender, amountDscToMint);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

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
            uint256 tokenColeteralUsdValue = getUsdValueOfCollateral(tokenCollateralAddress, amountCollateral);
            totalCollateralValueInUsd += tokenColeteralUsdValue;
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

    function getTokenAmountFromUsd(address tokenCollateralAddress, uint256 usdAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenCollateralAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint8 decimals = priceFeed.decimals();
        uint256 adjustedPrice = (uint256(price) * 1e18) / (10 ** uint256(decimals));
        return (usdAmount * 1e18) / adjustedPrice;
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
    /*
     * @notice Liquidate DSC
     * @dev This function is used to liquidate some user from the system
     * @param collateralTokenAddress The address of the collateral token to liquidate
     * @param userToLiquidate The address of the user to liquidate, their health factor must be less than MIN_HEALTH_FACTOR
     * @param debtToCover The amount of DSC you want to burn to impove the user's health factor
     */

    function liquidateDsc(address collateralTokenAddress, address userToLiquidate, uint256 debtToCover)
        external
        nonReentrant
        amountGreaterThanZero(debtToCover)
        isAllowedCollateral(collateralTokenAddress)
    {
        uint256 userHealthFactorBefore = _getHealthFactor(userToLiquidate);
        if (userHealthFactorBefore >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsNotBroken();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateralTokenAddress, debtToCover);
        // give the liquidator 10% bonus
        uint256 bonus = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / 100;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonus;
        _redeemCollateral(collateralTokenAddress, totalCollateralToRedeem, userToLiquidate, msg.sender);
        _burnDsc(debtToCover, userToLiquidate, msg.sender);
        uint256 healthFactorAfter = _getHealthFactor(userToLiquidate);
        if (healthFactorAfter <= userHealthFactorBefore) {
            revert DSCEngine__HealthFactorIsNotImproved(userHealthFactorBefore, healthFactorAfter);
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor(address user) public view returns (uint256) {
        return _getHealthFactor(user);
    }

    function getCollateralBalanceOfUser(address user, address token) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }
}
