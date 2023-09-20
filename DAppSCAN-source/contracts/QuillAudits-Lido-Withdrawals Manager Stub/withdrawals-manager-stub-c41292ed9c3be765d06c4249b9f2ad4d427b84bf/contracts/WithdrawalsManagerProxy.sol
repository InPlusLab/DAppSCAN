// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "OpenZeppelin/openzeppelin-contracts@4.0.0/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "OpenZeppelin/openzeppelin-contracts@4.0.0/contracts/utils/Address.sol";

import "./WithdrawalsManagerStub.sol";

/**
 * @dev Copied from https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.1.0/contracts/utils/StorageSlot.sol
 */
library StorageSlot {
    struct AddressSlot {
        address value;
    }

    function getAddressSlot(bytes32 slot) internal pure returns (AddressSlot storage r) {
        assembly {
            r.slot := slot
        }
    }
}

/**
 * @dev A proxy for Lido Ethereum 2.0 withdrawals manager contract.
 *
 * Though the Beacon chain already supports setting withdrawal credentials pointing to a smart
 * contract, the withdrawals specification is not yet final and might change before withdrawals
 * are enabled in the Merge network. This means that Lido cannot deploy the final implementation
 * of the withdrawals manager contract yet. At the same time, it's desirable to have withdrawal
 * credentials pointing to a smart contract since this would avoid the need to migrate a lot of
 * validators to new withdrawal credentials once withdrawals are enabled.
 *
 * To solve this, Lido uses an upgradeable proxy controlled by the DAO. Initially, it uses a stub
 * implementation contract, WithdrawalsManagerStub, that cannot receive Ether. The implementation
 * can only be changed by LDO holders collectively by performing a DAO vote. Lido will set validator
 * withdrawal credentials pointing to this proxy contract.
 *
 * When Ethereum 2.0 withdrawals specification is finalized, Lido DAO will prepare the new
 * implementation contract and initiate a vote among LDO holders for upgrading this proxy to the
 * new implementation.
 *
 * Once withdrawals are enabled in Ethereum 2.0, Lido DAO members will start a vote among LDO
 * holders for disabling the upgradeability forever and locking the implementation by changing
 * proxy admin from the DAO Voting contract to a zero address (which is an irreversible action).
 */
contract WithdrawalsManagerProxy is ERC1967Proxy {
    /**
     * @dev The address of Lido DAO Voting contract.
     */
    address internal constant LIDO_VOTING = 0x2e59A20f205bB85a89C53f1936454680651E618e;

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Initializes the upgradeable proxy with the initial stub implementation.
     */
    //  SWC-135-Code With No Effects: L71
    constructor() ERC1967Proxy(address(new WithdrawalsManagerStub()), new bytes(0)) {
        assert(ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        _setAdmin(LIDO_VOTING);
    }

    /**
     * @return Returns the current implementation address.
     */
    function implementation() external view returns (address) {
        return _implementation();
    }

    /**
     * @dev Upgrades the proxy to a new implementation, optionally performing an additional
     * setup call.
     *
     * Can only be called by the proxy admin until the proxy is ossified.
     * Cannot be called after the proxy is ossified.
     *
     * Emits an {Upgraded} event.
     *
     * @param setupCalldata Data for the setup call. The call is skipped if data is empty.
     */
    function proxy_upgradeTo(address newImplementation, bytes memory setupCalldata) external {
        address admin = _getAdmin();
        require(admin != address(0), "proxy: ossified");
        require(msg.sender == admin, "proxy: unauthorized");

        _upgradeTo(newImplementation);

        if (setupCalldata.length > 0) {
            Address.functionDelegateCall(newImplementation, setupCalldata, "proxy: setup failed");
        }
    }

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        StorageSlot.getAddressSlot(ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Returns the current admin of the proxy.
     */
    function proxy_getAdmin() external view returns (address) {
        return _getAdmin();
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function proxy_changeAdmin(address newAdmin) external {
        address admin = _getAdmin();
        require(msg.sender == admin, "proxy: unauthorized");
        emit AdminChanged(admin, newAdmin);
        _setAdmin(newAdmin);
    }

    /**
     * @dev Returns whether the implementation is locked forever.
     */
    function proxy_getIsOssified() external view returns (bool) {
        return _getAdmin() == address(0);
    }
}
