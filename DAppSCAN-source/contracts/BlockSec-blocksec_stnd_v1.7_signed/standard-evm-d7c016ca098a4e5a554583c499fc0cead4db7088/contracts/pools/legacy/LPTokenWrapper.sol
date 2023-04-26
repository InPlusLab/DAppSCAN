// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public lpt;

    uint256 private _totalInput;
    mapping(address => uint256) private _balances;

    function totalInput() public view returns (uint256) {
        return _totalInput;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalInput = _totalInput.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        lpt.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        _totalInput = _totalInput.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        lpt.safeTransfer(msg.sender, amount);
    }
}
