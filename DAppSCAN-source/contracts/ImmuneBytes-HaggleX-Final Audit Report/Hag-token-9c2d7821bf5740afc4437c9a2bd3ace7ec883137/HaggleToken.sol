// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
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


/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
}

/**
 * @dev Implementation of the Owned Contract.
 *
 */
contract Owned is Context {

    address public _owner;
    address public _newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    modifier onlyOwner {
        require(_msgSender() == _owner, "HaggleX Token: Only Owner can perform this task");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        _newOwner = newOwner;
    }

    function acceptOwnership() external {
        require(_msgSender() == _newOwner, "HaggleX Token: Token Contract Ownership has not been set for the address");
        emit OwnershipTransferred(_owner, _newOwner);
        _owner = _newOwner;
        _newOwner = address(0);
    }
}






/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;


    string private _name;
    string private _symbol;
    uint8 private _decimals;

    bool private _paused;

    mapping(address => bool) private _blacklists;




    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_, uint8 decimals_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;


        _paused = false;
    }

    

    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory) {
        return _name;
    }



    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev Returns the paused state of transfers.
     */
    function paused() external view returns (bool) {
        return _paused;
    }

    /**
     * @dev Returns the frozen state of transfers.
     */
    function blacklisted(address _address) external view returns (bool) {
        return _blacklists[_address];
    }



    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) external virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) external virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "HaggleX Token: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "HaggleX Token: decreased allowance below zero"));
        return true;
    }


    /* Freeze transfer of tokens from the contract  
     *
     */
     function _pause() internal virtual  {
        require(_paused == false, "HaggleX Token: token transfer is unavailable");
        _paused = true;
    }

    /* Unfreeze transfer of tokens from the contract  
     *
     */
    function _unpause() internal virtual  {
        require(_paused == true, "HaggleX Token: token transfer is available");
        _paused = false;
    }

    /* Blacklist address from making transfer of tokens.
     *
     */
    function _blacklist(address _address) internal virtual {
        require(_blacklists[_address] == false, "HaggleX Token: account already blacklisted");
        _blacklists[_address] = true;
    }

    /* Whitelist address to make transfer of tokens.
     *
     */
    function _whitelist(address _address) internal virtual {
        require(_blacklists[_address] == true, "HaggleX Token: account already whitelisted");
        _blacklists[_address] = false;
    }

    


    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "HaggleX Token: transfer from the zero address");
        require(recipient != address(0), "HaggleX Token: transfer to the zero address");
        require(_paused == false, "HaggleX Token: token contract is not available");
        require(_blacklists[sender] == false,"HaggleX Token: sender account already blacklisted");
        require(_blacklists[recipient] == false,"HaggleX Token: sender account already blacklisted");


        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "HaggleX Token: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "HaggleX Token: mint to the zero address");
        require(_paused == false, "HaggleX Token: token contract is not available");
        require(_blacklists[account] == false,"HaggleX Token: account to mint to already blacklisted");



        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");
        require(_paused == false, "HaggleX Token: token contract is not available");
        require(_blacklists[account] == false,"HaggleX Token: account to burn from already blacklisted");



        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "HaggleX Token: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }


    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "HaggleX Token: approve from the zero address");
        require(spender != address(0), "HaggleX Token: approve to the zero address");
        require(_paused == false, "HaggleX Token: token contract approve is not available");
        require(_blacklists[owner] == false,"HaggleX Token: owner account already blacklisted");
        require(_blacklists[spender] == false,"HaggleX Token: spender account already blacklisted");



        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
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
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}




