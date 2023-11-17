// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./libraries/ERC20Permit.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";

contract FountainToken is ERC20Permit {
    constructor(string memory name_, string memory symbol_)
        public
        ERC20(name_, symbol_)
        ERC20Permit(name_)
    {}

    function transferFromWithPermit(
        address owner,
        address recipient,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public returns (bool) {
        permit(owner, msg.sender, value, deadline, v, r, s);
        return transferFrom(owner, recipient, value);
    }
}
