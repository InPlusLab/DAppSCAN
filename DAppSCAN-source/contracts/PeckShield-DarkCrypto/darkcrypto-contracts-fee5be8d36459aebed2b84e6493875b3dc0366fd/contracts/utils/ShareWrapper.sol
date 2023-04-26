// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public share;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _stakeFor(msg.sender, amount);
    }

    function _stakeFor(address _account, uint256 _amount) internal {
        _totalSupply = _totalSupply.add(_amount);
        _balances[_account] = _balances[_account].add(_amount);
        share.safeTransferFrom(msg.sender, address(this), _amount);
    }

    function withdraw(uint256 _amount, uint256 _subtractedAmount) internal virtual {
        _withdraw(_amount, _subtractedAmount, true);
    }

    function _withdraw(uint256 _amount, uint256 _subtractedAmount, bool _tokenTransferred) internal {
        uint256 directorShare = _balances[msg.sender];
        require(directorShare >= _amount, "Boardroom: withdraw request greater than staked amount");
        _totalSupply = _totalSupply.sub(_amount);
        _balances[msg.sender] = directorShare.sub(_amount);
        if (_subtractedAmount > 0 && _tokenTransferred) {
            share.safeTransfer(msg.sender, _subtractedAmount);
        }
    }
}
