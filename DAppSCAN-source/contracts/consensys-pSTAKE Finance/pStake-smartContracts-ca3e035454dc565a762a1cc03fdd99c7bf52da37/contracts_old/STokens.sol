// SPDX-License-Identifier: UNLICENSED
pragma solidity >= 0.7.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./interfaces/ISTokens.sol";
import "./interfaces/IUTokens.sol";
import "./interfaces/IHolder.sol";
import "./libraries/FullMath.sol";

contract STokens is ERC20Upgradeable, ISTokens, PausableUpgradeable, AccessControlUpgradeable {

    using SafeMathUpgradeable for uint256;
    using FullMath for uint256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    // constants defining access control ROLES
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // variables pertaining to holder logic for whitelisted addresses & StakeLP
    // deposit contract address for STokens in a DeFi product
    EnumerableSetUpgradeable.AddressSet private _whitelistedAddresses;
    mapping(address => address) private _holderContractAddress;
    // LP Token contract address which might be different from whitelisted contract
    mapping(address => address) private _lpContractAddress;
    // last timestamp when the holder reward calculation was performed for updating reward pool
    mapping(address => uint256) private _lastHolderRewardTimestamp;

    // variables capturing data of other contracts in the product
    address private _liquidStakingContract;
    // address private _stakeLPCoreContract;
    IUTokens private _uTokens;

    // variables pertaining to moving reward rate logic
    uint256[] private _rewardRate;
    uint256[] private _lastMovingRewardTimestamp;
    uint256 private _valueDivisor;
    mapping(address => uint256) private _lastUserRewardTimestamp;

    /**
   * @dev Constructor for initializing the SToken contract.
   * @param uaddress - address of the UToken contract.
   * @param pauserAddress - address of the pauser admin.
   * @param rewardRate - set to rewardRate * 10^-5
   * @param valueDivisor - valueDivisor set to 10^9.
   */
    function initialize(address uaddress, address pauserAddress, uint256 rewardRate, uint256 valueDivisor) public virtual initializer {
        __ERC20_init("pSTAKE Staked ATOM", "stkATOM");
        __AccessControl_init();
        __Pausable_init();
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(PAUSER_ROLE, pauserAddress);
        setUTokensContract(uaddress);
        _valueDivisor = valueDivisor;
        require(rewardRate <= _valueDivisor.mul(100), "ST1");
        _rewardRate.push(rewardRate);
        _lastMovingRewardTimestamp.push(block.timestamp);
        _setupDecimals(6);
    }

    /**
    * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
    * @param lpContractAddress: contract address
    */
    function isContractWhitelisted(address lpContractAddress) public view virtual override returns (bool result, address holderAddress){
        // Get the time in number of blocks
        address _lpContractAddressLocal;
        // valueDivisor = _valueDivisor;
        uint256 _whitelistedAddressesLength = _whitelistedAddresses.length();
        for (uint256 i=0; i<_whitelistedAddressesLength; i=i.add(1)) {
            //get getUnstakeTime and compare it with current timestamp to check if 21 days + epoch difference has passed
            _lpContractAddressLocal = _lpContractAddress[_whitelistedAddresses.at(i)];
            if(_lpContractAddressLocal == lpContractAddress) {
                result = true;
                holderAddress = _holderContractAddress[_whitelistedAddresses.at(i)];
                break;
            }
        }
    }

    /**
    * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
    * @param whitelistedAddress: contract address
    */
    function getHolderData(address whitelistedAddress) public view virtual override returns (address holderAddress, address lpAddress, uint256 lastHolderRewardTimestamp){
        // Get the time in number of blocks
        holderAddress = _holderContractAddress[whitelistedAddress];
        lpAddress = _lpContractAddress[whitelistedAddress];
        lastHolderRewardTimestamp = _lastHolderRewardTimestamp[whitelistedAddress];
    }

    /*
    * @dev set reward rate called by admin
    * @param rewardRate: reward rate
    *
    *
    * Requirements:
    *
    * - `rate` cannot be less than or equal to zero.
    *
    */
    function setRewardRate(uint256 rewardRate) public virtual override returns (bool success) {
        // range checks for rewardRate. Since rewardRate cannot be more than 100%, the max cap 
        // is _valueDivisor * 100, which then brings the fees to 100 (percentage) 
        require(rewardRate <= _valueDivisor.mul(100), "ST1");
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST2");
        _rewardRate.push(rewardRate);
        _lastMovingRewardTimestamp.push(block.timestamp);
        return true;
    }

    /**
    * @dev get reward rate and value divisor
    */
    function getRewardRate() public view virtual returns (uint256[] memory rewardRate, uint256 valueDivisor) {
        rewardRate = _rewardRate;
        valueDivisor = _valueDivisor;
    }

    /**
     * @dev get rewards till timestamp
     * @param to: account address
     */
    function getLastUserRewardTimestamp(address to) public view virtual returns (uint256 lastUserRewardTimestamp) {
        lastUserRewardTimestamp = _lastUserRewardTimestamp[to];
    }

    /**
     * @dev Mint new stokens for the provided 'address' and 'tokens'
     * @param to: account address, tokens: number of tokens
     *
     * Emits a {MintTokens} event with 'to' set to address and 'tokens' set to amount of tokens.
     *
     * Requirements:
     *
     * - `amount` cannot be less than zero.
     *
     */
    function mint(address to, uint256 tokens) public virtual override returns (bool) {
        require(tx.origin == to && _msgSender() == _liquidStakingContract, "ST3");
        _mint(to, tokens);
        return true;
    }

    /*
     * @dev Burn stokens for the provided 'address' and 'tokens'
     * @param to: account address, tokens: number of tokens
     *
     * Emits a {BurnTokens} event with 'to' set to address and 'tokens' set to amount of tokens.
     *
     * Requirements:
     *
     * - `amount` cannot be less than zero.
     *
     */
    function burn(address from, uint256 tokens) public  virtual override returns (bool) {
        require(tx.origin == from && _msgSender() == _liquidStakingContract, "ST4");
        _burn(from, tokens);
        return true;
    }

    /**
     * @dev Calculate pending rewards from the provided 'principal' & 'lastRewardTimestamp'. The rate is the moving reward rate.
     * @param principal: principal amount
     * @param lastRewardTimestamp: timestamp of last reward calculation performed
     */
    function _calculatePendingRewards(uint256 principal, uint256 lastRewardTimestamp) internal view returns (uint256 pendingRewards){
        uint256 _index;
        uint256 _rewardBlocks;
        uint256 _simpleInterestOfInterval;
        uint256 _temp;
        // return 0 if principal or timeperiod is zero
        if(principal == 0 || block.timestamp.sub(lastRewardTimestamp) == 0) return 0;
        // calculate rewards for each interval period between rewardRate changes
        uint256 _lastMovingRewardLength = _lastMovingRewardTimestamp.length.sub(1);
        for(_index = _lastMovingRewardLength; _index >= 0;){
            // logic applies for all indexes of array except last index
            if(_index < _lastMovingRewardTimestamp.length.sub(1)) {
                if(_lastMovingRewardTimestamp[_index] > lastRewardTimestamp) {
                    _rewardBlocks = (_lastMovingRewardTimestamp[_index.add(1)]).sub(_lastMovingRewardTimestamp[_index]);
                    _temp = principal.mulDiv(_rewardRate[_index], 100);
                    _simpleInterestOfInterval = _temp.mulDiv(_rewardBlocks, _valueDivisor);
                    pendingRewards = pendingRewards.add(_simpleInterestOfInterval);
                }
                else {
                    _rewardBlocks = (_lastMovingRewardTimestamp[_index.add(1)]).sub(lastRewardTimestamp);
                    _temp = principal.mulDiv(_rewardRate[_index], 100);
                    _simpleInterestOfInterval = _temp.mulDiv(_rewardBlocks, _valueDivisor);
                    pendingRewards = pendingRewards.add(_simpleInterestOfInterval);
                    break;
                }
            }
            // logic applies only for the last index of array
            else {
                if(_lastMovingRewardTimestamp[_index] > lastRewardTimestamp) {
                    _rewardBlocks = (block.timestamp).sub(_lastMovingRewardTimestamp[_index]);
                    _temp = principal.mulDiv(_rewardRate[_index], 100);
                    _simpleInterestOfInterval = _temp.mulDiv(_rewardBlocks, _valueDivisor);
                    pendingRewards = pendingRewards.add(_simpleInterestOfInterval);
                }
                else {
                    _rewardBlocks = (block.timestamp).sub(lastRewardTimestamp);
                    _temp = principal.mulDiv(_rewardRate[_index], 100);
                    _simpleInterestOfInterval = _temp.mulDiv(_rewardBlocks, _valueDivisor);
                    pendingRewards = pendingRewards.add(_simpleInterestOfInterval);
                    break;
                }
            }

            if(_index == 0) break;
            else {
                _index = _index.sub(1);
            }
        }
        return pendingRewards;
    }

    /**
     * @dev Calculate pending rewards for the provided 'address'. The rate is the moving reward rate.
     * @param to: account address
     */
    function calculatePendingRewards(address to) public view virtual override returns (uint256 pendingRewards){
        // Get the time in number of blocks
        uint256 _lastRewardTimestamp = _lastUserRewardTimestamp[to];
        // Get the balance of the account
        uint256 _balance = balanceOf(to);
        // calculate pending rewards using _calculatePendingRewards
        pendingRewards = _calculatePendingRewards(_balance, _lastRewardTimestamp);

        return pendingRewards;
    }

    /**
     * @dev Calculate rewards for the provided 'address'
     * @param to: account address
     */
    function _calculateRewards(address to) internal returns (uint256){
        // Calculate the rewards pending
        uint256 _reward = calculatePendingRewards(to);

        // Set the new stakedBlock to the current, 
        // as per Checks-Effects-Interactions pattern
        _lastUserRewardTimestamp[to] = block.timestamp;

        // mint uTokens only if reward is greater than zero
        if(_reward>0) {
            // Mint new uTokens and send to the callers account
            _uTokens.mint(to, _reward);
            emit CalculateRewards(to, _reward, block.timestamp);
        }

        return _reward;
    }

    /**
     * @dev Calculate rewards for the provided 'address'
     * @param to: account address
     *
     * Emits a {TriggeredCalculateRewards} event with 'to' set to address, 'reward' set to amount of tokens and 'timestamp'
     *
     */
    function calculateRewards(address to) public virtual override whenNotPaused returns (bool success) {
        require(to == _msgSender(), "ST5");
        uint256 reward =  _calculateRewards(to);
        emit TriggeredCalculateRewards(to, reward, block.timestamp);
        return true;
    }

    /**
     * @dev Calculate rewards for the provided 'holder address'
     * @param to: holder address
     */
    function _calculateHolderRewards(address to, address from, uint256 amount) internal returns (uint256){
        // holderContract and lpContract (lp token contract) need to be validated together because
        // it might not be practical to setup holder to collect reward pool but not StakeLP to distribute reward
        // since the reward distribution calculation starts the minute reward pool is created
        require(_whitelistedAddresses.contains(to) && _holderContractAddress[to] != address(0) && _lpContractAddress[to] != address(0), "ST6");
        uint256 _sTokenSupply = IHolder(_holderContractAddress[to]).getSTokenSupply(to, from, amount);

        // calculate the reward applying the moving reward rate
        uint256 _newRewards = _calculatePendingRewards(_sTokenSupply, _lastHolderRewardTimestamp[to]);

        // update the last timestamp of reward pool to the current time as per Checks-Effects-Interactions pattern
        _lastHolderRewardTimestamp[to] = block.timestamp;

        // Mint new uTokens and send to the holder contract account as updated reward pool
        if(_newRewards > 0) {
            _uTokens.mint(_holderContractAddress[to], _newRewards);
            emit CalculateHolderRewards(_holderContractAddress[to], _newRewards, block.timestamp);
        }

        return _newRewards;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        require(!paused(), "ST7");
        super._beforeTokenTransfer(from, to, amount);
        // uint256 _sTokenSupply;
        // uint256 _timePeriod;
        if(from == address(0)){
            // cannot have a scenario of transfer from address(0) to address(0)
            // if(to == address(0)){}

            if(!_whitelistedAddresses.contains(to)){
                _calculateRewards(to);
            }
            else {
                // IHolder(_holderContractAddress[to]).calculateHolderRewards(to, from, _rewardRate, _lastMovingRewardTimestamp);
                _calculateHolderRewards(to, from, amount);
            }
        }

        if(from != address(0) && !_whitelistedAddresses.contains(from)){

            if(to == address(0)){
                _calculateRewards(from);
            }

            if(to != address(0) && !_whitelistedAddresses.contains(to)){
                _calculateRewards(from);
                _calculateRewards(to);
            }

            if(to != address(0) && _whitelistedAddresses.contains(to)){
                _calculateRewards(from);
                // IHolder(_holderContractAddress[to]).calculateHolderRewards(to, from, _rewardRate, _lastMovingRewardTimestamp);
                _calculateHolderRewards(to, from, amount);
            }

        }

        if(from != address(0) && _whitelistedAddresses.contains(from)){

            if(to == address(0)){
                // IHolder(_holderContractAddress[to]).calculateHolderRewards(from, to, _rewardRate, _lastMovingRewardTimestamp);
                _calculateHolderRewards(from, to, amount);
            }

            if(to != address(0) && !_whitelistedAddresses.contains(to)){
                // IHolder(_holderContractAddress[to]).calculateHolderRewards(from, to, _rewardRate, _lastMovingRewardTimestamp);
                _calculateHolderRewards(from, to, amount);
                _calculateRewards(to);
            }

            if(to != address(0) && _whitelistedAddresses.contains(to)){
                // IHolder(_holderContractAddress[to]).calculateHolderRewards(from, address(0), _rewardRate, _lastMovingRewardTimestamp);
                _calculateHolderRewards(from, address(0), amount);

                // IHolder(_holderContractAddress[to]).calculateHolderRewards(to, address(0), _rewardRate, _lastMovingRewardTimestamp);
                _calculateHolderRewards(to, address(0), amount);
            }

        }
    }

    /*
    * @dev Set 'whitelisted address', performed by admin only
    * @param whitelistedAddress: contract address of the whitelisted party
    *
    * Emits a {setWhitelistedAddress} event
    *
    */
    function setWhitelistedAddress(address whitelistedAddress, address holderContractAddress, address lpContractAddress) public virtual returns (bool success){
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST8");
        // lpTokenERC20ContractAddress or sTokenReserveContractAddress can be address(0) but not whitelistedAddress
        require(whitelistedAddress != address(0), "ST9");
        // add the whitelistedAddress if it isn't already available
        if(!_whitelistedAddresses.contains(whitelistedAddress)) _whitelistedAddresses.add(whitelistedAddress);
        // add the contract addresses to holder mapping variable
        _holderContractAddress[whitelistedAddress] = holderContractAddress;
        _lpContractAddress[whitelistedAddress] = lpContractAddress;

        emit SetWhitelistedAddress(whitelistedAddress, holderContractAddress, lpContractAddress, block.timestamp);
        success = true;
        return success;
    }

    /*
  * @dev remove 'whitelisted address', performed by admin only
  * @param whitelistedAddress: contract address of the whitelisted party
  * @param holderContractAddress: holder contract address of the corresponding whitelistedAddress
  *
  * Emits a {RemoveWhitelistedAddress} event
  *
  */
    function removeWhitelistedAddress(address whitelistedAddress) public virtual returns (bool success){
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST10");
        require(whitelistedAddress != address(0), "ST11");
        // remove whitelistedAddress from the list
        _whitelistedAddresses.remove(whitelistedAddress);
        address _holderContractAddressLocal = _holderContractAddress[whitelistedAddress];
        address _lpContractAddressLocal = _lpContractAddress[whitelistedAddress];

        // delete holder contract values
        delete _holderContractAddress[whitelistedAddress];
        delete _lpContractAddress[whitelistedAddress];

        emit RemoveWhitelistedAddress(whitelistedAddress, _holderContractAddressLocal, _lpContractAddressLocal, block.timestamp);
        success = true;
        return success;
    }

    /*
    * @dev Set 'contract address', called from constructor
    * @param uTokenContract: utoken contract address
    *
    * Emits a {SetUTokensContract} event with '_contract' set to the utoken contract address.
    *
    */
    function setUTokensContract(address uTokenContract) public virtual override {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST12");
        _uTokens = IUTokens(uTokenContract);
        emit SetUTokensContract(uTokenContract);
    }

    /*
     * @dev Set 'contract address', called from constructor
     * @param liquidStakingContract: liquidStaking contract address
     *
     * Emits a {SetLiquidStakingContract} event with '_contract' set to the liquidStaking contract address.
     *
     */
    function setLiquidStakingContract(address liquidStakingContract) public virtual override{
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "ST13");
        _liquidStakingContract = liquidStakingContract;
        emit SetLiquidStakingContract(liquidStakingContract);
    }

    /**
      * @dev Triggers stopped state.
      *
      * Requirements:
      *
      * - The contract must not be paused.
      */
    function pause() public virtual returns (bool success) {
        require(hasRole(PAUSER_ROLE, _msgSender()), "ST14");
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
        require(hasRole(PAUSER_ROLE, _msgSender()), "ST15");
        _unpause();
        return true;
    }
}