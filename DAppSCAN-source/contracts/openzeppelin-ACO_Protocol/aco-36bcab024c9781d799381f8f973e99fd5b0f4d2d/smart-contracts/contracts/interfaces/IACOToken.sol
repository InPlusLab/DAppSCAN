pragma solidity ^0.6.6;

import "./IERC20.sol";

interface IACOToken is IERC20 {
    function name() external view returns(string memory);
    function symbol() external view returns(string memory);
    function decimals() external view returns(uint8);
    function underlying() external view returns (address);
    function strikeAsset() external view returns (address);
    function feeDestination() external view returns (address);
    function isCall() external view returns (bool);
    function strikePrice() external view returns (uint256);
    function expiryTime() external view returns (uint256);
    function totalCollateral() external view returns (uint256);
    function acoFee() external view returns (uint256);
    function underlyingSymbol() external view returns (string memory);
    function strikeAssetSymbol() external view returns (string memory);
    function underlyingDecimals() external view returns (uint8);
    function strikeAssetDecimals() external view returns (uint8);
    function currentCollateral(address account) external view returns(uint256);
    function unassignableCollateral(address account) external view returns(uint256);
    function assignableCollateral(address account) external view returns(uint256);
    function currentCollateralizedTokens(address account) external view returns(uint256);
    function unassignableTokens(address account) external view returns(uint256);
    function assignableTokens(address account) external view returns(uint256);
    function getCollateralAmount(uint256 tokenAmount) external view returns(uint256);
    function getTokenAmount(uint256 collateralAmount) external view returns(uint256);
    function getExerciseData(uint256 tokenAmount) external view returns(address, uint256);
    function getCollateralOnExercise(uint256 tokenAmount) external view returns(uint256, uint256);
    function collateral() external view returns(address);
    function mintPayable() external payable;
    function mintToPayable(address account) external payable;
    function mint(uint256 collateralAmount) external;
    function mintTo(address account, uint256 collateralAmount) external;
    function burn(uint256 tokenAmount) external;
    function burnFrom(address account, uint256 tokenAmount) external;
    function redeem() external;
    function redeemFrom(address account) external;
    function exercise(uint256 tokenAmount) external payable;
    function exerciseFrom(address account, uint256 tokenAmount) external payable;
    function exerciseAccounts(uint256 tokenAmount, address[] calldata accounts) external payable;
    function exerciseAccountsFrom(address account, uint256 tokenAmount, address[] calldata accounts) external payable;
    function clear() external;
    function clearFrom(address account) external;
}