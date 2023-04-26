// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Dependencies/CheckContract.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Interfaces/ILockupContractFactory.sol";
import "./LockupContract.sol";
import "../Dependencies/console.sol";

/*
* The LockupContractFactory deploys LockupContracts - its main purpose is to keep a registry of valid deployed 
* LockupContracts. 
* 
* This registry is checked by ATIDToken when the Astrid deployer attempts to transfer ATID tokens. During the first year 
* since system deployment, the Astrid deployer is only allowed to transfer ATID to valid LockupContracts that have been 
* deployed by and recorded in the LockupContractFactory. This ensures the deployer's ATID can't be traded or staked in the
* first year, and can only be sent to a verified LockupContract which unlocks at least one year after system deployment.
*
* LockupContracts can of course be deployed directly, but only those deployed through and recorded in the LockupContractFactory 
* will be considered "valid" by ATIDToken. This is a convenient way to verify that the target address is a genuine 
* LockupContract.
*/

contract LockupContractFactory is ILockupContractFactory, Ownable, CheckContract {
    using SafeMath for uint;

    // --- Data ---
    string constant public NAME = "LockupContractFactory";

    address public atidTokenAddress;
    
    mapping (address => address) public lockupContractToDeployer;

    // Keep a list of deployed lockup contract addresses in case events are missed.
    address[] public deployedLockupContractAddresses;

    // --- Events ---

    event LockupContractDeployedThroughFactory(
        address _lockupContractAddress,
        address _beneficiary,
        uint _amount,
        uint _monthsToWaitBeforeUnlock,
        uint _releaseSchedule,
        address _deployer
    );

    // --- Functions ---

    function setATIDTokenAddress(address _atidTokenAddress) external override onlyOwner {
        checkContract(_atidTokenAddress);

        atidTokenAddress = _atidTokenAddress;
        emit ATIDTokenAddressSet(_atidTokenAddress);
    }

    // Only ATIDToken contract can call this.
    function deployLockupContract(
        address _beneficiary,
        uint _amount,
        uint _monthsToWaitBeforeUnlock,
        uint _releaseSchedule
    ) external override onlyOwner returns (address) {
        address atidTokenAddressCached = atidTokenAddress;
        _requireATIDAddressIsSet(atidTokenAddressCached);
        LockupContract lockupContract = new LockupContract(
                                                        atidTokenAddressCached,
                                                        _beneficiary,
                                                        _amount,
                                                        _monthsToWaitBeforeUnlock,
                                                        _releaseSchedule);

        lockupContractToDeployer[address(lockupContract)] = msg.sender;
        emit LockupContractDeployedThroughFactory(
            address(lockupContract),
            _beneficiary,
            _amount,
            _monthsToWaitBeforeUnlock,
            _releaseSchedule,
            msg.sender
        );
        deployedLockupContractAddresses.push(address(lockupContract));
        return address(lockupContract);
    }

    function isRegisteredLockup(address _contractAddress) public view override returns (bool) {
        return lockupContractToDeployer[_contractAddress] != address(0);
    }

    // --- 'require'  functions ---
    function _requireATIDAddressIsSet(address _atidTokenAddress) internal pure {
        require(_atidTokenAddress != address(0), "LCF: ATID Address is not set");
    }
}
