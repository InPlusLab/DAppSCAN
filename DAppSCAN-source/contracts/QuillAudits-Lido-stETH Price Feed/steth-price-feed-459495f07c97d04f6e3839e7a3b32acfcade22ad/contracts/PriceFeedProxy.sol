// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "OpenZeppelin/openzeppelin-contracts@4.0.0/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "OpenZeppelin/openzeppelin-contracts@4.0.0/contracts/utils/Address.sol";

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

interface IPriceFeed {
    function initialize(
        uint256 maxSafePriceDifference,
        address stableSwapOracleAddress,
        address curvePoolAddress,
        address admin
    ) external;
}

contract PriceFeedProxy is ERC1967Proxy {
    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Emitted when the admin account has changed.
     */
    event AdminChanged(address previousAdmin, address newAdmin);

    /**
     * @dev Initializes the upgradeable proxy with an initial implementation
     *      specified by `priceFeedImpl`, calling its `initialize` function
     *      on the proxy contract state.
     */
    //  SWC-135-Code With No Effects: L59
    constructor(
        address priceFeedImpl,
        uint256 maxSafePriceDifference,
        address stableSwapOracleAddress,
        address curvePoolAddress,
        address admin
    )
        payable
        ERC1967Proxy(
            priceFeedImpl,
            abi.encodeWithSelector(
                IPriceFeed(address(0)).initialize.selector,
                maxSafePriceDifference,
                stableSwapOracleAddress,
                curvePoolAddress,
                admin
            )
        )
    {
        // SWC-135-Code With No Effects: L71
        assert(_ADMIN_SLOT == bytes32(uint256(keccak256("eip1967.proxy.admin")) - 1));
        _setAdmin(admin);
    }

    /**
     * @dev Returns the current implementation address.
     */
    function implementation() external view returns (address) {
        return _implementation();
    }

    /**
     * @dev Upgrades the proxy to a new implementation, optionally performing an additional setup call.
     *
     * Emits an {Upgraded} event.
     *
     * @param setupCalldata Data for the setup call. The call is skipped if data is empty.
     */
    function upgradeTo(address newImplementation, bytes memory setupCalldata) external {
        require(msg.sender == _getAdmin(), "ERC1967: unauthorized");
        _upgradeTo(newImplementation);
        if (setupCalldata.length > 0) {
            Address.functionDelegateCall(newImplementation, setupCalldata, "ERC1967: setup failed");
        }
    }

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
    }

    /**
     * @dev Stores a new address in the EIP1967 admin slot.
     */
    function _setAdmin(address newAdmin) private {
        StorageSlot.getAddressSlot(_ADMIN_SLOT).value = newAdmin;
    }

    /**
     * @dev Returns the current admin of the proxy.
     */
    function getProxyAdmin() external view returns (address) {
        return _getAdmin();
    }

    /**
     * @dev Changes the admin of the proxy.
     *
     * Emits an {AdminChanged} event.
     */
    function changeProxyAdmin(address newAdmin) external {
        address admin = _getAdmin();
        require(msg.sender == admin, "ERC1967: unauthorized");
        emit AdminChanged(admin, newAdmin);
        _setAdmin(newAdmin);
    }
}
