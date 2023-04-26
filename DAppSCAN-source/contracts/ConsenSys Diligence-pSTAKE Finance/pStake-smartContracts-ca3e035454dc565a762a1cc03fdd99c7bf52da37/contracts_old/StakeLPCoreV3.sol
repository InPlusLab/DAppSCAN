// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.7.0;

import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./interfaces/ISTokens.sol";
import "./interfaces/IUTokens.sol";
import "./interfaces/IPSTAKE.sol";
import "./interfaces/IHolder.sol";
import "./interfaces/IStakeLPCore.sol";
import "./libraries/TransferHelper.sol";
import "./libraries/FullMath.sol";

contract StakeLPCoreV3 is IStakeLPCore, PausableUpgradeable, AccessControlUpgradeable {

    using SafeMathUpgradeable for uint256;
    using FullMath for uint256;
    
    // constant pertaining to access roles
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // balance of user for an LP Token 
    mapping(address => mapping(address => uint256)) public _lpBalance;
    // supply for an LP Token
    mapping(address => uint256) public _lpSupply;
    // last recorded total LPTimeShare
    mapping(address => uint256) private _lastLPTimeShare;
    // last recorded timestamp when rewards were disbursed
    mapping(address => uint256) private _lastLPTimeShareTimestamp;
    // last recorded timestamp when PSTAKE tokens were disbursed
    mapping(address => mapping(address => uint256)) private _lastLiquidityTimestamp; 

    //Private instances of contracts to handle Utokens and Stokens
    IUTokens public _uTokens;
    ISTokens public _sTokens;
    IPSTAKE public _pstakeTokens;

    /**
   * @dev Constructor for initializing the LiquidStaking contract.
   * @param uAddress - address of the UToken contract.
   * @param sAddress - address of the SToken contract.
   * @param pStakeAddress - address of the pStake contract address.
   */
    function initialize(address uAddress, address sAddress, address pStakeAddress, address pauserAddress) public virtual initializer  {
        __AccessControl_init();
        __Pausable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, pauserAddress);        
        setUTokensContract(uAddress);
        setSTokensContract(sAddress);
        setPSTAKEContract(pStakeAddress);
        // _lastLPTimeShareTimestamp = block.timestamp;
    }

    /*
     * @dev calculate liquidity and reward tokens and disburse to user
     * @param lpToken: lp token contract address
     * @param to: user address
     * @param liquidityWeightFactor: coming as an argument for further calculations
     * @param rewardWeightFactor: coming as an argument for further calculations
     * @param valueDivisor: coming as an argument for further calculations
     */
    function calculatePendingRewardsAndLiquidity(address lpToken, address to) public view returns (uint256 liquidity, uint256 reward, uint256 updatedSupplyLPTimeshare){
        // get the balance of user's LP token
        uint256 _lpBalanceUser = _lpBalance[lpToken][to];
        uint256 _lpSupplyContract = _lpSupply[lpToken];

        // calculate the LPTimeShare of the user's LP Token
        uint256 _userLPTimeShare = (_lpBalanceUser.mul(block.timestamp.sub(_lastLiquidityTimestamp[lpToken][to])));

        // calculate the LPTimeShare of the sum of supply of all LP Tokens
        uint256 _newSupplyLPTimeShare = (_lpSupplyContract.mul(block.timestamp.sub(_lastLPTimeShareTimestamp[lpToken])));
        uint256 _totalSupplyLPTimeShare = _lastLPTimeShare[lpToken].add(_newSupplyLPTimeShare);
        // is the remaining LPTimeShare of the total supply after the tokens for the user has been dispatched
        updatedSupplyLPTimeshare = _totalSupplyLPTimeShare.sub(_userLPTimeShare);

        if(_totalSupplyLPTimeShare > 0) {
            // calculate users new reward tokens
            uint256 _rewardPool = _uTokens.balanceOf(address(this));
            reward = _rewardPool.mulDiv(_userLPTimeShare, _totalSupplyLPTimeShare);

            // calculate users new liquidity tokens
            uint256 _liquidityPool = _pstakeTokens.balanceOf(address(this));
            liquidity = _liquidityPool.mulDiv(_userLPTimeShare, _totalSupplyLPTimeShare);
        }
    }

    /*
     * @dev calculate liquidity and reward tokens and disburse to user
     * @param lpToken: lp token contract address
     * @param to: user address
     * @param liquidityWeightFactor: coming as an argument for further calculations
     * @param rewardWeightFactor: coming as an argument for further calculations
     * @param valueDivisor: coming as an argument for further calculations
     */
    function _calculateRewardsAndLiquidity(address holderAddress, address lpToken, address to) internal returns (uint256 liquidity, uint256 reward){
        uint256 updatedSupplyLPTimeshare;
        (liquidity, reward, updatedSupplyLPTimeshare) = calculatePendingRewardsAndLiquidity(lpToken, to);

        // update last timestamps and LPTimeShares as per Checks-Effects-Interactions pattern
        _lastLiquidityTimestamp[lpToken][to] = block.timestamp;
        _lastLPTimeShareTimestamp[lpToken] = block.timestamp;
        _lastLPTimeShare[lpToken] = updatedSupplyLPTimeshare;

        // DISBURSE THE LIQUIDITY TOKENS TO USER (transfer)
        if(liquidity > 0)
        IHolder(holderAddress).safeTransfer(address(_pstakeTokens), to, liquidity);

        // DISBURSE THE REWARD TOKENS TO USER (transfer)
        if(reward > 0)
        IHolder(holderAddress).safeTransfer(address(_uTokens), to, reward);
    }

    /*
     * @dev calculate liquidity and reward tokens and disburse to user
     * @param lpToken: lp token contract address
     * @param amount: token amount
     */
    function calculateRewardsAndLiquidity(address lpToken, uint256 amount) internal whenNotPaused returns (uint256 liquidity, uint256 reward){
        // check for validity of arguments
        require(amount > 0 && lpToken != address(0), "LP2");

        // check if lpToken contract of DeFi product address is whitelisted and has valid holder contract
        (bool _isContractWhitelisted, address _holderAddress) = _sTokens.isContractWhitelisted(lpToken);
        require(_isContractWhitelisted && _holderAddress != address(0), "LP5");
        
        // calculate liquidity and reward tokens and disburse to user
        (liquidity, reward) = _calculateRewardsAndLiquidity(_holderAddress, lpToken, _msgSender());
        CalculateRewardsAndLiquidity(_holderAddress, lpToken, amount, _msgSender(), liquidity, reward);
    }

    /*
     * @dev adding the liquidity
     * @param lpToken: lp token contract address
     * @param amount: token amount
     *
     * Emits a {AddLiquidity} event with 'lpToken, amount, rewards and liquidity'
     *
     */
    function addLiquidity(
        address lpToken,
        uint256 amount
    ) public virtual override whenNotPaused returns (uint256 liquidity, uint256 rewards) {
        // check for validity of arguments
        require(amount > 0 && lpToken != address(0), "LP4");

        // check if lpToken contract of DeFi product address is whitelisted and has valid holder contract
        (bool _isContractWhitelisted, address _holderAddress) = _sTokens.isContractWhitelisted(lpToken);
        require(_isContractWhitelisted && _holderAddress != address(0), "LP5");

        address messageSender = _msgSender();

        // calculate liquidity and reward tokens and disburse to user
        (rewards, liquidity) = _calculateRewardsAndLiquidity(_holderAddress, lpToken, messageSender);
        // finally transfer the new LP Tokens to the StakeLP contract
        TransferHelper.safeTransferFrom(lpToken, messageSender, address(this), amount);
        // update the user balance
        _lpBalance[lpToken][messageSender] = _lpBalance[lpToken][messageSender].add(amount);
        // update the supply of lp tokens for reward and liquidity calculation
        _lpSupply[lpToken] = _lpSupply[lpToken].add(amount);
        emit AddLiquidity(lpToken, amount, rewards, liquidity);
    }

    /*
    * @dev removing the liquidity
    * @param lpToken: lp token contract address
    * @param amount: token amount
    *
    * Emits a {RemoveLiquidity} event with 'lpToken, amount, rewards and liquidity'
    *
    */
    function removeLiquidity(
        address lpToken,
        uint256 amount
    ) public virtual override whenNotPaused returns (uint256 liquidity, uint256 rewards) {
        // check for validity of arguments
        require(amount > 0 && lpToken != address(0), "LP6");

        // check if lpToken contract of DeFi product address is whitelisted and has valid holder contract
        (bool _isContractWhitelisted, address _holderAddress) = _sTokens.isContractWhitelisted(lpToken);
        require(_isContractWhitelisted && _holderAddress != address(0), "LP5");

        address messageSender = _msgSender();

        // check if suffecient balance is there
        require(_lpBalance[lpToken][messageSender] >= amount, "LP8");

        // calculate liquidity and reward tokens and disburse to user
        (rewards, liquidity) = _calculateRewardsAndLiquidity(_holderAddress, lpToken, messageSender);
        // finally transfer the LP Tokens to the user
        TransferHelper.safeTransferFrom(lpToken, address(this), messageSender, amount);
        // update the user balance
        _lpBalance[lpToken][messageSender] = _lpBalance[lpToken][messageSender].sub(amount);
        // update the supply of lp tokens for reward and liquidity calculation
        _lpSupply[lpToken] = _lpSupply[lpToken].sub(amount);
        emit RemoveLiquidity(lpToken, amount, rewards, liquidity);
    }

    /**
     * @dev Set 'contract address', called from constructor
     * @param uAddress: utoken contract address
     *
     * Emits a {SetUTokensContract} event with '_contract' set to the utoken contract address.
     *
     */
    function setUTokensContract(address uAddress) public virtual override {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "LP9");
        _uTokens = IUTokens(uAddress);
        emit SetUTokensContract(uAddress);
    }

    /**
     * @dev Set 'contract address', called from constructor
     * @param sAddress: stoken contract address
     *
     * Emits a {SetSTokensContract} event with '_contract' set to the stoken contract address.
     *
     */
    function setSTokensContract(address sAddress) public virtual override {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "LP10");
        _sTokens = ISTokens(sAddress);
        emit SetSTokensContract(sAddress);
    }

    /**
     * @dev Set 'contract address', called from constructor
     * @param pstakeAddress: pStake contract address
     *
     * Emits a {SetPSTAKEContract} event with '_contract' set to the stoken contract address.
     *
     */
    function setPSTAKEContract(address pstakeAddress) public virtual override {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "LP11");
        _pstakeTokens = IPSTAKE(pstakeAddress);
        emit SetPSTAKEContract(pstakeAddress);
    }

    /**
      * @dev Triggers stopped state.
      *
      * Requirements:
      *
      * - The contract must not be paused.
      */
    function pause() public virtual returns (bool success) {
        require(hasRole(PAUSER_ROLE, _msgSender()), "LP12");
        _pause();
        return true;
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function unpause() public virtual returns (bool success) {
        require(hasRole(PAUSER_ROLE, _msgSender()), "LP13");
        _unpause();
        return true;
    }
}