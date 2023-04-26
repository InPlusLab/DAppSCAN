// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/IMdexHecoPool.sol";

// Connecting to third party pools
contract StrategyMDexPools {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IMdexHecoPool constant hecopool = IMdexHecoPool(0xFB03e11D93632D97a8981158A632Dd5986F5E909);
    address mdxToken = address(0x25D2e80cB6B86881Fd7e07dd263Fb79f4AbE033c);

    function poolDepositToken(uint256 _poolId) public virtual view returns (address lpToken) {
        (lpToken,,,,,) = hecopool.poolInfo(_poolId);
    }

    function poolRewardToken(uint256 _poolId) public virtual view returns (address rewardToken) {
        _poolId;
        rewardToken = mdxToken;
    }

    function poolPending(uint256 _poolId) public virtual view returns (uint256 rewards) {
        rewards = hecopool.pending(_poolId, address(this));
    }

    function poolTokenApprove(address _token, uint256 _value) internal virtual {
        IERC20(_token).approve(address(hecopool), _value);
    }

    function poolDeposit(uint256 _poolId, uint256 _lpAmount) internal virtual {
        hecopool.deposit(_poolId, _lpAmount);
    }

    function poolWithdraw(uint256 _poolId, uint256 _lpAmount) internal virtual {
        hecopool.withdraw(_poolId, _lpAmount);
    }

    function poolClaim(uint256 _poolId) internal virtual returns (uint256 rewards) {
        uint256 uBalanceBefore = IERC20(mdxToken).balanceOf(address(this));
        hecopool.deposit(_poolId, 0);
        uint256 uBalanceAfter = IERC20(mdxToken).balanceOf(address(this));
        rewards = uBalanceAfter.sub(uBalanceBefore);
    }
}
