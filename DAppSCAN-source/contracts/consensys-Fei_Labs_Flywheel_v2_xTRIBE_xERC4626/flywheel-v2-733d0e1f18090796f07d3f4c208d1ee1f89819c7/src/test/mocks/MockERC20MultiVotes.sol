// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity >=0.8.0;

import {ERC20MultiVotes, ERC20, Auth, Authority} from "../../token/ERC20MultiVotes.sol";

contract MockERC20MultiVotes is ERC20MultiVotes {
    constructor(address _owner) ERC20("Token", "TKN", 18) Auth(_owner, Authority(address(0))) {}

    function mint(address to, uint256 value) public virtual {
        _mint(to, value);
    }

    function burn(address from, uint256 value) public virtual {
        _burn(from, value);
    }
}
