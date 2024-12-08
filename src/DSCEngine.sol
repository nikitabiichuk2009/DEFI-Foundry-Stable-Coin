// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
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
    function mintDsc(uint256 amountDscToMint) external amountGreaterThanZero(amountDscToMint) nonReentrant {}

    function burnDsc() external {}

    function liquidateDsc() external {}

    function getHealthFactor() external view {}
}
