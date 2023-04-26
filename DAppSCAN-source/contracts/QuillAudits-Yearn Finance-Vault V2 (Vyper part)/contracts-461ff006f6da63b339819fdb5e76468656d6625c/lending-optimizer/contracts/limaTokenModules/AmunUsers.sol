pragma solidity ^0.6.2;

// import "@openzeppelin/upgrades/contracts/Initializable.sol";
import {
    OwnableUpgradeSafe
} from "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import {AddressArrayUtils} from "../library/AddressArrayUtils.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an limaManager) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the limaManager account will be the one that deploys the contract. This
 * can later be changed with {transferLimaManagerOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyLimaManager`, which can be applied to your functions to restrict their use to
 * the limaManager.
 */
contract AmunUsers is OwnableUpgradeSafe {
    using AddressArrayUtils for address[];

    address[] public amunUsers;
    bool public isOnlyAmunUserActive;

    function __AmunUsers_init_unchained(bool _isOnlyAmunUserActive) internal initializer {
        isOnlyAmunUserActive = _isOnlyAmunUserActive;
    }

    modifier onlyAmunUsers(address user) {
        if (isOnlyAmunUserActive) {
            require(
                isAmunUser(user),
                "AmunUsers: msg sender must be part of amunUsers."
            );
        }
        _;
    }

    function switchIsOnlyAmunUser() external onlyOwner {
        isOnlyAmunUserActive = !isOnlyAmunUserActive;
    }

    function isAmunUser(address _amunUser) public view returns (bool) {
        return amunUsers.contains(_amunUser);
    }

    function addAmunUser(address _amunUser) external onlyOwner {
        amunUsers.push(_amunUser);
    }

    function removeAmunUser(address _amunUser) external onlyOwner {
        amunUsers = amunUsers.remove(_amunUser);
    }
}
