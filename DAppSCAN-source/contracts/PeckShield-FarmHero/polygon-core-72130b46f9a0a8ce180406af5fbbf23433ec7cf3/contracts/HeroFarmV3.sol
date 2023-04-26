// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./lib.sol";
import "./IERC721.sol";
import "./interfaces.sol";

contract HeroFarmV3 is OwnableUpgradeable, ReentrancyGuardUpgradeable, PausableUpgradeable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 shares; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint64  gracePeriod; // timestamp of that users can receive the staked LP/Token without deducting the transcation fee
        uint64  lastDepositBlock;       // the blocknumber of the user's last deposit

        // We do some fancy math here. Basically, any point in time, the amount of HERO
        // entitled to a user but is pending to be distributed is:
        //
        //   amount = user.shares / sharesTotal * wantLockedTotal
        //   pending reward = (amount * pool.accHEROPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws want tokens to a pool. Here's what happens:
        //   1. The pool's `accHEROPerShare` (and `lastRewardTime`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    enum PoolType { ERC20, ERC721, ERC1155 }

    struct PoolInfo {
        address want; // Address of the want token.
        PoolType poolType; //
        uint256 allocPoint; // How many allocation points assigned to this pool. HERO to distribute per block.
        uint256 lastRewardTime;  // Last time that HERO distribution occurs.
        uint256 accHEROPerShare; // Accumulated HERO per share, times 1e12. See below.
        address strat; // Strategy address that will auto compound want tokens
    }

    address public HERO;

    address public burnAddress;

    uint256 public startTime;
    uint256 public HERORewardPerSecond; // HERO tokens created per second
    uint256 public epochReduceRate; // */100
    uint256 public epochDuration;
    uint256 public totalEpoch;
    uint256 public HEROMaxSupply;

    uint256 public reservedNFTFarmingRate; // 30%
    address public reservedNFTFarmingAddress; 
    uint256 public teamRate;         // 7%
    address public teamAddress;      
    uint256 public communityRate;    // 5%;
    address public communityAddress; 
    uint256 public ecosystemRate;    // 23%
    address public ecosystemAddress; 
    uint256 public erc20PoolRate;    // 30%
    uint256 public erc721PoolRate;   // 5%
    address public feeAddress;
    bool public withdrawFee;

    PoolInfo[] public poolInfo; // Info of each pool.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo; // Info of each user that stakes LP tokens.
    mapping(PoolType => uint256) public totalAllocPoint; // Total allocation points. Must be the sum of all allocation points in all pools.

    address public rewardDistribution;
    bool public compoundNotFee;
    bool public compoundPaused;
    mapping(address => bool) public poolExistence ;

    mapping(address => address) public referrals;
    uint256 public referralRate;
    address public playerBook;
    uint256 public nftRewardRate;   // x/ 10000
    address public heroDistribution;
    mapping(address => bool) public feeExclude;
    mapping(address => bool) public skipEOA;

    function initialize(address _hero, uint256 _heroRewardPerSecond, address[] calldata _disAddresses) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init_unchained();
        
        HERO = _hero;
        burnAddress = 0x000000000000000000000000000000000000dEaD;
        HEROMaxSupply = 1000000000 * 1e18; // ten hundred million
        HERORewardPerSecond = _heroRewardPerSecond;
        totalEpoch = 21;
        epochDuration = 14 days;
        epochReduceRate= 90;
        withdrawFee = true;
        
        erc20PoolRate = 300;
        erc721PoolRate = 50;
        teamRate = 70;
        teamAddress = _disAddresses[0];
        communityRate = 50;
        communityAddress = _disAddresses[1];
        ecosystemRate = 230;
        ecosystemAddress = _disAddresses[2];
        reservedNFTFarmingRate = 300;
        reservedNFTFarmingAddress = _disAddresses[3];
        feeAddress = _disAddresses[4];
        nftRewardRate = 10000;
    }

    event DepositNTF(address indexed user, uint256 indexed pid, uint256[] tokenIds);
    event WithdrawNFT(address indexed user, uint256 indexed pid, uint256[] tokenIds);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event EmergencyWithdrawNFT(
        address indexed user,
        uint256 indexed pid,
        uint256[] tokenIds
    );
    event Compound(address indexed user, uint256 indexed pid, uint256 amount);
    event FeeExclude(address indexed user, bool exclude);
    event SkipEOA(address indexed user, bool skip);

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function totalDistributeRates() private returns (uint256) {
        return teamRate + communityRate + ecosystemRate + reservedNFTFarmingRate;
    }

    function totalPoolDistributeRates() private returns (uint256) {
        return erc20PoolRate + erc721PoolRate;
    }

    function setRewardDistribution(address _rewardDistribution) public virtual onlyOwner {
        rewardDistribution = _rewardDistribution;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do. (Only if want tokens are stored here.)

    // HFC-13
    modifier nonPoolDuplicated (address _watnToken ) {
        require(poolExistence[_watnToken] == false , "nonDuplicated: duplicated") ;
        _ ;
    }

    function add(
        uint256 _allocPoint,
        address _want,
        PoolType _poolType,
        bool _withUpdate,
        address _strat
    ) public onlyOwner nonReentrant nonPoolDuplicated(_want) {
        require(startTime > 0, "unknow startTime");

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardTime = now > startTime ? now : startTime;
        totalAllocPoint[_poolType] = totalAllocPoint[_poolType].add(_allocPoint);
        poolInfo.push(
            PoolInfo({
                want: _want,
                poolType: _poolType,
                allocPoint: _allocPoint,
                lastRewardTime: lastRewardTime,
                accHEROPerShare: 0,
                strat: _strat
            })
        );

        poolExistence[_want] = true;
    }

    // Update the given pool's HERO allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) public onlyOwner nonReentrant {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint[poolInfo[_pid].poolType] = totalAllocPoint[poolInfo[_pid].poolType].sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
        poolExistence[poolInfo[_pid].want] = _allocPoint > 0;
    }

    function startAt(uint256 _startTime) external onlyOwner {
        require(_startTime >= now, "invalid startTime");
        require(poolInfo.length == 0, "pool not empty");

        startTime = _startTime;
    }

    function setWithdrawFee(address _feeAddress, bool _enable) external onlyOwner{
        feeAddress = _feeAddress;
        withdrawFee = _enable;
    }

    function epochsPassed(uint _time) public view returns (uint256) {
        if (_time < startTime) {
            return 0;
        }
        // how long it has been since the beginning of mint period
        uint256 timePassed = _time.sub(startTime);
        // subtract the FIRST_EPOCH_DELAY, so that we can count all epochs as lasting 
        uint256 totalEpochsPassed = timePassed.div(epochDuration);
        // epochs don't count over TOTAL_EPOCHS
        if (totalEpochsPassed > totalEpoch) {
            return totalEpoch;
        }

        return totalEpochsPassed;
    }

    function epochReward(uint _epoch) public view returns (uint256 reward) {
        if (_epoch >= totalEpoch) {
            return HERORewardPerSecond.mul((epochReduceRate)**totalEpoch).div(100**totalEpoch);
        }
        return HERORewardPerSecond.mul((epochReduceRate)**_epoch).div(100**_epoch);
    }

    function epochsLeft() public view returns (uint256) {
        return totalEpoch.sub(epochsPassed(now));
    }

    function calculateReward(uint _before, uint _now) public view returns (uint256) {
        if (IERC20(HERO).totalSupply() >= HEROMaxSupply) {
            return 0;
        }

        uint _beforeEpoch = epochsPassed(_before); 
        uint _nowEpoch = epochsPassed(_now);
        if(_beforeEpoch == _nowEpoch){
            return _now.sub(_before).mul(epochReward(_beforeEpoch));
        }else if(_beforeEpoch + 1 == _nowEpoch){
            uint epochTime = _nowEpoch.mul(epochDuration).add(startTime);

            uint _beforeReward = epochTime.sub(_before).mul(epochReward(_beforeEpoch));
            uint _nowReward = _now.sub(epochTime).mul(epochReward(_nowEpoch));

            return _beforeReward.add(_nowReward);
        }else{
            uint _reward;
            uint _beforeEpochTime = (_beforeEpoch + 1).mul(epochDuration).add(startTime);
            uint _nowEpochTime = _nowEpoch.mul(epochDuration).add(startTime);

            uint _beforeReward = _beforeEpochTime.sub(_before).mul(epochReward(_beforeEpoch));
            uint _nowReward = _now.sub(_nowEpochTime).mul(epochReward(_nowEpoch));

            for(uint i = _beforeEpoch + 1 ; i < _nowEpoch; i++ ){
                _reward = _reward.add(epochReward(i).mul(epochDuration));
            }

            return _beforeReward.add(_nowReward).add(_reward);
            
        }
    }

    function _calcGracePeriod(uint256 gracePeriod, uint256 shareNew, uint256 shareAdd) internal view returns(uint256) {
        uint256 blockTime = block.timestamp;
        if (gracePeriod == 0) {
            // solium-disable-next-line
            return blockTime.add(180 days);
        }
        uint256 depositSec;
        // solium-disable-next-line
        if (blockTime >= gracePeriod) {
            depositSec = 180 days;
            return blockTime.add(depositSec.mul(shareAdd).div(shareNew));
        } else {
            // solium-disable-next-line
            depositSec = uint256(180 days).sub(gracePeriod.sub(blockTime));
            return gracePeriod.add(depositSec.mul(shareAdd).div(shareNew));
        }
    }

    function _calcFeeRateByGracePeriod(uint256 gracePeriod) internal view returns(uint256) {
        // solium-disable-next-line
        if (block.timestamp >= gracePeriod) {
            return 0;
        }
        // solium-disable-next-line
        uint256 leftSec = gracePeriod.sub(block.timestamp);

        if (leftSec < 90 days) {
            return 10;      // 0.1%
        } else if (leftSec < 150 days) {
            return 20;      // 0.2%
        } else if (leftSec < 166 days) {
            return 30;      // 0.3%
        } else if (leftSec < 173 days) {
            return 40;      // 0.4%
        } else {
            return 50;      // 0.5%
        }
    }

    // View function to see pending HERO on frontend.
    function pendingHERO(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accHEROPerShare = pool.accHEROPerShare;
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (now > pool.lastRewardTime && sharesTotal != 0) {
            uint256 HEROTotalReward = calculateReward(pool.lastRewardTime, now);
            uint256 HEROReward = HEROTotalReward.mul(_poolTypeRewardRate(pool.poolType)).div(1000)
                .mul(pool.allocPoint).div(
                    totalAllocPoint[pool.poolType]
                );
            uint256 rewardRate = pool.poolType == PoolType.ERC20 ? 10000 : nftRewardRate;
            accHEROPerShare = accHEROPerShare.add(
                HEROReward.mul(1e12).div(sharesTotal).mul(rewardRate).div(10000)
            );
        }
        return user.shares.mul(accHEROPerShare).div(1e12).sub(user.rewardDebt);
    }

    // View function to see staked Want tokens on frontend.
    function stakedWantTokens(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];

        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        if (sharesTotal == 0) {
            return 0;
        }
        return user.shares.mul(wantLockedTotal).div(sharesTotal);
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

        if (now <= pool.lastRewardTime) {
            return;
        }
        if(totalAllocPoint[pool.poolType]==0){
            return;
        }
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();
        if (sharesTotal == 0) {
            pool.lastRewardTime = now;
            return;
        }
        uint256 HEROTotalReward = calculateReward(pool.lastRewardTime, now);
        if(HEROTotalReward <= 0) {
            return;
        }
        uint256 HEROReward = HEROTotalReward.mul(_poolTypeRewardRate(pool.poolType)).div(1000)
            .mul(pool.allocPoint).div(
                totalAllocPoint[pool.poolType]
            );

        uint256 _totalDistributeRates = totalDistributeRates();
        // blockRewards * 65% * 30(5)/35
        uint256 HERO_DistributeRewards = HEROTotalReward.mul(_totalDistributeRates).div(1000)
            .mul(_poolTypeRewardRate(pool.poolType)).div(totalPoolDistributeRates())
            .mul(pool.allocPoint).div(
                totalAllocPoint[pool.poolType]
            );
        // HFC-01 | Unused local variables
        // distributeReservedNFTFarming  23%
        _mintHERO(reservedNFTFarmingAddress, 
            HERO_DistributeRewards.mul(reservedNFTFarmingRate).div(_totalDistributeRates));
        // distributeTeam                 7%
        _mintHERO(teamAddress, 
            HERO_DistributeRewards.mul(teamRate).div(_totalDistributeRates));
        // distributeCommunity            5%
        _mintHERO(communityAddress, 
            HERO_DistributeRewards.mul(communityRate).div(_totalDistributeRates));
        // distributeEcosystem            5%
        _mintHERO(ecosystemAddress, 
            HERO_DistributeRewards.mul(ecosystemRate).div(_totalDistributeRates));

        
        HEROToken(HERO).mint(address(this), HEROReward);

        uint256 rewardRate = pool.poolType == PoolType.ERC20 ? 10000 : nftRewardRate;

        pool.accHEROPerShare = pool.accHEROPerShare.add(
            HEROReward.mul(1e12).div(sharesTotal).mul(rewardRate).div(10000)
        );
        pool.lastRewardTime = now;
    }

    function _poolTypeRewardRate(PoolType _poolType) internal view returns (uint256){
        if(_poolType == PoolType.ERC20)
            return erc20PoolRate;
        else if(_poolType == PoolType.ERC721)
            return erc721PoolRate;
        else
            return 0;
    }

    function _mintHERO(address _mintTo, uint256 _mintAmt) internal returns(uint256){
        HEROToken(HERO).mint(
            _mintTo,
            _mintAmt
        );
        if(isContract(_mintTo))
            _notifyRewardAmount(_mintTo, _mintAmt);
        return _mintAmt;
    }

    function compound(uint256 _pid) public isEOA nonReentrant whenNotPaused {
        require(!compoundPaused, "compound paused");

        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(pool.want == HERO, "not support compound");

        uint256 wantLockedTotal =
            IStrategy(pool.strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(pool.strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw pending HERO
        uint256 pending =
            user.shares.mul(pool.accHEROPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (pending == 0) return;
        

        IERC20(pool.want).safeIncreaseAllowance(pool.strat, pending);
        uint256 sharesAdded =
        IStrategy(pool.strat).deposit(msg.sender, pending);
        user.shares = user.shares.add(sharesAdded);

        if(!compoundNotFee){
            user.gracePeriod = SafeMathExt.safe64(_calcGracePeriod(user.gracePeriod, uint256(user.shares), sharesAdded));
            user.lastDepositBlock = SafeMathExt.safe64(block.number);
        }

        user.rewardDebt = user.shares.mul(pool.accHEROPerShare).div(1e12);


        emit Compound(msg.sender, _pid, pending);
    }

    function _setUserReferral(string memory _referName) internal {

        if(playerBook == address(0)) return;

        if(referrals[msg.sender] != address(0)) return;

        address refer = IPlayerBook(playerBook).getPlayer(_referName);
        if(refer != address(0) && refer != IPlayerBook(playerBook).dev())
            referrals[msg.sender] = refer;
    }
    
    // Want tokens moved from user -> HEROFarm (HERO allocation) -> Strat (compounding)
    function deposit(uint256 _pid, uint256 _wantAmt, string memory _referName) public isEOA nonReentrant whenNotPaused {

        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(pool.poolType == PoolType.ERC20, "require erc20");

        _setUserReferral(_referName);

        if (user.shares > 0) {
            uint256 pending =
                user.shares.mul(pool.accHEROPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (pending > 0) {
                _withdrawReward(pending);
            }
        }
        if (_wantAmt > 0) {
            IERC20(pool.want).safeTransferFrom(
                address(msg.sender),
                address(this),
                _wantAmt
            );

            IERC20(pool.want).safeIncreaseAllowance(pool.strat, _wantAmt);

            if(!feeExclude[msg.sender]){
                uint256 entranceAmt = IStrategy(poolInfo[_pid].strat).entranceFeeFactor().mul(_wantAmt).div(10000);
                uint256 entranceFee = _wantAmt.sub(entranceAmt);
                if(entranceFee > 0) {
                    IERC20(pool.want).safeTransfer(feeAddress, entranceFee); 
                    _wantAmt = entranceAmt;
                }
            }

            uint256 sharesAdded =
                IStrategy(poolInfo[_pid].strat).deposit(msg.sender, _wantAmt);
            user.shares = user.shares.add(sharesAdded);

            user.gracePeriod = SafeMathExt.safe64(_calcGracePeriod(user.gracePeriod, uint256(user.shares), sharesAdded));
            user.lastDepositBlock = SafeMathExt.safe64(block.number);
        }
        user.rewardDebt = user.shares.mul(pool.accHEROPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _wantAmt);
    }

    function depositNFT(uint256 _pid, uint256[] memory _tokenIds, string memory _referName) public isEOA nonReentrant whenNotPaused {

        updatePool(_pid);
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(pool.poolType == PoolType.ERC721, "require ntf");

        _setUserReferral(_referName);

        if (user.shares > 0) {
            uint256 pending =
                user.shares.mul(pool.accHEROPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            if (pending > 0) {
                _withdrawReward(pending);
            }
        }
        if (_tokenIds.length > 0) {
            for(uint i = 0; i < _tokenIds.length; i++)
            {
                IERC721(pool.want).safeTransferFrom(
                    address(msg.sender),
                    address(this),
                    _tokenIds[i]
                );
                IERC721(pool.want).approve(pool.strat, _tokenIds[i]);
            }
            uint256 sharesAdded =
                IStrategy(poolInfo[_pid].strat).deposit(msg.sender, _tokenIds);
            user.shares = user.shares.add(sharesAdded);

            user.gracePeriod = SafeMathExt.safe64(_calcGracePeriod(user.gracePeriod, uint256(user.shares), sharesAdded));
            user.lastDepositBlock = SafeMathExt.safe64(block.number);
        }
        user.rewardDebt = user.shares.mul(pool.accHEROPerShare).div(1e12);
        
        emit DepositNTF(msg.sender, _pid, _tokenIds);
    }

    function _withdrawReward(uint256 pending) internal {
        address refer = referrals[msg.sender];
        if(refer == address(0) && playerBook != address(0))
            refer = IPlayerBook(playerBook).dev();
        
        uint referFee;
        if(refer != address(0)){
            referFee = pending.mul(referralRate).div(10000);
        }
        uint256 leftPending = pending.sub(referFee);

        if(heroDistribution == address(0)){
            if(referFee > 0)
                safeHEROTransfer(refer, referFee);
            safeHEROTransfer(msg.sender, leftPending);
        }else{
            safeHEROTransfer(heroDistribution, pending);
            if(referFee > 0)
                IFeeDistribution(heroDistribution).mint(refer, referFee);
            IFeeDistribution(heroDistribution).mint(msg.sender, leftPending);
        }
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _wantAmt) public isEOA nonReentrant whenNotPaused {

        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(pool.poolType == PoolType.ERC20, "invalid erc20");

        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw pending HERO
        uint256 pending =
            user.shares.mul(pool.accHEROPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (pending > 0) {
            _withdrawReward(pending);
        }

        // Withdraw want tokens
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);
        if (_wantAmt > amount) {
            _wantAmt = amount;
        }
        if (_wantAmt > 0) {
            uint256 sharesRemoved =
                IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, _wantAmt);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            uint256 wantBal = IERC20(pool.want).balanceOf(address(this));
            if (wantBal < _wantAmt) {
                _wantAmt = wantBal;
            }
            if(withdrawFee || !feeExclude[msg.sender]) {
                uint256 feeRate = _calcFeeRateByGracePeriod(uint256(user.gracePeriod));
                if(feeRate > 0){
                    uint256 feeAmount = _wantAmt.mul(feeRate).div(10000);
                    _wantAmt = _wantAmt.sub(feeAmount);
                    IERC20(pool.want).safeTransfer(feeAddress, feeAmount);
                }
            }
            IERC20(pool.want).safeTransfer(address(msg.sender), _wantAmt);
        }

        if(_wantAmt == 0 && rewardDistribution!=address(0)) {
            IRewardDistribution(rewardDistribution).earn(address(this));
        }

        user.rewardDebt = user.shares.mul(pool.accHEROPerShare).div(1e12);

        // If user withdraws all the LPs, then gracePeriod is cleared
        if (user.shares == 0) {
            user.gracePeriod = 0;
        }

        emit Withdraw(msg.sender, _pid, _wantAmt);
    }

    function withdrawNFT(uint256 _pid, uint256[] memory _tokenIds) public isEOA nonReentrant whenNotPaused {

        updatePool(_pid);

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        require(pool.poolType == PoolType.ERC721, "invalid erc721");

        // uint256 wantLockedTotal =
        //     IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();

        require(user.shares > 0, "user.shares is 0");
        require(sharesTotal > 0, "sharesTotal is 0");

        // Withdraw pending HERO
        uint256 pending =
            user.shares.mul(pool.accHEROPerShare).div(1e12).sub(
                user.rewardDebt
            );
        if (pending > 0) {
            _withdrawReward(pending);
        }

        if (_tokenIds.length > 0) {
            uint256 sharesRemoved =
                IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, _tokenIds);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            for(uint i = 0; i < _tokenIds.length; i++)
            {
                IERC721(pool.want).transferFrom(address(this), msg.sender, _tokenIds[i]);
            }

        }
        user.rewardDebt = user.shares.mul(pool.accHEROPerShare).div(1e12);
        
        // If user withdraws all the LPs, then gracePeriod is cleared
        if (user.shares == 0) {
            user.gracePeriod = 0;
        }
        emit WithdrawNFT(msg.sender, _pid, _tokenIds);
    }

    function withdrawAll(uint256 _pid) public isEOA {

        withdraw(_pid, uint256(-1));
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public isEOA nonReentrant {

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(pool.poolType == PoolType.ERC20, "invalid erc20");

        uint256 wantLockedTotal =
            IStrategy(poolInfo[_pid].strat).wantLockedTotal();
        uint256 sharesTotal = IStrategy(poolInfo[_pid].strat).sharesTotal();
        uint256 amount = user.shares.mul(wantLockedTotal).div(sharesTotal);

        IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, amount);

        if(withdrawFee && !feeExclude[msg.sender]) {
            uint256 feeRate = _calcFeeRateByGracePeriod(uint256(user.gracePeriod));
            if(feeRate > 0){
                uint256 feeAmount = amount.mul(feeRate).div(10000);
                amount = amount.sub(feeAmount);
                IERC20(pool.want).safeTransfer(feeAddress, feeAmount);
            }
        }

        IERC20(pool.want).safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
        user.shares = 0;
        user.rewardDebt = 0;
        user.gracePeriod = 0;
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdrawNFT(uint256 _pid, uint256[] memory _tokenIds) public isEOA nonReentrant {
        
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(pool.poolType == PoolType.ERC721, "invalid erc721");

        if (_tokenIds.length > 0) {
            uint256 sharesRemoved =
                IStrategy(poolInfo[_pid].strat).withdraw(msg.sender, _tokenIds);

            if (sharesRemoved > user.shares) {
                user.shares = 0;
            } else {
                user.shares = user.shares.sub(sharesRemoved);
            }

            for(uint i = 0; i < _tokenIds.length; i++)
            {
                IERC721(pool.want).transferFrom(address(this), msg.sender, _tokenIds[i]);
            }

        }

        emit EmergencyWithdrawNFT(msg.sender, _pid, _tokenIds);
        user.shares = 0;
        user.rewardDebt = 0;
        user.gracePeriod = 0;
    }

    // Safe HERO transfer function, just in case if rounding error causes pool to not have enough
    function safeHEROTransfer(address _to, uint256 _HEROAmt) internal {
        uint256 HEROBal = IERC20(HERO).balanceOf(address(this));
        if (_HEROAmt > HEROBal) {
            IERC20(HERO).transfer(_to, HEROBal);
        } else {
            IERC20(HERO).transfer(_to, _HEROAmt);
        }
    }

    function inCaseTokensGetStuck(address _token, uint256 _amount)
        public
        onlyOwner
    {
        require(_token != HERO, "!safe");
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function setPlaybook(address _playerBook, uint256 _referralRate) external onlyOwner {

        playerBook = _playerBook;
        referralRate = _referralRate;
    }

    function setReferralRate(uint256 _referralRate) external onlyOwner {
        referralRate = _referralRate;
    }

    function setHEROMaxSupply(uint256 _supply) external onlyOwner {
        HEROMaxSupply = _supply;
    }

    function setEpochDuration(uint256 _epochDuration) external onlyOwner {
        require(_epochDuration > 0);
        epochDuration = _epochDuration;
    }

    function setEpochReduceRate(uint256 _epochReduceRate) external onlyOwner {
        epochReduceRate = _epochReduceRate;
    }

    function setTotalEpoch(uint256 _totalEpoch) external onlyOwner {
        totalEpoch = _totalEpoch;
    }

    function setCompoundPaused(bool _paused) external onlyOwner {
        compoundPaused = _paused;
    }

    function setCompoundNotFee(bool _notFee) external onlyOwner {
        compoundNotFee = _notFee;
    }

    function setNftRewardRate(uint256 _rate) external onlyOwner {
        nftRewardRate = _rate;
    }

    function setHeroDistribution(address _heroDistribution) external onlyOwner {
        heroDistribution = _heroDistribution;
    }

    function isContract(address account) internal view returns (bool) {
      // According to EIP-1052, 0x0 is the value returned for not-yet created accounts
      // and 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470 is returned
      // for accounts without code, i.e. `keccak256('')`
      bytes32 codehash;
      bytes32 accountHash = 0xc5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470;
      // solhint-disable-next-line no-inline-assembly
      assembly { codehash := extcodehash(account) }
      return (codehash != accountHash && codehash != 0x0);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4){
        return 0x150b7a02;
    }

    function setAddresses(address _reservedNFTFarmingAddress, address _teamAddress, address _communityAddress, address _ecosystemAddress) external onlyOwner {
        reservedNFTFarmingAddress = _reservedNFTFarmingAddress;
        teamAddress = _teamAddress;
        communityAddress = _communityAddress;
        ecosystemAddress = _ecosystemAddress;
    }

    modifier isEOA() {
        require(tx.origin == msg.sender || skipEOA[msg.sender], "not EOA");
        _;
    }

    function setRates(uint256 _teamRate, uint256 _communityRate, uint256 _ecosystemRate, uint256 _reservedNFTFarmingRate) external onlyOwner {
        teamRate = _teamRate;
        communityRate = _communityRate;
        ecosystemRate = _ecosystemRate;
        reservedNFTFarmingRate = _reservedNFTFarmingRate;
    }

    function _notifyRewardAmount(address _addr, uint256 _reward) internal returns (bool success, bytes memory data) {
        // You can send ether and specify a custom gas amount
        (success, data) = _addr.call(
            abi.encodeWithSignature("notifyRewardAmount(uint256)", _reward)
        );
    }

    function setFeeExclude(address _user) external onlyOwner {
        require(_user != address(0));
        feeExclude[_user] = true;
        emit FeeExclude(_user, true);
    }

    function setSkipEOA(address _user) external onlyOwner {
        require(_user != address(0));
        skipEOA[_user] = true;
        emit SkipEOA(_user, true);
    }
}