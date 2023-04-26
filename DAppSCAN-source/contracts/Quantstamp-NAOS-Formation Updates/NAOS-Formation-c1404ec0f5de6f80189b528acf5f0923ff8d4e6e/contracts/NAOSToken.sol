// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title NAOSToken
///
/// @dev This is the contract for the NAOS governance token.
contract NAOSToken is AccessControl, ERC20("NAOSToken", "NAOS") {
    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

    /// @dev The identifier of the role which allows accounts to mint tokens.
    bytes32 public constant MINTER_ROLE = keccak256("MINTER");

    /// @dev The address of default admin
    address public DEFAULT_ADMIN_ADDRESS;

    constructor() public {
        DEFAULT_ADMIN_ADDRESS = msg.sender;
        _setupRole(ADMIN_ROLE, DEFAULT_ADMIN_ADDRESS);
        _setupRole(MINTER_ROLE, DEFAULT_ADMIN_ADDRESS);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
    }

    /// @dev A modifier which checks that the caller has the minter role.
    modifier onlyMinter() {
        require(hasRole(MINTER_ROLE, msg.sender), "NAOSToken: only minter");
        _;
    }

    /// @dev Mints tokens to a recipient.
    ///
    /// This function reverts if the caller does not have the minter role.
    ///
    /// @param _recipient the account to mint tokens to.
    /// @param _amount    the amount of tokens to mint.
    function mint(address _recipient, uint256 _amount) external onlyMinter {
        _mint(_recipient, _amount);
    }
}
