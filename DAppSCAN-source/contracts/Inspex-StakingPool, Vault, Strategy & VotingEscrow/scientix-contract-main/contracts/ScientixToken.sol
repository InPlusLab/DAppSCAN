// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

import {IDetailedERC20} from "./interfaces/IDetailedERC20.sol";

/// @title ScientixToken
///
/// @dev This is the contract for the Scientix governance token.
///
/// Initially, the contract deployer is given both the admin and minter role. This allows them to pre-mine tokens,
/// transfer admin to a timelock contract, and lastly, grant the staking pools the minter role. After this is done,
/// the deployer must revoke their admin role and minter role.
contract ScientixToken is AccessControl, ERC20("Scientix", "SCIX") {

  using SafeMath for uint256;

  /// @dev The identifier of the role which maintains other roles.
  bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");

  /// @dev The identifier of the role which allows accounts to mint tokens.
  bytes32 public constant MINTER_ROLE = keccak256("MINTER");

  uint256 public maxSupply;

  constructor() public {
    _setupRole(ADMIN_ROLE, msg.sender);
    _setupRole(MINTER_ROLE, msg.sender);
    _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
    _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);

    maxSupply = 1300000 ether;
  }

  /// @dev A modifier which checks that the caller has the minter role.
  modifier onlyMinter() {
    require(hasRole(MINTER_ROLE, msg.sender), "ScientixToken: only minter");
    _;
  }

  modifier onlyAdmin() {
    require(hasRole(ADMIN_ROLE, msg.sender), "ScientixToken: only admin");
    _;
  }

  /// @dev Mints tokens to a recipient.
  ///
  /// This function reverts if the caller does not have the minter role.
  ///
  /// @param _recipient the account to mint tokens to.
  /// @param _amount    the amount of tokens to mint.
  function mint(address _recipient, uint256 _amount) external onlyMinter {
    require(totalSupply().add(_amount) <= maxSupply, "ScientixToken: Maximum limit exceeded");
    _mint(_recipient, _amount);
  }

  function setMaxSupply(uint256 _amount) external onlyAdmin {
    maxSupply = _amount;
  }
}