contract HaggleXToken is ERC20, Owned {
    using SafeMath for uint;
    
    event staked(address sender, uint amount, uint lockedTime);
    event unstaked(address sender, uint amount);
    
    address private _minter;

    uint private stakedSupply = 0;

    
    uint8 private STAKERS_PERCENTAGE = 60;
    uint8 private LEADERSHIP_BOARD_PERCENTAGE = 20;
    uint8 private UNIVERSAL_BASIC_INCOME_PERCENTAGE = 5;
    uint8 private DEVELOPMENT_PERCENTAGE = 15;

    
    address private CORE_TEAM = 0x821e90F8a572B62604877A2d5aa740Da0abDa07F;
    address private ADVISORS = 0x7610269058d82eC1F2E66a0ff981056622D387F6;
    address private CORE_INVESTORS = 0x811a622EB3e2a1a0Af8aE1a9AAaE8D1DC6016534;
    address private RESERVE = 0x609B1D6C5E6E2B48bfCe70eD7f88bAA3ECB9ca9d;
    address private CHARITY = 0x76a6a41282434a784e88Afc91Bd3E552A6F560f1;
    address private FOUNDING_STAFF = 0xAbE2526c2F8117B081817273d56fa09c4bcBDc49;
    address private AIRGRAB = 0xF985905b1510d51fd3da563D530263481F7c2a18;
    
    address private LEADERSHIP_BOARD = 0x7B9A1CF604396160F543f0FFaE50E076e15f39c8;
    address private UNIVERSAL_BASIC_INCOME = 0x9E7481AeD2585eC09066B8923570C49A38E06eAF;
    address private DEVELOPMENT = 0xaC92741D5BcDA49Ce0FF35a3D5be710bA870B260;
    
    

    struct StakeType {
        uint rewardPercent; // Percent reward to get each period
        uint lockedTime; // How long the stake is locked before allowed to withdraw
        uint totalStaked; //Total amount staked for 
    }
    
    mapping(uint => StakeType) private _stakingOptions;
    
    struct Stake {
        uint amount; // Amount staked
        uint startTime; // When staking started
        uint stakeType; // Type of stake
        uint lastWithdrawTime; // Track the last lastWithdrawTime time
        uint noOfWithdrawals; // Number of Withdrawals made
    }
    mapping(address => Stake[]) private _staking;
    
    constructor () public  ERC20("HaggleX Token", "HAG", 18){
                
       
        //Test Staking
        _stakingOptions[9].rewardPercent = 100;
        _stakingOptions[9].lockedTime = 20 minutes;
        _stakingOptions[9].totalStaked = 0;

        
        _stakingOptions[8].rewardPercent = 50;
        _stakingOptions[8].lockedTime = 30 minutes;
        _stakingOptions[8].totalStaked = 0;


        //staking for 3months 
        _stakingOptions[0].rewardPercent = 15;
        _stakingOptions[0].lockedTime = 12 weeks;
        _stakingOptions[0].totalStaked = 0;
        
        //staking for 6months 
        _stakingOptions[1].rewardPercent = 30;
        _stakingOptions[1].lockedTime = 24 weeks;
        _stakingOptions[1].totalStaked = 0;

        
        //staking for 12months 
        _stakingOptions[2].rewardPercent = 55;
        _stakingOptions[2].lockedTime = 48 weeks;
        _stakingOptions[2].totalStaked = 0;

        
        _owner = _msgSender();
        
        _mint(CORE_TEAM, 100000 ether);
        _mint(ADVISORS, 40000 ether);
        _mint(CORE_INVESTORS, 60000 ether);
        _mint(RESERVE, 100000 ether);
        _mint(CHARITY, 20000 ether);
        _mint(FOUNDING_STAFF, 80000 ether);
        _mint(AIRGRAB, 100000 ether);

    }
    
    /* Set the token contract for which to call for the stake reward
     *
     */
    function getTotalSupply() public view returns(uint) {
        return totalSupply() + stakedSupply;
    }
    
    /* Get available tokens
     *
     */
    function getMyBalance() external view returns(uint) {
        return balanceOf(_msgSender());
    }

    
    /* Get all tokens including staked
     *
     */
    function getMyFullBalance() external view returns(uint) {
        uint balance = balanceOf(_msgSender());
        for (uint i = 0; i < _staking[_msgSender()].length; i++){
            balance += getStakeAmount(i);
        } 
        return balance;
    }



      /* Get all stakes a address holds
     */
    function getStakes() external view returns (uint[3][] memory) {
        uint[3][] memory tempStakeList = new uint[3][](_staking[_msgSender()].length);
        for (uint i = 0; i < _staking[_msgSender()].length; i++){
            tempStakeList[i][0] = getStakeAmount(i);
            tempStakeList[i][1] = getRemainingLockTime(i);
            tempStakeList[i][2] = calculateDailyStakeReward(i);
        } 
        return tempStakeList;
    }
    
    

    
    /* Sets the address allowed to mint
     *
     */
    function setMinter(address minter_) external onlyOwner {
        _minter = minter_;
    }

    /* Puts a hold on token movement in the contract
    *
    */
    function pause() external onlyOwner  {
        _pause();
    }
    
    /* Release the hold on token movement in the contract
    *
    */
    function unpause() external onlyOwner {
        _unpause();
    }

      /* Blacklist address from making transfer of tokens.
     *
     */
    function blacklist(address _address) external onlyOwner {
        _blacklist(_address);
    }    

    /* Whitelist address to make transfer of tokens.
     *
     */
    function whitelist(address _address) external onlyOwner {
        _whitelist(_address);
    } 

     /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) external {
        _burn(_msgSender(), amount);
    }
    
    /**
    * @dev Internal function that burns an amount of the token of a given
    * account, deducting from the sender's allowance for said account. Uses the
    * internal burn function.
    * - account The account whose tokens will be burnt.
    * - amount The amount that will be burnt.
        */
    function burnFrom(address account, uint256 amount) external {
         uint256 decreasedAllowance = allowance(account, _msgSender()).sub(amount, "HaggleX Token: burn amount exceeds allowance");

        _approve(account, _msgSender(), decreasedAllowance);
        _burn(account, amount);
    }


    /* Mint an amount of tokens to an address
     *
     */
    function mint(address address_, uint256 amount_) external {
        require(_msgSender() == _minter || _msgSender() == _owner, "HaggleX Token: Only minter and owner can mint tokens!");
        _mint(address_, amount_);
    }
    
    /*Mint to multiple addresses in an array.
     *
     */
    function mintToMultipleAddresses(address[] memory _addresses, uint _amount) external onlyOwner {
        for(uint i = 0; i < _addresses.length; i++){
            _mint(_addresses[i],  _amount);
        }
    }
    
    
  
   
    /* returns true or false depending on if a stake is locked
     * or free to withdraw.
     */
    function isStakeLocked(uint stake_) private view returns (bool) {
        uint stakingTime = block.timestamp - _staking[_msgSender()][stake_].startTime;
        return stakingTime < _stakingOptions[_staking[_msgSender()][stake_].stakeType].lockedTime;
    }
    
    /* Returns the remaining lock time of a stake, if unlocked
     * returns 0.
     */
    function getRemainingLockTime(uint stake_) public view returns (uint) {
        uint stakingTime = block.timestamp - _staking[_msgSender()][stake_].startTime;
        if (stakingTime < _stakingOptions[_staking[_msgSender()][stake_].stakeType].lockedTime) {
            return _stakingOptions[_staking[_msgSender()][stake_].stakeType].lockedTime - stakingTime;
        } else {
            return 0;
        }
    }
    
    /* Returns the last Withdrawal time.
     */
    function getLastWithdrawalTime(uint stake_) external view returns (uint) {
       return _staking[_msgSender()][stake_].lastWithdrawTime;
    }
    
    /* Gets the number of withdrawals made already.
     */
    function getNoOfWithdrawals(uint stake_) external view returns (uint) {
        return _staking[_msgSender()][stake_].noOfWithdrawals;
    }
    
    
      /* Returns the amount of token provided with a stake.
     *
     */
    function getStakeAmount(uint stake_) public view returns (uint) {
        return _staking[_msgSender()][stake_].amount;
    } 


    /* Returns the Total number of staked amount for a particular stake option
    *
    */
    function getTotalStakedAmount(uint stakeType_) public view returns (uint) {
        return _stakingOptions[stakeType_].totalStaked;
    }



    
    
    /* Gets the Rewards from minted Tokens.
     */
    function getStakePercentageReward(uint stakeType_) private view returns (uint) {
        uint rewardPerc = getHalvedReward().mul(STAKERS_PERCENTAGE).mul(_stakingOptions[stakeType_].rewardPercent);
        return  rewardPerc.div(10000);
    }
    
    function getLeadershipBoardPercentageReward() private view returns (uint) {
        uint rewardPerc = getHalvedReward().mul(LEADERSHIP_BOARD_PERCENTAGE);
        return  rewardPerc.div(100);
    }
    
    function getUBIPercentageReward() private view returns (uint) {
        uint rewardPerc = getHalvedReward().mul(UNIVERSAL_BASIC_INCOME_PERCENTAGE);
        return  rewardPerc.div(100);
    }
    
    function getDevelopmentPercentageReward() private view returns (uint) {
        uint rewardPerc = getHalvedReward().mul(DEVELOPMENT_PERCENTAGE);
        return  rewardPerc.div(100);
    }
    


    /* Calculates the halved reward of a staking.
    */
    function getHalvedReward() public view returns (uint) {
            
            uint reward;

            if (getTotalSupply() >= 1000000 ether && getTotalSupply() <= 1116800 ether) {//halvening 1
               reward =  80 ether;
            }
            else if (getTotalSupply() > 1116800 ether && getTotalSupply() <= 1175200 ether) {//halvening 2
               
               reward =  40 ether;
            }
            else if (getTotalSupply() > 1175200 ether && getTotalSupply() <= 1204400 ether) { //halvening 3
               
               reward =  20 ether;
            }
            else if (getTotalSupply() > 1204400 ether && getTotalSupply() <= 1219000 ether) { //halvening 4
               
               reward =  10 ether;
            }
            else if (getTotalSupply() > 1219000 ether && getTotalSupply() <= 1226300 ether) { //halvening 5
               
               reward =  5 ether;
            }
            else if (getTotalSupply() > 1226300 ether && getTotalSupply() <= 1229950 ether) { //halvening 6
               
               reward =  2.5 ether;
            }
            else if (getTotalSupply() > 1229950 ether && getTotalSupply() <= 1231775 ether) { //halvening 7
               
               reward =  1.25 ether;
            }
            else if (getTotalSupply() > 1231775 ether) { //halvening 8
               
               reward =  0.625 ether;
            }
            else {

               reward =  0 ether;
            }
            
            return reward;
        }

    
    
    
    
     /* Calculates the Daily Reward of the of a particular stake
    *
     */
    function calculateDailyStakeReward(uint stake_) public view returns (uint) {
        uint reward = getStakeAmount(stake_).mul(getStakePercentageReward(_staking[_msgSender()][stake_].stakeType));
        return reward.div(getTotalStakedAmount(_staking[_msgSender()][stake_].stakeType));
    }
    
    
            //WITHDRAWALS
    /* Withdraw the staked reward delegated
    *
     */
    function withdrawStakeReward(uint stake_) external {
        require(isStakeLocked(stake_) == true, "Withdrawal no longer available, you can only Unstake now!");
        require(block.timestamp >= _staking[_msgSender()][stake_].lastWithdrawTime + 10 minutes, "Not yet time to withdraw reward");
        _staking[_msgSender()][stake_].noOfWithdrawals++;
        _staking[_msgSender()][stake_].lastWithdrawTime = block.timestamp;
        uint _amount = calculateDailyStakeReward(stake_);
        _mint(_msgSender(), _amount);    
    }
    
    function withdrawLeadershipBoardReward() external onlyOwner {
        uint lastWithdrawTime = 1614556800;
        require(block.timestamp >= lastWithdrawTime + 10 minutes, "Not yet time to withdraw Leadership Board reward");
        lastWithdrawTime = block.timestamp;
        uint _amount = getLeadershipBoardPercentageReward();
        _mint(LEADERSHIP_BOARD, _amount);    
    }
    
    function withdrawUBIReward() external onlyOwner {
        uint lastWithdrawTime = 1614556800;
        require(block.timestamp >= lastWithdrawTime + 10 minutes, "Not yet time to withdraw Leadership Board reward");
        lastWithdrawTime = block.timestamp;
        uint _amount = getUBIPercentageReward();
        _mint(UNIVERSAL_BASIC_INCOME, _amount);    
    }
    
    function withdrawDevelopmentReward() external onlyOwner {
        uint lastWithdrawTime = 1614556800;
        require(block.timestamp >= lastWithdrawTime + 10 minutes, "Not yet time to withdraw Leadership Board reward");
        lastWithdrawTime = block.timestamp;
        uint _amount = getDevelopmentPercentageReward();
        _mint(DEVELOPMENT, _amount);    
    }

    
     /* Stake
     *
     */
    function stake(uint amount_, uint stakeType_) external {
        _burn(_msgSender(), amount_);
        stakedSupply += amount_;
        Stake memory temp;
        temp.amount = amount_;
        temp.startTime = block.timestamp;
        temp.stakeType = stakeType_;    
        temp.lastWithdrawTime = block.timestamp;
        temp.noOfWithdrawals = 0;
        // SWC-128-DoS With Block Gas Limit: L1077
        _staking[_msgSender()].push(temp);
        _stakingOptions[stakeType_].totalStaked += amount_;
        emit staked(_msgSender(), amount_, _stakingOptions[stakeType_].lockedTime);
    }
    
    
    
    /* Unstake previous stake, mints back the original tokens,
     * sends mint function call to reward contract to mint the
     * reward to the sender address.
     */
    function unstake(uint stake_) external {
        require(isStakeLocked(stake_) != true, "HaggleX Token:Stake still locked!");
        uint _amount = _staking[_msgSender()][stake_].amount;
        _mint(_msgSender(), _amount);
        stakedSupply -= _amount;
        _stakingOptions[stake_].totalStaked -= _amount;
        _removeIndexInArray(_staking[_msgSender()], stake_);
        emit unstaked(_msgSender(), _amount);
    }
    
    
    
    /* Walks through an array from index, moves all values down one
     * step then pops the last value.
     */
    function _removeIndexInArray(Stake[] storage _array, uint _index) private {
        if (_index >= _array.length) return;
        for (uint i = _index; i<_array.length-1; i++){
            _array[i] = _array[i+1];
        }
        _array.pop();
    }
    
}
