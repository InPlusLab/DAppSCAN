// SPDX-License-Identifier: Apache-2.0

// File: contracts/lib/Administrable/Pausable.sol

pragma solidity 0.6.12;
import "../access/AccessControlMixin.sol";

abstract contract Pausable is AccessControlMixin {
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    event Pause();
    event Unpause();

    bool internal _paused = false;

    /**
     * @notice Throws if this contract is paused
     */
    modifier whenNotPaused() {
        require(!_paused, "Pausable: paused");
        _;
    }

    /**
     * @notice Return the members of the pauser role
     * @return Addresses
     */
    function pausers() external view returns (address[] memory) {
        uint256 count = getRoleMemberCount(PAUSER_ROLE);
        address[] memory list = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            list[i] = getRoleMember(PAUSER_ROLE, i);
        }

        return list;
    }

    /**
     * @notice Returns whether this contract is paused
     * @return True if paused
     */
    function paused() external view returns (bool) {
        return _paused;
    }

    /**
     * @notice Pause this contract
     */
    function pause() external only(PAUSER_ROLE) {
        _paused = true;
        emit Pause();
    }

    /**
     * @notice Unpause this contract
     */
    function unpause() external only(PAUSER_ROLE) {
        _paused = false;
        emit Unpause();
    }
}