pragma solidity =0.8.0;

interface IRevoTokenContract{
  function balanceOf(address account) external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
}

interface IRevoTierContract{
    function getRealTimeTier(address _wallet) external view returns (Tier memory);
    function getTier(uint256 _index) external view returns(Tier memory);
    
    struct Tier {
        uint256 index;
        uint256 minRevoToHold;
        uint256 stakingAPRBonus;
        string name;
    }
}

interface IRevoLib{
  function getLiquidityValue(uint256 liquidityAmount) external view returns (uint256 tokenRevoAmount, uint256 tokenBnbAmount);
  function getLpTokens(address _wallet) external view returns (uint256);
  function tokenRevoAddress() external view returns (address);
  function calculatePercentage(uint256 _amount, uint256 _percentage, uint256 _precision, uint256 _percentPrecision) external view returns (uint256);
}

library SafeMath {
    function add(uint x, uint y) internal pure returns (uint z) {
        require((z = x + y) >= x, 'ds-math-add-overflow');
    }

    function sub(uint x, uint y) internal pure returns (uint z) {
        require((z = x - y) <= x, 'ds-math-sub-underflow');
    }

    function mul(uint x, uint y) internal pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
    }
    
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }
}

contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
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


contract RevoStaking is Ownable{
    using SafeMath for uint256;
    uint256 SECONDS_IN_YEAR = 31104000;
    
    struct Pool {
        string poolName;
        uint256 poolIndex;
        uint256 startTime;
        uint256 totalReward;
        uint256 totalRewardRemaining;
        uint256 totalStaked;
        uint256 currentReward;
        uint256 duration;
        uint256 APR;
        bool terminated;
        uint256 maxRevoStaking;
    }
    
    struct Stake {
        uint256 stakedAmount;
        uint256 startTime;
        uint256 poolIndex;
        uint256 tierIndex;
        uint256 reward;
        uint256 harvested;
        bool withdrawStake;
    }
    
    //Revo Token
    address public revoAddress;
    IRevoTokenContract revoToken;
    //Tier
    address public tierAddress;
    IRevoTierContract revoTier;
    //Revo lib
    address public revoLibAddress;
    IRevoLib revoLib;
    //Emergency right
    bool public emergencyRightBurned;
    //Pools
    mapping (uint => Pool) public pools;
    mapping(uint256 => mapping(address => Stake)) public stakes;
    uint public poolIndex;
    //Reward precision
    uint256 public rewardPrecision = 100000000000000;
    
    //EVENTS
    event StakeEvent(uint256 revoAmount, address wallet);
    event HarvestEvent(uint256 revoAmount, address wallet);
    event UnstakeEvent(uint256 revoStakeAmount, uint256 revoHarvestAmount, address wallet);

    //MODIFIERS
    modifier stakeProtection(uint256 _poolIndex, uint256 _revoAmount, address _wallet) {
        //TIERS 
        IRevoTierContract.Tier memory userTier = revoTier.getRealTimeTier(_wallet);

        //Stake not done
        require(stakes[_poolIndex][_wallet].stakedAmount == 0 && !stakes[_poolIndex][_wallet].withdrawStake, "Stake already done");
        
        //Pool not terminated
        require(!pools[_poolIndex].terminated, "Pool closed");
        
        //User must belong to at least the first tier
        require(userTier.minRevoToHold > 0, "User must belong to a tier");
        
        //Max Revo amount to stake 
        require(_revoAmount <= pools[_poolIndex].maxRevoStaking, "Please stake less than the max amount");
        
        //Stake more than 0
        require(_revoAmount > 0, "Please stake more than 0 Revo");
        
        _;
    }
    
    constructor(address _revoLibAddress, address _revoTier, address _poolManagerAddress) {
        setRevoLib(_revoLibAddress);
        setRevo(revoLib.tokenRevoAddress());
        setRevoTier(_revoTier);
        setPoolManager(_poolManagerAddress);
    }
    
    /****************************
            POOLS functions
    *****************************/
    
    /*
    Create a new pool to a new incremented index + transfer Revo to it
    */
    function createPool(string memory _name, uint256 _balance, uint256 _duration, uint256 _apr, uint256 _maxRevoStaking) public onlyOwner {
        updatePool(poolIndex, _name, _balance, _duration, _apr, _maxRevoStaking);
        poolIndex++;
    }
    
    /*
    Update a pool to specific index
    */
    function updatePool(uint256 _index, string memory _name, uint256 _balance, uint256 _duration, uint256 _apr, uint256 _maxRevoStaking) public onlyOwner {
        pools[_index].poolName = _name;
        pools[_index].poolIndex = _index;
        pools[_index].startTime = block.timestamp;
        pools[_index].totalReward = _balance;
        pools[_index].duration = _duration;
        pools[_index].APR = _apr;
        pools[_index].maxRevoStaking = _maxRevoStaking;

        if(pools[_index].totalRewardRemaining < pools[_index].totalReward){
            addReward(pools[_index].totalReward.sub(pools[_index].totalRewardRemaining), _index);  
        }
    }
    
    /*
    Update terminated variable in pool at a specific index
    */
    function updateTerminated(uint256 _index, bool _terminated) public onlyOwner {
        pools[_index].terminated = _terminated;
    }
    
    /****************************
            STAKING functions
    *****************************/
    /*
    Stake Revo based on Tier
    */
    function performStake(uint256 _poolIndex, uint256 _revoAmount, address _wallet) public stakeProtection(_poolIndex, _revoAmount, _wallet) onlyOwner {
        Stake storage stake = stakes[_poolIndex][_wallet];
        
        //Update user stake tier index <!> Before update stakedAmount
        stake.tierIndex = revoTier.getRealTimeTier(_wallet).index;
        
        //Update user & pool rewards
        stake.reward = getUserPoolReward(_poolIndex, _revoAmount, _wallet);
        //Check if there are enough reward to reward user
        require(stake.reward <= getRevoLeftForPool(_poolIndex), "No Revo left");
        
        pools[_poolIndex].currentReward = pools[_poolIndex].currentReward.add(stake.reward);
        
        //Update total staked
        pools[_poolIndex].totalStaked = pools[_poolIndex].totalStaked.add(_revoAmount);
        
        //Update user stake
        stake.stakedAmount = _revoAmount;
        stake.startTime = block.timestamp;
        stake.poolIndex = _poolIndex;
        
        //Transfer REVO
        revoToken.transferFrom(_wallet, address(this), _revoAmount);
        
        emit StakeEvent(_revoAmount, _wallet);
    }
    
     /*
    Unstake Revo & harvestable
    */
    function unstake(uint256 _poolIndex, address _wallet) public onlyOwner {
        Stake storage stake = stakes[_poolIndex][_wallet];
        
        uint256 endTime = stake.startTime.add(pools[_poolIndex].duration);
        require(block.timestamp >= endTime, "Stake period not finished");
        
        //Not already unstake
        require(!stake.withdrawStake, "Revo already unstaked");
        stake.withdrawStake = true;
        
        uint256 harvestable = getHarvestable(_wallet, _poolIndex);

        //Enough reward
        require(pools[_poolIndex].totalRewardRemaining.sub(harvestable) > 0, "Not enough reward in contract");
        pools[_poolIndex].totalRewardRemaining = pools[_poolIndex].totalRewardRemaining.sub(harvestable);

        revoToken.transfer(_wallet, stake.stakedAmount.add(harvestable));
        
        emit UnstakeEvent(stake.stakedAmount, harvestable, _wallet);
        
        stake.harvested = getHarvest(_wallet, _poolIndex);
    }
    
    /*
    Harvest Revo reward linearly
    */
    function harvest(uint256 _poolIndex, address _wallet) public onlyOwner {
        Stake storage stake = stakes[_poolIndex][_wallet];
        
        //Not already unstake
        require(!stake.withdrawStake, "Revo already unstaked");
        
        //Transfer harvestable 
        uint256 harvestable = getHarvestable(_wallet, _poolIndex);

        //Enough reward
        require(pools[_poolIndex].totalRewardRemaining.sub(harvestable) > 0, "Not enough reward in contract");
        pools[_poolIndex].totalRewardRemaining = pools[_poolIndex].totalRewardRemaining.sub(harvestable);

        revoToken.transfer(_wallet, harvestable);
        
        //Update harvested
        stake.harvested = getHarvest(_wallet, _poolIndex);
        
        emit HarvestEvent(harvestable, _wallet);
    }
    
    /*
    Get Revo reward global harvest
    */
    function getHarvest(address _wallet, uint256 _poolIndex) public view returns(uint256){
        uint256 percentPrecision = 100000000000;
        Stake storage stake = stakes[_poolIndex][_wallet];
        //End time stake
        uint256 endTime = stake.startTime.add(pools[_poolIndex].duration);
        
        uint256 percentHarvestable = percentPrecision;//100%
        if(block.timestamp < endTime){
            uint256 remainingTime = endTime.sub(block.timestamp);
            
            percentHarvestable = percentPrecision - remainingTime.mul(percentPrecision).div(pools[_poolIndex].duration);
        }
        
        return revoLib.calculatePercentage(stake.reward, percentHarvestable, rewardPrecision, percentPrecision);
    }
    
    
    /*
    Get Revo harvestable
    */
    function getHarvestable(address _wallet, uint256 _poolIndex) public view returns(uint256){
        return getHarvest(_wallet, _poolIndex).sub(stakes[_poolIndex][_wallet].harvested);
    }
    

    /*
    Return the user reward for a specific pool & for a specific amount
    */
    function getUserPoolReward(uint256 _poolIndex, uint256 _stakeAmount, address _wallet) public view returns(uint256){
        IRevoTierContract.Tier memory userTier = revoTier.getRealTimeTier(_wallet);
        
        uint256 userPercentage = getPoolPercentage(_poolIndex, userTier.index);
        
        uint256 reward = _stakeAmount.div(100).mul(userPercentage).div(rewardPrecision);
        
        return reward;
    }

    /*
    Return pool percentage * rewardPrecision
    */
    function getPoolPercentage(uint256 _poolIndex, uint256 _tierIndex) public view returns(uint256){
        uint256 APR = pools[_poolIndex].APR;//.add(revoTier.getTier(_tierIndex).stakingAPRBonus);
        
        return APR.mul(rewardPrecision).div(SECONDS_IN_YEAR).mul(pools[_poolIndex].duration);
    }
    
    /*
    Return Revo left for reward
    */
    function getRevoLeftForPool(uint256 _poolIndex) public view returns(uint256){
        return pools[_poolIndex].totalReward.sub(pools[_poolIndex].currentReward);
    }
    
    /*
    Set revo Address & token
    */
    function setRevo(address _revo) public onlyOwner {
        revoAddress = _revo;
        revoToken = IRevoTokenContract(revoAddress);
    }
    
    /*
    Set revo tier Address & contract
    */
    function setRevoTier(address _revoTier) public onlyOwner {
        tierAddress = _revoTier;
        revoTier = IRevoTierContract(tierAddress);
    }
    
    /*
    Set revoLib Address & libInterface
    */
    function setRevoLib(address _revoLib) public onlyOwner {
        revoLibAddress = _revoLib;
        revoLib = IRevoLib(revoLibAddress);
    }
    
    /*
    Emergency transfer Revo
    */
    function withdrawRevo(uint256 _amount) public onlyOwner {
        if(!emergencyRightBurned){
            revoToken.transfer(owner(), _amount);
        }
    }

    function burnEmergencyRight() public onlyOwner {
        emergencyRightBurned = true;
    }

    /*
    Add revo Reward
    */
    function addReward(uint256 _revoAmount, uint256 _poolIndex) public onlyOwner {
        //Transfer REVO
        pools[_poolIndex].totalRewardRemaining = pools[_poolIndex].totalRewardRemaining.add(_revoAmount);
        revoToken.transferFrom(msg.sender, address(this), _revoAmount);
    }
    
    /*
    Get pool indexes for user
    */
    function getUserStakes(address _user) public view returns(Stake[] memory){
        uint256 count;
        for(uint256 i = 0; i < poolIndex; i++){
            if(stakes[i][_user].stakedAmount > 0){ count++;}
        }
        
        Stake[] memory stakesToReturn = new Stake[](count);
        uint index;
        for(uint256 i = 0; i < poolIndex; i++){
            Stake memory s = stakes[i][_user];
            if(s.stakedAmount > 0){
                stakesToReturn[index] = Stake(s.stakedAmount, s.startTime, s.poolIndex, s.tierIndex, s.reward, s.harvested, s.withdrawStake);
                index++;
            }
        }
        
        return stakesToReturn;
    }
    
    function getAllPools() public view returns(Pool[] memory){
        Pool[] memory poolsToReturn = new Pool[](poolIndex);
        for(uint256 i = 0; i < poolIndex; i++){
            poolsToReturn[i] = pools[i];
        }
        
        return poolsToReturn;
    }
    
    function getUserStake(uint256 _poolIndex, address _user) public view returns(Stake memory){
        return stakes[_poolIndex][_user];
    }
}