// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;
// SWC-103-Floating Pragma: L2
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import './utils/Counters.sol';
import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IWBNB.sol";
import './tokens/LuckyToken.sol';

contract RevenueSharingPool is Ownable {
    // Utility Libraries  
    using SafeERC20 for IERC20;
    using Counters for Counters.Counter;
    Counters.Counter private _roundId;

    // swap token related variables
    IERC20 public luckyBusd;
    IERC20 public lucky;
    IERC20 public BUSD;
    IWBNB public wNative;
    IPancakeRouter02 public exchangeRouter;
    
    // contract global variables
    uint256 MAX_NUMBER;
    uint256 public START_ROUND_DATE;
    uint256 public MAX_DATE = 7;
    
    // staking related variables
    mapping(uint256 => mapping(uint256 => uint256)) public totalStake;
    mapping(uint256 => uint256) public totalLuckyRevenue;
    mapping(uint256 => mapping(uint256 => mapping(address => uint256))) stakeAmount; // SWC-108-State Variable Default Visibility: L33
    
    mapping(address => bool) public whitelists;
    
    // user info variables
    struct UserInfo {
        uint256 amount;
        uint256 rewardDept;
        uint256 pendingReward;
        uint256 lastUpdateRoundId;
    }
    
    mapping(address => UserInfo) public userInfo;
    
    // pool info
    struct PoolInfo {
	    uint256 winRate;
	    uint256 TPV;
	    uint256 buyBack;
	    uint256 TVL;
    }
    
    mapping(uint256 => PoolInfo) public poolInfo; //

    event DepositStake(address indexed account, uint256 amount, uint256 timestamp);
    event WithdrawStake(address indexed account, uint256 amount, uint256 timestamp);
    event ClaimReward(address indexed account, uint256 amount, uint256 timestamp);
    event DistributeLuckyRevenue(address from, address to, uint256 amounts);

    struct InputToken {
        address token;
        uint256 amount;
        address[] tokenToBUSDPath;
    }
    
    modifier isWhitelisted(address addr) {
        require(whitelists[addr], "Permission Denied");
        _;
    }

    constructor (
        address _lucky,
        address _luckyBusd,
        address owner_,
        IPancakeRouter02 _exchangeRouter,
        address _busd,
        address _wNative
    ) public {
        exchangeRouter = IPancakeRouter02(_exchangeRouter);
        luckyBusd = IERC20(_luckyBusd);
        lucky = IERC20(_lucky);
        wNative = IWBNB(_wNative);
        BUSD = IERC20(_busd);
        MAX_NUMBER = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
        START_ROUND_DATE = block.timestamp;        
        transferOwnership(owner_);
    }

    // allow contract to receive natve coin  
    receive() external payable {}
    
    //-------------------------Staking Functions -------------------------//
    
    // deposit LUCKY-BUSD LP token
    function depositToken(uint256 amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(amount > 0, "Insufficient deposit amount!");
        luckyBusd.safeTransferFrom(msg.sender, address(this), amount);
        uint256 depositDate = getDepositDate();
        uint256 roundId = getCurrentRoundId();
        
        if (!isStakeUpToDate(roundId)) {
           updatePendingStake(); 
        }
        
        user.amount += amount;
        updateStake(roundId, depositDate, amount);
        emit DepositStake(msg.sender, amount, block.timestamp);
    }
    
    // withdraw LUCKY-BUSD LP token
    function withdrawToken() external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 roundId = getCurrentRoundId();

        if (!isStakeUpToDate(roundId)) {
           updatePendingStake(); 
        }
        
        updatePendingReward();
        uint256 amount = user.amount;
        user.amount = 0;
        removeStake(roundId);
        luckyBusd.safeTransfer(msg.sender, amount);
        emit WithdrawStake(msg.sender, amount, block.timestamp);
    }
    
    // claim LUCKY reward
    function claimReward() external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 roundId = getCurrentRoundId();
        
        if (user.amount > 0) {
            if (!isStakeUpToDate(roundId)) {
               updatePendingStake(); 
            }
            updatePendingReward();
        }
        
        uint256 claimableLuckyReward = user.pendingReward;
        require(claimableLuckyReward > 0, "Not enough claimable LUCKY reward!");
        user.rewardDept += claimableLuckyReward;
        user.pendingReward -= claimableLuckyReward;
        lucky.safeTransfer(msg.sender, claimableLuckyReward);
        emit ClaimReward(msg.sender, claimableLuckyReward, block.timestamp);
    }
    
    //-------------------------Updater Functions -------------------------//
    
    function updateRoundId() internal {
        _roundId.increment(); // increase round id when owner deposit revenue share to the contract
    }
    
    // Update max number of day in a round (default 7 days)
    function updateMaxDate(uint256 newMaxDate) external onlyOwner {
        MAX_DATE = newMaxDate;
    }
    
    function addWhitelist(address addr) external onlyOwner {
        whitelists[addr] = true;
    }

    function removeWhitelist(address addr) external onlyOwner {
        whitelists[addr] = false;
    }
    
    function updatePoolInfo(uint256 winRate, uint256 TPV, uint256 buyBack, uint256 roundID) internal {
	    uint256 totalValueLock = luckyBusd.balanceOf(address(this));
	    PoolInfo storage _poolInfo = poolInfo[roundID];
	    _poolInfo.winRate = winRate;
	    _poolInfo.TPV = TPV;
            _poolInfo.buyBack = buyBack;
	    _poolInfo.TVL = totalValueLock;
    }

    function removeStake(uint256 roundId) internal {
        for (uint256 i = 1; i <= MAX_DATE; i++) {
            uint256 amount = stakeAmount[roundId][i][msg.sender];
            stakeAmount[roundId][i][msg.sender] -= amount;
            totalStake[roundId][i] -= amount;
        }
    }
    
    function updateStake(uint256 roundId, uint256 depositDate, uint256 amount) internal {
        for(uint256 i = depositDate; i <= MAX_DATE; i++) {
            stakeAmount[roundId][i][msg.sender] += amount;
            totalStake[roundId][i] += amount;
        }
    }
    
    // Update pending stake of msg.sender from last update round to current round (MasterPool)
    function updatePendingStake() internal {
        UserInfo storage user = userInfo[msg.sender];
        uint256 lastUpdateRoundId = user.lastUpdateRoundId;
        uint256 currentRoundId = getCurrentRoundId();
        uint256 amount = user.amount;
        // If last update stake amount is on round 2 so we need to update stake amount from round 3 - 5
        for(uint256 i = (lastUpdateRoundId + 1); i <= currentRoundId; i++) {
            for(uint256 j = 1; j <= MAX_DATE; j++) {
                stakeAmount[i][j][msg.sender] = amount;
            }
        }
        user.lastUpdateRoundId = currentRoundId;
    }
    
    function updateTotalStake(uint256 roundId) internal {
        uint256 _totalStake = luckyBusd.balanceOf(address(this));
        for(uint256 i = 1; i <= MAX_DATE; i++) {
            totalStake[roundId][i] = _totalStake;
        }
    }
    
    function updatePendingReward() internal {
        UserInfo storage user = userInfo[msg.sender];
        uint256 luckyReward = calculateTotalLuckyReward();
        uint256 luckyRewardDept = user.rewardDept;
        user.pendingReward = (luckyReward - luckyRewardDept);
    }
    
    function calculateLuckyReward(address account, uint256 roundId) internal view returns (uint256) {
        uint256 luckyReward;
        uint256 totalLuckyRevenuePerDay = getTotalLuckyRewardPerDay(roundId);
        if (totalLuckyRevenuePerDay == 0) {
            return 0;
        }
        for (uint256 i = 1; i <= MAX_DATE; i++) {
            uint256 amount = stakeAmount[roundId][i][account];
            if (amount == 0) continue;
            uint256 _totalStake = totalStake[roundId][i];
            uint256 userSharesPerDay = (amount * 1e18) / _totalStake;
            luckyReward += (totalLuckyRevenuePerDay * userSharesPerDay) / 1e18;
        }
        return luckyReward;
    }
    // SWC-128-DoS With Block Gas Limit: L241-243
    function calculateTotalLuckyReward() internal view returns (uint256) {
        uint256 totalLuckyReward = 0;
        uint256 roundId = getCurrentRoundId();
        for (uint256 i = 0; i < roundId; i++) { 
            totalLuckyReward += calculateLuckyReward(msg.sender, i);
        }
        return totalLuckyReward;
    }
    
    //-------------------------Getter Functions -------------------------//
    
    // return current round id
    function getCurrentRoundId() public view returns (uint256) {
        return _roundId.current();
    }
    
    // return user stake amount of specific round and date
    function getStakeAmount(uint256 roundId, uint256 day) public view returns (uint256) {
        return stakeAmount[roundId][day][msg.sender];
    }
     
    // Get past time (in seconds) since start round
    function getRoundPastTime() external view returns (uint256) {
        return (block.timestamp - START_ROUND_DATE);
    }
    
    // check deposit date of msg.sender (date range: 1 - MAX_DATE)
    function getDepositDate() internal view returns (uint256) {
        for (uint256 i = 1; i <= MAX_DATE; i++) { 
            if (block.timestamp >= START_ROUND_DATE && block.timestamp < START_ROUND_DATE + (i * 1 days)) { 
                return i;
            }
        }
    }
    
    // return total LUCKY reward per day of specific round
    function getTotalLuckyRewardPerDay(uint256 roundId) public view returns (uint256) {
        return (totalLuckyRevenue[roundId] / MAX_DATE);
    }
    
    // return total LUCKY token balance in this contract
    function getLuckyBalance() external view returns (uint256) {
        return lucky.balanceOf(address(this));
    }
    
    // return total LUCKY-BUSD LP balance in this contract
    function getLuckyBusdBalance() external view returns (uint256) {
        return luckyBusd.balanceOf(address(this));
    }
     
    // return unclaimed LUCKY reward of msg.sender
    function getPendingReward() external view returns (uint256) {
        UserInfo storage user = userInfo[msg.sender];
        if (user.amount == 0) {
            return user.pendingReward;
        }
        uint256 luckyReward = calculateTotalLuckyReward();
        uint256 luckyRewardDept = user.rewardDept;
        return (luckyReward - luckyRewardDept);
    }
    
    // (RevPool)
    function getLuckyRewardPerRound(uint256 roundId) external view returns (uint256){
	    uint256 luckyReward = calculateLuckyReward(msg.sender, roundId);
	    return luckyReward;
    }
    
    // checking whether user reward is up-to-date or not
    function isStakeUpToDate(uint256 currentRoundId) internal view returns (bool) {
        return (userInfo[msg.sender].lastUpdateRoundId == currentRoundId);
    }
    
    //-------------------------Swap Token Functions -------------------------//
    
    // for owner to deposit revenue (any tokens) to RevenueSharingPool contract
    function depositRevenue(
        InputToken[] calldata inputTokens,
        address[] calldata BUSDToOutputPath,
        uint256 minOutputAmount,
        uint256 winRate,
        uint256 TPV
    ) external payable isWhitelisted(msg.sender) {
        uint256 luckyRevenue;
        uint256 roundId = getCurrentRoundId();
        
        // specify a correct swap path for NATIVE-to-BUSD
        address[] memory _path = new address[](2);
            _path[0] = address(wNative);
            _path[1] = address(BUSD);
           
        // if owner deposit native coin contract will swap native to BUSD token first 
        if (msg.value > 0) {
            wNative.deposit{value: msg.value}();
            uint256 wNativeBalance = wNative.balanceOf(address(this));
            _swapExactNativeForBUSD(wNativeBalance, _path);
        }
        
        if (inputTokens.length > 0 ) {
            for (uint256 i; i < inputTokens.length; i++) {
                if (inputTokens[i].token == address(lucky)) { // if token is LUCKY just transfer to contract directly
                    IERC20(lucky).safeTransferFrom(msg.sender, address(this), inputTokens[i].amount);
                    totalLuckyRevenue[roundId] += inputTokens[i].amount;
                    luckyRevenue += inputTokens[i].amount;
                } else if (inputTokens[i].token == address(BUSD)) { // if token is BUSD just transfer to contract first
                    IERC20(BUSD).safeTransferFrom(msg.sender, address(this), inputTokens[i].amount);
                } else {  // if token is not both LUCKY or BUSD let's swap it's to BUSD first
                    _transferTokensToCave(inputTokens[i]);
                    _swapTokensForBUSD(inputTokens[i]);
                }
            }
        }
        
        uint256 BUSDBalance = BUSD.balanceOf(address(this));
        uint256 amountOut = _swapBUSDForToken( // swap BUSD to LUCKY token
            BUSDBalance,
            BUSDToOutputPath
        );
        
        require(
            amountOut >= minOutputAmount,
            "Expect amountOut to be greater than minOutputAmount."
        );
        
        updatePoolInfo(winRate, TPV, BUSDBalance, roundId); // update round pool info
        totalLuckyRevenue[roundId] += amountOut;
        luckyRevenue += amountOut;
        START_ROUND_DATE = block.timestamp;
        updateRoundId();
        uint256 currentRoundId = getCurrentRoundId();
        updateTotalStake(currentRoundId); // update new round total stake
        emit DistributeLuckyRevenue(msg.sender, address(this), luckyRevenue);
    }

    // transfer all tokens from owner wallet to contract
    function _transferTokensToCave(InputToken calldata inputTokens) private {
            IERC20(inputTokens.token).safeTransferFrom(
                msg.sender,
                address(this),
                inputTokens.amount
            );
    }
    
    // swap native coin (e.g. BNB) to the BUSD token
    function _swapExactNativeForBUSD(uint256 amount, address[] memory path) private returns (uint256){
        if (amount == 0 || path[path.length - 1] == address(wNative)) {
            return amount;
        }
        wNative.approve(address(exchangeRouter), MAX_NUMBER);
        exchangeRouter.swapExactTokensForTokens(
            amount,
            0,//minimum amount out can optimize by cal slippage
            path,
            address(this),
            block.timestamp + 60
        );
    }
    
    // swap any ERC20 / BEP20 tokens to BUSD token
    function _swapTokensForBUSD(InputToken calldata inputTokens) private {
        if (inputTokens.token != address(BUSD)) {
            IERC20(inputTokens.token).approve(address(exchangeRouter), MAX_NUMBER);
            exchangeRouter.swapExactTokensForTokens(
                inputTokens.amount,
                0, //minimum amount out can optimize by cal slippage
                inputTokens.tokenToBUSDPath,
                address(this),
                block.timestamp + 60
            );
        }
    }

    // swap BUSD token to LUCKY token
    function _swapBUSDForToken(uint256 amount, address[] memory path)
        private
        returns (uint256)
    {
        if (amount == 0 || path[path.length - 1] == address(BUSD)) {
            return amount;
        }
        BUSD.approve(address(exchangeRouter), MAX_NUMBER);
        uint256[] memory amountOuts = exchangeRouter.swapExactTokensForTokens(
            amount,
            0,//minimum amount out can optimize by cal slippage
            path,
            address(this),
            block.timestamp + 60
        );
        return amountOuts[amountOuts.length - 1];
    }
}
