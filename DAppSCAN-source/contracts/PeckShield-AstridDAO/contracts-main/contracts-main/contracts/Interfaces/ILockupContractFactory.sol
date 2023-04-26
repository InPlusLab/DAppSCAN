// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;
    
interface ILockupContractFactory {
    
    // --- Events ---

    event ATIDTokenAddressSet(address _atidTokenAddress);
    event LockupContractDeployedThroughFactory(address _lockupContractAddress, address _beneficiary, uint _unlockTime, address _deployer);

    // --- Functions ---

    function setATIDTokenAddress(address _atidTokenAddress) external;

    function deployLockupContract(
        address _beneficiary,
        uint _amount,
        uint _monthsToWaitBeforeUnlock,
        uint _releaseSchedule
    ) external returns (address);

    function isRegisteredLockup(address _addr) external view returns (bool);
}
