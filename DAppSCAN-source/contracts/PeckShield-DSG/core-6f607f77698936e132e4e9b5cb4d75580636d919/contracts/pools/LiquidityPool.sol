// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../token/DSGToken.sol";
import "../interfaces/ISwapPair.sol";
import "../interfaces/IDsgNft.sol";
import "../interfaces/IERC20Metadata.sol";

contract LiquidityPool is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _pairs;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt.
        uint256 rewardPending; //Rewards that have been settled and pending
        uint256 accRewardAmount; // How many rewards the user has got.
        uint256 additionalNftId; //Nft used to increase revenue
        uint256 additionalRate; //nft additional rate of reward, base 10000
        uint256 additionalAmount; //nft additional amount of share
    }

    struct UserView {
        uint256 stakedAmount;
        uint256 unclaimedRewards;
        uint256 lpBalance;
        uint256 accRewardAmount;
        uint256 additionalNftId; //Nft used to increase revenue
        uint256 additionalRate; //nft additional rate of reward
    }

    // Info of each pool.
    struct PoolInfo {
        address lpToken; // Address of LP token contract.
        address additionalNft; //Nft for users to increase share rate
        uint256 allocPoint; // How many allocation points assigned to this pool. reward tokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that reward tokens distribution occurs.
        uint256 accRewardPerShare; // Accumulated reward tokens per share, times 1e12.
        uint256 totalAmount; // Total amount of current pool deposit.
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        uint256 accDonateAmount;
    }

    struct PoolView {
        uint256 pid;
        address lpToken;
        address additionalNft;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 rewardsPerBlock;
        uint256 accRewardPerShare;
        uint256 allocRewardAmount;
        uint256 accRewardAmount;
        uint256 totalAmount;
        address token0;
        string symbol0;
        string name0;
        uint8 decimals0;
        address token1;
        string symbol1;
        string name1;
        uint8 decimals1;
    }

    // The reward token!
    DSGToken public rewardToken;
    // reward tokens created per block.
    uint256 public rewardTokenPerBlock;

    address public feeWallet;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // pid corresponding address
    mapping(address => uint256) public LpOfPid;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when token mining starts.
    uint256 public startBlock;
    uint256 public halvingPeriod = 3952800; // half year

    uint256[] public additionalRate = [0, 300, 400, 500, 600, 800, 1000]; //The share ratio that can be increased by each level of nft
    uint256 public nftSlotFee = 1e18; //Additional nft requires a card slot, enable the card slot requires fee

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Donate(address indexed user, uint256 pid, uint256 donateAmount, uint256 realAmount);
    event AdditionalNft(address indexed user, uint256 pid, uint256 nftId);

    constructor(
        DSGToken _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        address _feeWallet
    ) public {
        rewardToken = _rewardToken;
        rewardTokenPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        feeWallet = _feeWallet;
    }

    function phase(uint256 blockNumber) public view returns (uint256) {
        if (halvingPeriod == 0) {
            return 0;
        }
        if (blockNumber > startBlock) {
            return (blockNumber.sub(startBlock)).div(halvingPeriod);
        }
        return 0;
    }

    function getRewardTokenPerBlock(uint256 blockNumber) public view returns (uint256) {
        uint256 _phase = phase(blockNumber);
        return rewardTokenPerBlock.div(2**_phase);
    }

    function getRewardTokenBlockReward(uint256 _lastRewardBlock) public view returns (uint256) {
        uint256 blockReward = 0;
        uint256 lastRewardPhase = phase(_lastRewardBlock);
        uint256 currentPhase = phase(block.number);
        while (lastRewardPhase < currentPhase) {
            lastRewardPhase++;
            uint256 height = lastRewardPhase.mul(halvingPeriod).add(startBlock);
            blockReward = blockReward.add((height.sub(_lastRewardBlock)).mul(getRewardTokenPerBlock(height)));
            _lastRewardBlock = height;
        }
        blockReward = blockReward.add((block.number.sub(_lastRewardBlock)).mul(getRewardTokenPerBlock(block.number)));
        return blockReward;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        address _lpToken,
        address _additionalNft,
        bool _withUpdate
    ) public onlyOwner {
        require(_lpToken != address(0), "LiquidityPool: _lpToken is the zero address");
        require(ISwapPair(_lpToken).token0() != address(0), "not lp");

        require(!EnumerableSet.contains(_pairs, _lpToken), "LiquidityPool: _lpToken is already added to the pool");
        // return EnumerableSet.add(_pairs, _lpToken);
        EnumerableSet.add(_pairs, _lpToken);

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                additionalNft: _additionalNft,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0,
                accDonateAmount: 0,
                totalAmount: 0,
                allocRewardAmount: 0,
                accRewardAmount: 0
            })
        );
        LpOfPid[_lpToken] = getPoolLength() - 1;
    }

    function setAdditionalNft(uint256 _pid, address _additionalNft) public onlyOwner {
        require(poolInfo[_pid].additionalNft == address(0), "already set");

        poolInfo[_pid].additionalNft = _additionalNft;
    }

    function setNftSlotFee(uint256 val) public onlyOwner {
        nftSlotFee = val;
    }

    function getAdditionalRates() public view returns(uint256[] memory) {
        return additionalRate;
    }

    // Update the given pool's reward token allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }

        if (pool.totalAmount == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }

        uint256 blockReward = getRewardTokenBlockReward(pool.lastRewardBlock);

        if (blockReward <= 0) {
            return;
        }

        uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);

        bool minRet = rewardToken.mint(address(this), tokenReward);
        if (minRet) {
            pool.accRewardPerShare = pool.accRewardPerShare.add(tokenReward.mul(1e12).div(pool.totalAmount));
            pool.allocRewardAmount = pool.allocRewardAmount.add(tokenReward);
            pool.accRewardAmount = pool.accRewardAmount.add(tokenReward);
        }
        pool.lastRewardBlock = block.number;
    }

    function donate(uint256 donateAmount) public {
        uint256 oldBal = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), donateAmount);
        uint256 realAmount = IERC20(rewardToken).balanceOf(address(this)) - oldBal;

        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);

            PoolInfo storage pool = poolInfo[pid];
            if(pool.allocPoint == 0) {
                continue;
            }
            require(pool.totalAmount > 0, "no lp staked");

            uint256 tokenReward = realAmount.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accRewardPerShare = pool.accRewardPerShare.add(tokenReward.mul(1e12).div(pool.totalAmount));
            pool.allocRewardAmount = pool.allocRewardAmount.add(tokenReward);
            pool.accDonateAmount = pool.accDonateAmount.add(tokenReward);
        }

        emit Donate(msg.sender, 100000, donateAmount, realAmount);
    }

    function donateToPool(uint256 pid, uint256 donateAmount) public {
        updatePool(pid);

        PoolInfo storage pool = poolInfo[pid];
        require(pool.allocPoint > 0, "pool closed");

        require(pool.totalAmount > 0, "no lp staked");

        uint256 oldBal = IERC20(rewardToken).balanceOf(address(this));
        IERC20(rewardToken).safeTransferFrom(msg.sender, address(this), donateAmount);
        uint256 realAmount = IERC20(rewardToken).balanceOf(address(this)) - oldBal;

        pool.accRewardPerShare = pool.accRewardPerShare.add(realAmount.mul(1e12).div(pool.totalAmount));
        pool.allocRewardAmount = pool.allocRewardAmount.add(realAmount);
        pool.accDonateAmount = pool.accDonateAmount.add(realAmount);

        emit Donate(msg.sender, pid, donateAmount, realAmount);
    }

    function additionalNft(uint256 _pid, uint256 nftId) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.additionalNftId == 0, "nft already set");
        updatePool(_pid);

        uint256 level = IDsgNft(pool.additionalNft).getLevel(nftId);
        require(level > 0, "no level");

        if(nftSlotFee > 0) {
            IERC20(rewardToken).safeTransferFrom(msg.sender, feeWallet, nftSlotFee);
        }

        IDsgNft(pool.additionalNft).safeTransferFrom(msg.sender, address(this), nftId);
        IDsgNft(pool.additionalNft).burn(nftId);

        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
            user.rewardPending = user.rewardPending.add(pending);
        }

        user.additionalNftId = nftId;
        user.additionalRate = additionalRate[level];
        
        user.additionalAmount = user.amount.mul(user.additionalRate).div(10000);
        pool.totalAmount = pool.totalAmount.add(user.additionalAmount);

        user.rewardDebt = user.amount.add(user.additionalAmount).mul(pool.accRewardPerShare).div(1e12);
        emit AdditionalNft(msg.sender, _pid, nftId);
    }

    function deposit(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        uint256 pending = user.amount.add(user.additionalAmount).mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        user.rewardPending = user.rewardPending.add(pending);

        if (_amount > 0) {
            IERC20(pool.lpToken).safeTransferFrom(msg.sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
            pool.totalAmount = pool.totalAmount.add(_amount);
            if(user.additionalRate > 0) {
                uint256 _add = _amount.mul(user.additionalRate).div(10000);
                user.additionalAmount = user.additionalAmount.add(_add);
                pool.totalAmount = pool.totalAmount.add(_add);
            }
        }

        user.rewardDebt = user.amount.add(user.additionalAmount).mul(pool.accRewardPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function harvest(uint256 _pid) public {
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        uint256 pendingAmount = user.amount.add(user.additionalAmount).mul(pool.accRewardPerShare).div(1e12).sub(user.rewardDebt);
        pendingAmount = pendingAmount.add(user.rewardPending);
        user.rewardPending = 0;
        if (pendingAmount > 0) {
            safeRewardTokenTransfer(msg.sender, pendingAmount);
            user.accRewardAmount = user.accRewardAmount.add(pendingAmount);
            pool.allocRewardAmount = pool.allocRewardAmount.sub(pendingAmount);
        }

        // pool.totalAmount = pool.totalAmount.sub(user.additionalAmount);
        // user.additionalAmount = 0;
        // user.additionalRate = 0;
        // user.additionalNftId = 0;
        user.rewardDebt = user.amount.add(user.additionalAmount).mul(pool.accRewardPerShare).div(1e12);
    }

    function pendingRewards(uint256 _pid, address _user) public view returns (uint256) {
        require(_pid <= poolInfo.length - 1, "LiquidityPool: Can not find this pool");

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;

        uint256 pending = 0;
        uint256 amount = user.amount.add(user.additionalAmount);
        if (amount > 0) {
            if (block.number > pool.lastRewardBlock) {
                uint256 blockReward = getRewardTokenBlockReward(pool.lastRewardBlock);
                uint256 tokenReward = blockReward.mul(pool.allocPoint).div(totalAllocPoint);
                accRewardPerShare = accRewardPerShare.add(tokenReward.mul(1e12).div(pool.totalAmount));
                pending = amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
            } else if (block.number == pool.lastRewardBlock) {
                pending = amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt);
            }
        }
        pending = pending.add(user.rewardPending);
        return pending;
    }

    function withdraw(uint256 _pid, uint256 _amount) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "LiquidityPool: withdraw not good");
        updatePool(_pid);

        harvest(_pid);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.totalAmount = pool.totalAmount.sub(_amount);
            IERC20(pool.lpToken).safeTransfer(msg.sender, _amount);
            
            pool.totalAmount = pool.totalAmount.sub(user.additionalAmount);
            user.additionalAmount = 0;
            user.additionalRate = 0;
            user.additionalNftId = 0;
        }
        user.rewardDebt = user.amount.add(user.additionalAmount).mul(pool.accRewardPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function harvestAll() public {
        for (uint256 i = 0; i < poolInfo.length; i++) {
            harvest(i);
        }
    }

    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        uint256 additionalAmount = user.additionalAmount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.additionalAmount = 0;
        user.additionalRate = 0;
        user.additionalNftId = 0;

        IERC20(pool.lpToken).safeTransfer(msg.sender, amount);

        if (pool.totalAmount >= amount) {
            pool.totalAmount = pool.totalAmount.sub(amount);
        }
        
        if(pool.totalAmount >= additionalAmount) {
            pool.totalAmount = pool.totalAmount.sub(additionalAmount);
        }
        
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeRewardTokenTransfer(address _to, uint256 _amount) internal {
        uint256 rewardTokenBalance = rewardToken.balanceOf(address(this));
        if (_amount > rewardTokenBalance) {
            IERC20(address(rewardToken)).safeTransfer(_to, rewardTokenBalance);
        } else {
            IERC20(address(rewardToken)).safeTransfer(_to, _amount);
        }
    }

    // Set the number of reward token produced by each block
    function setRewardTokenPerBlock(uint256 _newPerBlock) public onlyOwner {
        massUpdatePools();
        rewardTokenPerBlock = _newPerBlock;
    }

    function setHalvingPeriod(uint256 _block) public onlyOwner {
        halvingPeriod = _block;
    }

    function getPairsLength() public view returns (uint256) {
        return EnumerableSet.length(_pairs);
    }

    function getPairs(uint256 _index) public view returns (address) {
        require(_index <= getPairsLength() - 1, "LiquidityPool: index out of bounds");
        return EnumerableSet.at(_pairs, _index);
    }

    function getPoolLength() public view returns (uint256) {
        return poolInfo.length;
    }

    function getAllPools() external view returns (PoolInfo[] memory) {
        return poolInfo;
    }

    function getPoolView(uint256 pid) public view returns (PoolView memory) {
        require(pid < poolInfo.length, "LiquidityPool: pid out of range");
        PoolInfo memory pool = poolInfo[pid];
        address lpToken = pool.lpToken;
        IERC20 token0 = IERC20(ISwapPair(lpToken).token0());
        IERC20 token1 = IERC20(ISwapPair(lpToken).token1());
        string memory symbol0 = IERC20Metadata(address(token0)).symbol();
        string memory name0 = IERC20Metadata(address(token0)).name();
        uint8 decimals0 = IERC20Metadata(address(token0)).decimals();
        string memory symbol1 = IERC20Metadata(address(token1)).symbol();
        string memory name1 = IERC20Metadata(address(token1)).name();
        uint8 decimals1 = IERC20Metadata(address(token1)).decimals();
        uint256 rewardsPerBlock = pool.allocPoint.mul(rewardTokenPerBlock).div(totalAllocPoint);
        return
            PoolView({
                pid: pid,
                lpToken: lpToken,
                additionalNft: pool.additionalNft,
                allocPoint: pool.allocPoint,
                lastRewardBlock: pool.lastRewardBlock,
                accRewardPerShare: pool.accRewardPerShare,
                rewardsPerBlock: rewardsPerBlock,
                allocRewardAmount: pool.allocRewardAmount,
                accRewardAmount: pool.accRewardAmount,
                totalAmount: pool.totalAmount,
                token0: address(token0),
                symbol0: symbol0,
                name0: name0,
                decimals0: decimals0,
                token1: address(token1),
                symbol1: symbol1,
                name1: name1,
                decimals1: decimals1
            });
    }

    function getPoolViewByAddress(address lpToken) public view returns (PoolView memory) {
        uint256 pid = LpOfPid[lpToken];
        return getPoolView(pid);
    }

    function getAllPoolViews() external view returns (PoolView[] memory) {
        PoolView[] memory views = new PoolView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            views[i] = getPoolView(i);
        }
        return views;
    }

    function getUserView(address lpToken, address account) public view returns (UserView memory) {
        uint256 pid = LpOfPid[lpToken];
        UserInfo memory user = userInfo[pid][account];
        uint256 unclaimedRewards = pendingRewards(pid, account);
        uint256 lpBalance = ERC20(lpToken).balanceOf(account);
        return
            UserView({
                stakedAmount: user.amount,
                unclaimedRewards: unclaimedRewards,
                lpBalance: lpBalance,
                accRewardAmount: user.accRewardAmount,
                additionalNftId: user.additionalNftId,
                additionalRate: user.additionalRate
            });
    }

    function getUserViews(address account) external view returns (UserView[] memory) {
        address lpToken;
        UserView[] memory views = new UserView[](poolInfo.length);
        for (uint256 i = 0; i < poolInfo.length; i++) {
            lpToken = address(poolInfo[i].lpToken);
            views[i] = getUserView(lpToken, account);
        }
        return views;
    }

    function onERC721Received(address, address, uint256, bytes memory) public returns (bytes4) {
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }
}
