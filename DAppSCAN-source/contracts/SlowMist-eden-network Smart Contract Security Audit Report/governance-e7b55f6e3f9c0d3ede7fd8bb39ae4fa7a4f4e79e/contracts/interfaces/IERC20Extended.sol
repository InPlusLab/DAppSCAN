// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20Metadata.sol";
import "./IERC20Mintable.sol";
import "./IERC20Burnable.sol";
import "./IERC20Permit.sol";
import "./IERC20TransferWithAuth.sol";
import "./IERC20SafeAllowance.sol";

interface IERC20Extended is 
    IERC20Metadata, 
    IERC20Mintable, 
    IERC20Burnable, 
    IERC20Permit,
    IERC20TransferWithAuth,
    IERC20SafeAllowance 
{}
    