pragma solidity 0.6.0;
pragma experimental ABIEncoderV2;

library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () internal { }

    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () internal {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
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
 

interface IRevoTokenContract{
  function balanceOf(address account) external view returns (uint256);
  function totalSupply() external view returns (uint256);
  function transfer(address recipient, uint256 amount) external returns (bool);
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
}



contract RevoPreSaleContract is Ownable {
    using SafeMath for uint;
    
    uint256 public tokenPurchaseInWei;
    uint256 public contributors;
    bool public isListingDone;
    bool public isWhitelistEnabled = true;
    bool public started = true;
    
    // PRE-SALE PRICE 0.11 USDT
    uint256 public constant BASE_PRICE_IN_WEI = 110000000000000000;
    uint256 public constant FOURTEEN_DAYS_IN_SECONDS = 1209600;
    
    mapping (address=>bool) public whitelistedAddresses;
    mapping (address=>uint256) public whitelistedAddressesCap;
    mapping (address=>bool) public salesDonePerUser;
    
     /// minimum = 900 USDT
    uint256 public minWeiPurchasable = 800000000000000000000;
    //MAX ALLOCATION BY DEFAULT
    uint256 public maxDefaultUsdtETH = 5000;
    //TOKEN CAP IN WEI
    uint256 public tokenCapRevoInWei;
    
    //Vesting start date 04/12/2021 6PM00
    uint256 public vestingStartTime = 1618250400;
    
    //ADDRESSES & CONTRACTS
    address public usdtAddress;
    address public revoAddress;
    IRevoTokenContract private revoToken;
    IRevoTokenContract private usdtToken;
    
    event BuyTokenEvent(uint _tokenPurchased);
  
   /**
    * @dev Error messages for require statements
    */
    string internal constant ALREADY_LOCKED = 'Tokens already locked';
    string internal constant NOT_LOCKED = 'No tokens locked';
    string internal constant AMOUNT_ZERO = 'Amount can not be 0';
    
    mapping(address => bytes32[]) public lockReason;

    struct lockToken {
        uint256 amount;
        uint256 validity;
        bool claimed;
    }

    mapping(address => mapping(bytes32 => lockToken)) public locked;

    event Locked(
        address indexed _of,
        bytes32 indexed _reason,
        uint256 _amount,
        uint256 _validity
    );

    event Unlocked(
        address indexed _of,
        bytes32 indexed _reason,
        uint256 _amount
    );

   /**
    * @dev constructor to mint initial tokens
    * Shall update to _mint once openzepplin updates their npm package.
    */
    constructor(address revoTokenAddress, address usdtAddress, uint256 maxCapRevoInWei) public {
        setUSDTAddress(usdtAddress);
        setRevoAddress(revoTokenAddress);
        setTokenCapInWei(maxCapRevoInWei);
    }
    
    /**
   * Low level token purchase function
   */
    function buyTokens(uint256 amountUSDTInWei) public payable validPurchase(amountUSDTInWei) {
        salesDonePerUser[msg.sender] = true;

        uint256 tokenCountWei = amountUSDTInWei.mul(10**18).div(BASE_PRICE_IN_WEI);

        tokenPurchaseInWei = tokenPurchaseInWei.add(tokenCountWei);
        
        require(tokenPurchaseInWei <= tokenCapRevoInWei, "Not enough token for sale.");
    
        contributors = contributors.add(1);
        
        forwardFunds(amountUSDTInWei);
        
        //LOCK PART
        uint lockAmountStage = calculatePercentage(tokenCountWei, 20, 1000000);

        lock("lock_1", lockAmountStage, 0); //First unlock at listing
        lock("lock_2", lockAmountStage, vestingStartTime.sub(now).add(FOURTEEN_DAYS_IN_SECONDS.mul(1))); //04/12/2021 + 14 days
        lock("lock_3", lockAmountStage, vestingStartTime.sub(now).add(FOURTEEN_DAYS_IN_SECONDS.mul(2))); //04/12/2021 + 28 days
        lock("lock_4", lockAmountStage, vestingStartTime.sub(now).add(FOURTEEN_DAYS_IN_SECONDS.mul(3))); //04/12/2021 + 42 days
        lock("lock_5", lockAmountStage, vestingStartTime.sub(now).add(FOURTEEN_DAYS_IN_SECONDS.mul(4))); //04/12/2021 + 56 days
        

        emit BuyTokenEvent(tokenPurchaseInWei);
    }
    
    modifier validPurchase(uint256 amountUSDTInWei) {
        require(started, "Pre-sale not started.");
        require(!isWhitelistEnabled || whitelistedAddresses[msg.sender] == true, "Not whitelisted.");
        require(amountUSDTInWei >= minWeiPurchasable, "Below min price allowed.");
        require(amountUSDTInWei <= (whitelistedAddressesCap[msg.sender]).mul(10**18), "Above max price allowed.");
        require(salesDonePerUser[msg.sender] == false, "Address has already bought token.");
        _;
    }

    /**
    * Forwards funds to the tokensale wallet
    */
    function forwardFunds(uint256 amount) internal {
        usdtToken.transferFrom(msg.sender, address(owner()), amount);
    }


    function enableWhitelistVerification() public onlyOwner {
        isWhitelistEnabled = true;
    }
    
    function disableWhitelistVerification() public onlyOwner {
        isWhitelistEnabled = false;
    }
    
    function changeMinWeiPurchasable(uint256 value) public onlyOwner {
        minWeiPurchasable = value;
    }
    
    function changeStartedState(bool value) public onlyOwner {
        started = value;
    }
    
    function addToWhitelistPartners(address[] memory _addresses, uint256[] memory _maxCaps) public onlyOwner {
        for(uint256 i = 0; i < _addresses.length; i++) {
            whitelistedAddresses[_addresses[i]] = true;
            updateWhitelistAdressCap(_addresses[i], _maxCaps[i]);
        }
    }
    
    function updateWhitelistAdressCap(address _address, uint256 _maxCap) public onlyOwner {
        whitelistedAddressesCap[_address] = _maxCap;
    }

    function addToWhitelist(address _address) public onlyOwner {
        whitelistedAddresses[_address] = true;
        whitelistedAddressesCap[_address] = maxDefaultUsdtETH;
    }
    
    function addToWhitelist(address[] memory addresses) public onlyOwner {
        for(uint i = 0; i < addresses.length; i++) {
            addToWhitelist(addresses[i]);
        }
    }
    
    function isAddressWhitelisted(address _address) view public returns(bool) {
        return !isWhitelistEnabled || whitelistedAddresses[_address] == true;
    }
    
    function withdrawTokens(uint256 amount) public onlyOwner {
        revoToken.transfer(owner(), amount);
    }
    
    function setListingDone(bool isDone) public onlyOwner {
        isListingDone = isDone;
    }
    
    function setUSDTAddress(address _usdtAddress) public onlyOwner{
        usdtAddress = _usdtAddress;
        usdtToken = IRevoTokenContract(_usdtAddress);
    }
    
    function setRevoAddress(address _revoAddress) public onlyOwner{
        revoAddress = _revoAddress;
        revoToken = IRevoTokenContract(_revoAddress);
    }
    
    //ETH Value not WEI
    function setMaxDefaultUsdtAllocInEth(uint256 _maxDefaultUsdtETH) public onlyOwner{
        maxDefaultUsdtETH = _maxDefaultUsdtETH;
    }
    
    //Set Token Cap in WEI
    function setTokenCapInWei(uint256 _tokenCapRevoInWei) public onlyOwner{
        tokenCapRevoInWei = _tokenCapRevoInWei;
    }
    
    /*
        LOCK PART
    */

    /**
     * @dev Locks a specified amount of tokens against an address,
     *      for a specified reason and time
     * @param _reason The reason to lock tokens
     * @param _amount Number of tokens to be locked
     * @param _time Lock time in seconds
     */
    function lock(string memory _reason, uint256 _amount, uint256 _time) private returns (bool) {
        bytes32 reason = stringToBytes32(_reason);
        uint256 validUntil = now.add(_time); //solhint-disable-line

        // If tokens are already locked, then functions extendLock or
        // increaseLockAmount should be used to make any changes
        require(tokensLocked(msg.sender, bytes32ToString(reason)) == 0, ALREADY_LOCKED);
        require(_amount != 0, AMOUNT_ZERO);

        if (locked[msg.sender][reason].amount == 0)
            lockReason[msg.sender].push(reason);

        locked[msg.sender][reason] = lockToken(_amount, validUntil, false);

        emit Locked(msg.sender, reason, _amount, validUntil);
        return true;
    }
    
    /**
     * @dev Returns tokens locked for a specified address for a
     *      specified reason
     *
     * @param _of The address whose tokens are locked
     * @param _reason The reason to query the lock tokens for
     */
    function tokensLocked(address _of, string memory _reason) public view returns (uint256 amount) {
        bytes32 reason = stringToBytes32(_reason);
        if (!locked[_of][reason].claimed)
            amount = locked[_of][reason].amount;
    }

    /**
     * @dev Returns total tokens held by an address (locked + transferable)
     * @param _of The address to query the total balance of
     */
    function totalBalanceOf(address _of) public view returns (uint256 amount) {
        amount = revoToken.balanceOf(_of);

        for (uint256 i = 0; i < lockReason[_of].length; i++) {
            amount = amount.add(tokensLocked(_of, bytes32ToString(lockReason[_of][i])));
        }   
    }

    /**
     * @dev Returns unlockable tokens for a specified address for a specified reason
     * @param _of The address to query the the unlockable token count of
     * @param _reason The reason to query the unlockable tokens for
     */
    function tokensUnlockable(address _of, string memory _reason) public view returns (uint256 amount) {
        bytes32 reason = stringToBytes32(_reason);
        if (locked[_of][reason].validity <= now && !locked[_of][reason].claimed) //solhint-disable-line
            amount = locked[_of][reason].amount;
    }

    /**
     * @dev Unlocks the unlockable tokens of a specified address
     */
    function unlock() public returns (uint256 unlockableTokens) {
        require(isListingDone, "Listing not done");
        
        uint256 lockedTokens;

        for (uint256 i = 0; i < lockReason[msg.sender].length; i++) {
            lockedTokens = tokensUnlockable(msg.sender, bytes32ToString(lockReason[msg.sender][i]));
            if (lockedTokens > 0) {
                unlockableTokens = unlockableTokens.add(lockedTokens);
                locked[msg.sender][lockReason[msg.sender][i]].claimed = true;
                emit Unlocked(msg.sender, lockReason[msg.sender][i], lockedTokens);
            }
        }  

        if (unlockableTokens > 0)
            revoToken.transfer(msg.sender, unlockableTokens);
    }

    /**
     * @dev Gets the unlockable tokens of a specified address
     * @param _of The address to query the the unlockable token count of
     */
    function getUnlockableTokens(address _of) public view returns (uint256 unlockableTokens) {
        for (uint256 i = 0; i < lockReason[_of].length; i++) {
            unlockableTokens = unlockableTokens.add(tokensUnlockable(_of, bytes32ToString(lockReason[_of][i])));
        }  
    }
    
    function getremainingLockTime(address _of, string memory _reason) public view returns (uint256 remainingTime) {
        bytes32 reason = stringToBytes32(_reason);
        if (locked[_of][reason].validity > now && !locked[_of][reason].claimed) //solhint-disable-line
            remainingTime = locked[_of][reason].validity.sub(now);
    }
    
    function getremainingLockDays(address _of, string memory _reason) public view returns (uint256 remainingDays) {
        bytes32 reason = stringToBytes32(_reason);
        if (locked[_of][reason].validity > now && !locked[_of][reason].claimed) //solhint-disable-line
            remainingDays = (locked[_of][reason].validity.sub(now)) / 86400;
    }
    
    /*
    UTILS
    */
    
    function stringToBytes32(string memory source) public pure returns (bytes32 result) {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }
    
        assembly {
            result := mload(add(source, 32))
        }
    }
    
    function bytes32ToString(bytes32 x) public pure returns (string memory) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (uint256 j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }
    
    function calculatePercentage(uint256 amount, uint256 percentage, uint256 precision) public pure returns(uint256){
        return amount.mul(precision).mul(percentage).div(100).div(precision);
    }
}