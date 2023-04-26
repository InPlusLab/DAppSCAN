// SPDX-License-Identifier: https://github.com/lendroidproject/protocol.2.0/blob/master/LICENSE.md
pragma solidity 0.7.4;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";


/** @title LPTokenWrapper
    @author Lendroid Foundation
    @notice Tracks the state of the LP Token staked / unstaked both in total
        and on a per account basis.
    @dev Audit certificate : Pending
*/


abstract contract LPTokenWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public lpToken;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    /**
        @notice Registers the LP Token address
        @param lpTokenAddress : address of the LP Token
    */
    constructor(address lpTokenAddress) {
      lpToken = IERC20(lpTokenAddress);
    }

    /**
        @notice Displays the total LP Token staked
        @return uint256 : value of the _totalSupply which stores total LP Tokens staked
    */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
        @notice Displays LP Token staked per account
        @param account : address of a user account
        @return uint256 : total LP staked by given account address
    */
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    /**
        @notice Stake / Deposit LP Token into the Pool
        @dev : Increases count of total LP Token staked.
               Increases count of LP Token staked for the msg.sender.
               LP Token is transferred from msg.sender to the Pool.
        @param amount : Amount of LP Token to stake
    */
    function stake(uint256 amount) virtual public {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        lpToken.safeTransferFrom(msg.sender, address(this), amount);
    }

    /**
        @notice Unstake / Withdraw staked LP Token from the Pool
        @dev : Decreases count of total LP Token staked
               Decreases count of LP Token staked for the msg.sender
               LP Token is transferred from the Pool to the msg.sender
        @param amount : Amount of LP Token to withdraw / unstake
    */
    function unstake(uint256 amount) virtual public {
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);
        lpToken.safeTransfer(msg.sender, amount);
    }
}
