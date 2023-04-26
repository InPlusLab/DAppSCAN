// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "./SinglePool.sol";
import "../interfaces/IERC20Metadata.sol";

contract SinglePoolFactory is Ownable {

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private pools;

    struct PoolView {
        address pool;
        address depositToken;
        address rewardsToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 totalAmount;
        uint256 startBlock;
        uint256 bonusEndBlock;
        string depositSymbol;
        string depositName;
        uint8 depositDecimals;
        string rewardsSymbol;
        string rewardsName;
        uint8 rewardsDecimals;
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 tokenBalance;
    }

    event NewPool(
        address pool, 
        address depositToken, 
        address rewardToken, 
        uint256 rewardPerBlock,
        uint256 startBlock,
        uint256 bonusEndBlock
    );

    constructor() public {

    }

    function createPool(
        IERC20 _depositToken,
        IERC20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock) public onlyOwner {
        
        SinglePool pool = new SinglePool(_depositToken, _rewardToken, _rewardPerBlock, _startBlock, _bonusEndBlock);
        pools.add(address(pool));

        emit NewPool(address(pool), address(_depositToken), address(_rewardToken), _rewardPerBlock, _startBlock, _bonusEndBlock);
    }

    function addPool(address pool) public onlyOwner {
        pools.add(pool);
    }

    function removePool(address pool) public onlyOwner {
        address owner = SinglePool(pool).owner();
        if(owner == address(this)) {
            SinglePool(pool).transferOwnership(msg.sender);
        }
        pools.remove(pool);
    }

    function getAllPoolViews() public view returns(PoolView[] memory){
        uint len = pools.length();
        PoolView[] memory views = new PoolView[](len);
        for (uint256 i = 0; i < len; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getPoolView(uint idx) public view returns(PoolView memory) {
        address pool = pools.at(idx);
        (IERC20 depositToken, uint256 allocPoint, uint256 lastRewardBlock, uint256 accRewardsPerShare) = SinglePool(pool).poolInfo(0);
        IERC20 rewardToken = SinglePool(pool).rewardToken();

        string memory depositSymbol = IERC20Metadata(address(depositToken)).symbol();
        string memory depositName = IERC20Metadata(address(depositToken)).name();
        uint8 depositDecimals = IERC20Metadata(address(depositToken)).decimals();

        string memory rewardSymbol = IERC20Metadata(address(rewardToken)).symbol();
        string memory rewardName = IERC20Metadata(address(rewardToken)).name();
        uint8 rewardDecimals = IERC20Metadata(address(rewardToken)).decimals();

        return
            PoolView({
                pool: pool,
                depositToken: address(depositToken),
                rewardsToken: address(rewardToken),
                allocPoint: allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: accRewardsPerShare,
                rewardsPerBlock: SinglePool(pool).rewardPerBlock(),
                totalAmount: SinglePool(pool).totalDeposit(),
                startBlock: SinglePool(pool).startBlock(),
                bonusEndBlock: SinglePool(pool).bonusEndBlock(),
                depositSymbol: depositSymbol,
                depositName: depositName,
                depositDecimals: depositDecimals,
                rewardsSymbol: rewardSymbol,
                rewardsName: rewardName,
                rewardsDecimals: rewardDecimals
            });
    }

    function getUserView(address pool, address account) public view returns (UserView memory) {
        (uint256 amount, ) = SinglePool(pool).userInfo(account);
        uint256 unclaimedRewards = SinglePool(pool).pendingReward(account);
        uint256 lpBalance = IERC20(SinglePool(pool).depositToken()).balanceOf(account);

        return
            UserView({
                stakedAmount: amount,
                unclaimedRewards: unclaimedRewards,
                tokenBalance: lpBalance
            });
    }

    function getUserViews(address account) external view returns (UserView[] memory) {
        address pool;
        uint len = pools.length();

        UserView[] memory views = new UserView[](len);
        for (uint256 i = 0; i < len; i++) {
            pool = pools.at(i);
            views[i] = getUserView(pool, account);
        }
        return views;
    }

    function stopReward(address pool) public onlyOwner {
        SinglePool(pool).stopReward();
    }

    function updateMultiplier(address pool, uint256 multiplierNumber) public onlyOwner {
        SinglePool(pool).updateMultiplier(multiplierNumber);
    }

    function emergencyRewardWithdraw(address pool, uint256 _amount) public onlyOwner {
        IERC20 token = IERC20(SinglePool(pool).rewardToken());
        uint256 oldAmount = token.balanceOf(address(this));
        SinglePool(pool).emergencyRewardWithdraw(_amount);
        uint256 amount = token.balanceOf(address(this)) - oldAmount;

        require(token.transfer(msg.sender, amount));
    }

}