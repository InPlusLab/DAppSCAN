// SPDX-License-Identifier: Apache-2.0

// File: contracts/lib/Administrable/Rescuable.sol

pragma solidity 0.6.12;
import "../access/AccessControlMixin.sol";
import "../SafeERC20.sol";

abstract contract Rescuable is AccessControlMixin {
    using SafeERC20 for IERC20;

    bytes32 public constant RESCUER_ROLE = keccak256("RESCUER_ROLE");

    event RescuerChanged(address indexed newRescuer);

    /**
     * @notice Return the members of the rescuer role
     * @return Addresses
     */
    function rescuers() external view returns (address[] memory) {
        uint256 count = getRoleMemberCount(RESCUER_ROLE);
        address[] memory list = new address[](count);

        for (uint256 i = 0; i < count; i++) {
            list[i] = getRoleMember(RESCUER_ROLE, i);
        }

        return list;
    }

    /**
     * @notice Rescue ERC20 tokens locked up in this contract.
     * @param tokenContract ERC20 token contract address
     * @param to        Recipient address
     * @param amount    Amount to withdraw
     */
    function rescueERC20(
        IERC20 tokenContract,
        address to,
        uint256 amount
    ) external only(RESCUER_ROLE) {
        tokenContract.safeTransfer(to, amount);
    }
}