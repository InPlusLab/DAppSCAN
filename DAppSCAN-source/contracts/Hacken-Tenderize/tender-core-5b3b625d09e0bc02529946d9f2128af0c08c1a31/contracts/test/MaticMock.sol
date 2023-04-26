pragma solidity 0.8.4;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./MockStaking.sol";

contract MaticMock is MockStaking {
    uint256 public constant validatorId = 1;
    uint256 public constant exchangeRate = 100;

    constructor(IERC20 _token) MockStaking(_token) {}

    function owner() external view returns (address) {
        return msg.sender;
    }

    function restake() public {
        return;
    }

    function buyVoucher(uint256 _amount, uint256 _minSharesToMint) external reverted(this.buyVoucher.selector) {
        require(token.transferFrom(msg.sender, address(this), _amount));
        staked += _amount;
    }

    function sellVoucher_new(uint256 _claimAmount, uint256 _maximumSharesToBurn)
        external
        reverted(this.sellVoucher_new.selector)
    {
        staked -= _claimAmount;
        unstakeLocks[nextUnstakeLockID] = UnstakeLock({ amount: _claimAmount, account: msg.sender });
        nextUnstakeLockID++;
    }

    function unstakeClaimTokens_new(uint256 _unbondNonce) external reverted(this.unstakeClaimTokens_new.selector) {
        token.transfer(unstakeLocks[_unbondNonce].account, unstakeLocks[_unbondNonce].amount);
    }

    function balanceOf(address _from) external view returns (uint256) {
        return staked;
    }
}
