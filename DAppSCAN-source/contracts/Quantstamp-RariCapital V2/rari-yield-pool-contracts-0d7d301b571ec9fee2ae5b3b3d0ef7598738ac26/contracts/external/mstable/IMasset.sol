pragma solidity 0.5.17;

/**
 * @title IMasset
 * @dev   (Internal) Interface for interacting with Masset
 *        VERSION: 1.0
 *        DATE:    2020-05-05
 */
interface IMasset {
    function mint(address _basset, uint256 _bassetQuantity) external returns (uint256 massetMinted);
    function redeem(address _basset, uint256 _bassetQuantity) external returns (uint256 massetRedeemed);
    function swap(address _input, address _output, uint256 _quantity, address _recipient) external returns (uint256 output);
    function swapFee() external view returns (uint256);
}
