pragma solidity 0.4.25;


/// @title ISettings
/// @dev Interface for getting the data from settings contract.
interface ISettings {
    function oracleAddress() external view returns(address);
    function minDeposit() external view returns(uint256);
    function sysFee() external view returns(uint256);
    function userFee() external view returns(uint256);
    function ratio() external view returns(uint256);
    function globalTargetCollateralization() external view returns(uint256);
    function tmvAddress() external view returns(uint256);
    function maxStability() external view returns(uint256);
    function minStability() external view returns(uint256);
    function gasPriceLimit() external view returns(uint256);
    function isFeeManager(address account) external view returns (bool);
    function tBoxManager() external view returns(address);
}
