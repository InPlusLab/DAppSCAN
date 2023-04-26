// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./UpgradeableOwnable.sol";
import "openzeppelin-solidity/contracts/proxy/UpgradeableProxy.sol";


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract UpgradeableOwnableProxy is UpgradeableOwnable, UpgradeableProxy {
    /**
     * @dev Initializes the upgradeable proxy with an initial implementation specified by `_logic`.
     *
     * If `_data` is nonempty, it's used as data in a delegate call to `_logic`. This will typically be an encoded
     * function call, and allows initializating the storage of the proxy like a Solidity constructor.
     */
    constructor(address _logic, bytes memory _data)
        public
        payable
        UpgradeableProxy(_logic, _data) {
    }

    function upgradeTo(address newImplementation) external onlyOwner {
        _upgradeTo(newImplementation);
    }

    function implementation() external view returns (address) {
        return _implementation();
    }
}

