pragma solidity 0.5.11;


/// @title ISettings
/// @dev Interface for getting the data from settings contract.
interface ISettings {
    function oracleAddress() external view returns(address);
    function MIN_DEPO() external view returns(uint256);
    function SYS_COMM() external view returns(uint256);
    function USER_COMM() external view returns(uint256);
    function ratio() external view returns(uint256);
    function globalTargetCollateralization() external view returns(uint256);
    function tmvAddress() external view returns(uint256);
    function maxStability() external view returns(uint256);
    function minStability() external view returns(uint256);
    function isFeeManager(address account) external view returns (bool);
    function logicManager() external view returns(address);
}
