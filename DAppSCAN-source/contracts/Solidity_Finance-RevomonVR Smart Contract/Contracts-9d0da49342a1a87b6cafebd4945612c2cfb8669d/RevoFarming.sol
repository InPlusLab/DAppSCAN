/**
 *Submitted for verification at BscScan.com on 2021-08-01
*/

pragma solidity ^0.8.0;


/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }
}


library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
}


contract ReentrancyGuard {
    uint256 private _guardCounter;

    constructor () {
        _guardCounter = 1;
    }

    modifier nonReentrant() {
        _guardCounter += 1;
        uint256 localCounter = _guardCounter;
        _;
        require(localCounter == _guardCounter, "ReentrancyGuard: reentrant call");
    }
}

contract Context {
    constructor () { }

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;
    address public _poolManager;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender() || _poolManager == _msgSender(), "Ownable: caller is not the owner");
        _;
    }
    
    function setPoolManager(address _pm) public onlyOwner{
        _poolManager = _pm;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Pausable is Ownable {
  event Pause();
  event Unpause();

  bool public paused = false;


  /**
   * @dev Modifier to make a function callable only when the contract is not paused.
   */
  modifier whenNotPaused() {
    require(!paused);
    _;
  }

  /**
   * @dev Modifier to make a function callable only when the contract is paused.
   */
  modifier whenPaused() {
    require(paused);
    _;
  }

  /**
   * @dev called by the owner to pause, triggers stopped state
   */
  function pause() onlyOwner whenNotPaused public {
    paused = true;
    emit Pause();
  }

  /**
   * @dev called by the owner to unpause, returns to normal state
   */
  function unpause() onlyOwner whenPaused public {
    paused = false;
    emit Unpause();
  }
}

interface IERC20{
  function balanceOf(address account) external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function symbol() external view returns (string memory);
}

interface IRevoLib{
  function getLiquidityValue(uint256 liquidityAmount) external view returns (uint256 tokenRevoAmount, uint256 tokenBnbAmount);
  function getLpTokens(address _wallet) external view returns (uint256);
  function tokenRevoAddress() external view returns (address);
  function calculatePercentage(uint256 _amount, uint256 _percentage, uint256 _precision, uint256 _percentPrecision) external view returns (uint256);
}

contract RevoFarming is ReentrancyGuard, Pausable {
    using SafeMath for uint256;
    
    struct FarmingPool {
        string name;
        uint256 poolIndex;
        uint256 startTime;
        uint256 periodFinish;
        uint256 rewardRate;
        uint256 rewardsDuration;
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored;
        uint256 totalLpStaked;
    }
    
    struct Stake {
        uint256 stakedAmount;
        uint256 poolIndex;
        uint256 harvested;
        uint256 harvestable;
    }

    /* ========== STATE VARIABLES ========== */
    uint256 public poolIndex;
    mapping(uint256 => FarmingPool) public farmingPools;
    
    //Revo lib
    address public revoLibAddress;
    IRevoLib revoLib;
    //Revo Token
    address public revoAddress;
    IERC20 revoToken;
    //LP Token
    IERC20 public lpToken;
    address public lpAddress;

    mapping(uint256 => mapping(address => uint256)) public userRewardPerTokenPaid;
    mapping(uint256 => mapping(address => uint256)) public harvested;
    mapping(uint256 => mapping(address => uint256)) public rewards;

    
    mapping(uint256 => mapping(address => uint256)) private _balances;
    
    //Emergency right
    bool public emergencyRightBurned;

    /* ========== CONSTRUCTOR ========== */

    constructor(address _revoLibAddress, address _lpToken, address _poolManagerAddress) public {
        setRevoLib(_revoLibAddress);
        setRevo(revoLib.tokenRevoAddress());
        setLpToken(_lpToken);
        setPoolManager(_poolManagerAddress);
    }
    
    function createPool(uint256 _rewardsDuration, uint256 _totalReward, string memory _poolName) public onlyOwner{
        farmingPools[poolIndex].startTime = block.timestamp;
        farmingPools[poolIndex].poolIndex = poolIndex;
        updatePoolName(poolIndex, _poolName);
        setRewardsDuration(poolIndex, _rewardsDuration);
        notifyRewardAmount(poolIndex, _totalReward);
        
        poolIndex++;
    }
    
    function updatePoolName(uint256 _poolIndex, string memory _poolName) public onlyOwner{
        farmingPools[_poolIndex].name = _poolName;
    }

    /* ========== VIEWS ========== */

    function balanceOf(uint256 _poolIndex, address account) external view returns (uint256) {
        return _balances[_poolIndex][account];
    }

    function lastTimeRewardApplicable(uint256 _poolIndex) public view returns (uint256) {
        return Math.min(block.timestamp, farmingPools[_poolIndex].periodFinish);
    }

    function rewardPerToken(uint256 _poolIndex) public view returns (uint256) {
        if (farmingPools[_poolIndex].totalLpStaked == 0) {
            return farmingPools[_poolIndex].rewardPerTokenStored;
        }
        return
            farmingPools[_poolIndex].rewardPerTokenStored.add(
                lastTimeRewardApplicable(_poolIndex)
                    .sub(farmingPools[_poolIndex].lastUpdateTime)
                    .mul(farmingPools[_poolIndex].rewardRate)
                    .mul(1e18)
                    .div(farmingPools[_poolIndex].totalLpStaked)
            );
    }

    function earned(uint256 _poolIndex, address account) public view returns (uint256) {
        return
            _balances[_poolIndex][account]
                .mul(rewardPerToken(_poolIndex).sub(userRewardPerTokenPaid[_poolIndex][account]))
                .div(1e18)
                .add(rewards[_poolIndex][account]);
    }

    function getRewardForDuration(uint256 _poolIndex) external view returns (uint256) {
        return farmingPools[_poolIndex].rewardRate.mul(farmingPools[_poolIndex].rewardsDuration);
    }
    
    function getAllPools() external view returns(FarmingPool[] memory){
        FarmingPool[] memory poolsToReturn = new FarmingPool[](poolIndex);
        for(uint256 i = 0; i < poolIndex; i++){
            poolsToReturn[i] = farmingPools[i];
        }
        
        return poolsToReturn;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 _poolIndex, address _wallet, uint256 amount) external nonReentrant whenNotPaused updateReward(_poolIndex, _wallet) onlyOwner {
        require(amount > 0, "Cannot stake 0");
        farmingPools[_poolIndex].totalLpStaked = farmingPools[_poolIndex].totalLpStaked.add(amount);
        _balances[_poolIndex][_wallet] = _balances[_poolIndex][_wallet].add(amount);
        lpToken.transferFrom(_wallet, address(this), amount);
        emit Staked(_wallet, amount);
    }

    function withdraw(uint256 _poolIndex, address _wallet, uint256 amount) public nonReentrant updateReward(_poolIndex, _wallet) onlyOwner {
        require(amount > 0, "Cannot withdraw 0");
        farmingPools[_poolIndex].totalLpStaked = farmingPools[_poolIndex].totalLpStaked.sub(amount);
        _balances[_poolIndex][_wallet] = _balances[_poolIndex][_wallet].sub(amount);
        lpToken.transfer(_wallet, amount);
        emit Withdrawn(_wallet, amount);
    }

    function harvest(uint256 _poolIndex, address _wallet) public nonReentrant updateReward(_poolIndex, _wallet) onlyOwner {
        uint256 reward = rewards[_poolIndex][_wallet];
        if (reward > 0) {
            rewards[_poolIndex][_wallet] = 0;
            revoToken.transfer(_wallet, reward);
            harvested[_poolIndex][_wallet] = harvested[_poolIndex][_wallet].add(reward);
            emit RewardPaid(_wallet, reward);
        }
    }

    function exit(uint256 _poolIndex, address _wallet) external onlyOwner {
        withdraw(_poolIndex, _wallet, _balances[_poolIndex][_wallet]);
        harvest(_poolIndex, _wallet);
    }
    
    /*
    Get pool indexes for user
    */
    function getUserStakes(address _user) public view returns(Stake[] memory){
        uint256 count;
        for(uint256 i = 0; i < poolIndex; i++){
            if(_balances[i][_user] > 0){ count++;}
        }
        
        Stake[] memory stakesToReturn = new Stake[](count);
        uint index;
        for(uint256 i = 0; i < poolIndex; i++){
            if(_balances[i][_user] > 0 || earned(i, _user) > 0){
                stakesToReturn[index] = Stake(_balances[i][_user], i, harvested[i][_user], earned(i, _user));
                index++;
            }
        }
        
        return stakesToReturn;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function notifyRewardAmount(uint256 _poolIndex, uint256 _reward) private onlyOwner updateReward(_poolIndex, address(0)) {
        if (block.timestamp >= farmingPools[_poolIndex].periodFinish) {
            farmingPools[_poolIndex].rewardRate = _reward.div(farmingPools[_poolIndex].rewardsDuration);
        } else {
            uint256 remaining = farmingPools[_poolIndex].periodFinish.sub(block.timestamp);
            uint256 leftover = remaining.mul(farmingPools[_poolIndex].rewardRate);
            farmingPools[_poolIndex].rewardRate = _reward.add(leftover).div(farmingPools[_poolIndex].rewardsDuration);
        }

        revoToken.transferFrom(msg.sender, address(this), _reward);
        uint256 balance = revoToken.balanceOf(address(this));
        require(farmingPools[_poolIndex].rewardRate <= balance.div(farmingPools[_poolIndex].rewardsDuration), "Provided reward too high");

        farmingPools[_poolIndex].lastUpdateTime = block.timestamp;
        farmingPools[_poolIndex].periodFinish = block.timestamp.add(farmingPools[_poolIndex].rewardsDuration);
        emit RewardAdded(_reward);
    }
    
    function setRewardsDuration(uint256 _poolIndex, uint256 _rewardsDuration) private onlyOwner {
        require(
            farmingPools[_poolIndex].periodFinish == 0 || block.timestamp > farmingPools[_poolIndex].periodFinish,
            "Previous rewards period must be complete before changing the duration for the new period"
        );
        farmingPools[_poolIndex].rewardsDuration = _rewardsDuration;
        emit RewardsDurationUpdated(farmingPools[_poolIndex].rewardsDuration);
    }

    function recoverRevo(uint256 _amount) external onlyOwner{
        require(!emergencyRightBurned, "Emergency right burned");
        revoToken.transfer(owner(), _amount);
    }
    
    function recoverLP(uint256 _amount) external onlyOwner{
        require(!emergencyRightBurned, "Emergency right burned");
        lpToken.transfer(owner(), _amount);
    }
    
    function burnEmergencyRight() external onlyOwner{
        emergencyRightBurned = true;
    }

    /* ========== MODIFIERS ========== */

    modifier updateReward(uint256 _poolIndex, address account) {
        farmingPools[_poolIndex].rewardPerTokenStored = rewardPerToken(_poolIndex);
        farmingPools[_poolIndex].lastUpdateTime = lastTimeRewardApplicable(_poolIndex);
        if (account != address(0)) {
            rewards[_poolIndex][account] = earned(_poolIndex, account);
            userRewardPerTokenPaid[_poolIndex][account] = farmingPools[_poolIndex].rewardPerTokenStored;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event RewardAdded(uint256 reward);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardsDurationUpdated(uint256 newDuration);
    event Recovered(address token, uint256 amount);
    
    /*
    SETTERS
    */
    /*
    Set revoLib Address & libInterface
    */
    function setRevoLib(address _revoLib) public onlyOwner {
        revoLibAddress = _revoLib;
        revoLib = IRevoLib(revoLibAddress);
    }
    
    /*
    Set revo Address & token
    */
    function setRevo(address _revo) public onlyOwner {
        revoAddress = _revo;
        revoToken = IERC20(revoAddress);
    }
    
     /*
    Set lp Address & lp token
    */
    function setLpToken(address _lpAddress) public onlyOwner {
        lpAddress = _lpAddress;
        lpToken = IERC20(_lpAddress);
    }
}