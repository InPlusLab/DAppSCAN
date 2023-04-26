// SPDX-License-Identifier: Apache-2.0

// File: contracts/lib/AccessControlMixin.sol

pragma solidity 0.6.12;
import "./AccessControl.sol";

contract AccessControlMixin is AccessControl {
    string private _revertMsg;

    function _setupContractId(string memory contractId) internal {
        _revertMsg = string(
            abi.encodePacked(contractId, ": INSUFFICIENT_PERMISSIONS")
        );
    }

    modifier only(bytes32 role) {
        require(hasRole(role, _msgSender()), _revertMsg);
        _;
    }
}