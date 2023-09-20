// SPDX-License-Identifier: MIT
// 
pragma solidity 0.8.9;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "./library/DateTime.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {BEP20PresetMinterPauser}.
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
contract AOC_BEP is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using DateTimeLibrary for uint;

    struct Level {
        uint256 start;
        uint256 end;
        uint256 percentage;
    }

    struct UserInfo {
        uint256 balance;
        uint256 level;
        uint256 year;
        uint256 month;
    }
    
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public blacklisted;
    mapping (address => bool) public excludedFromRAMS;
    mapping (address => bool) public includedInLTAF;
    mapping(uint256 => Level) public levels;
    mapping(address => UserInfo) public userInfo;

    uint256 private _totalSupply;
    uint8 private constant _decimal = 18;
    string private constant _name = "Alpha Omega Coin";
    string private constant _symbol = "AOC BEP20";
    uint256 public ltafPercentage;


    event ExternalTokenTransfered(
        address from,
        address to,
        uint256 amount
    );
    
    event BNBFromContractTransferred(
        uint256 amount
    );
    
    event Blacklisted(
        string indexed action,
        address indexed to,
        uint256 at
       
    );
    
    event RemovedFromBlacklist(
        string indexed action,
        address indexed to,
        uint256 at
    );

    event IncludedInRAMS(
        address indexed account
    );

    event ExcludedFromRAMS(
        address indexed account
    );

    event IncludedInLTAF(
        address indexed account
    );

    event ExcludedFromLTAF(
        address indexed account
    );

    event LtafPercentageUpdated(
        uint256 percentage
    );

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The defaut value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function initialize() public initializer {
        // SWC-118-Incorrect Constructor Name: L115 - L126
        _mint(_msgSender(), (1000 * 10**9 * 10**18)); //mint the initial total supply
        ltafPercentage = 50;

        addLevels(1, 1640995200, 1704153599, 20);
        addLevels(2, 1704153600, 1767311999, 15);
        addLevels(3, 1767312000, 1830383999, 10);
        addLevels(4, 1830384000, 0, 5);

        // initializing
        __Pausable_init_unchained();  
        __Ownable_init_unchained();  
        __Context_init_unchained();
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev Returns the name of the token.
     */
    function name() external view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {BEP20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() external view virtual override returns (uint8) {
        return _decimal;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() external view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) external view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) external virtual override whenNotPaused returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) external view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) external virtual override whenNotPaused returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {BEP20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external virtual override whenNotPaused returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "BEP20: transfer amount exceeds allowance");
        _approve(sender, _msgSender(), currentAllowance - amount);

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
    function increaseAllowance(address spender, uint256 addedValue) external virtual whenNotPaused returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
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
    function decreaseAllowance(address spender, uint256 subtractedValue) external virtual whenNotPaused returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "BEP20: decreased allowance below zero");
        _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        return true;
    }
    
    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {BEP20-_burn}.
     */
    function burn(uint256 amount) external virtual onlyOwner whenNotPaused returns (bool) {
        _burn(_msgSender(), amount);
        return true;
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {BEP20-_burn} and {BEP20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) external virtual onlyOwner whenNotPaused {
        uint256 currentAllowance = _allowances[account][_msgSender()];
        require(currentAllowance >= amount, "BEP20: burn amount exceeds allowance");
        _approve(account, _msgSender(), currentAllowance - amount);
        _burn(account, amount);
    }

    function blacklistUser(address _address) external onlyOwner whenNotPaused {
        require(!blacklisted[_address], "User is already blacklisted");
        blacklisted[_address] = true;
        emit Blacklisted("Blacklisted", _address, block.timestamp);
	}
	
	function removeFromBlacklist(address _address) external onlyOwner whenNotPaused {
	    require(blacklisted[_address], "User is not in the blacklist");
	    blacklisted[_address] = false;
	    emit RemovedFromBlacklist("Removed", _address, block.timestamp);
        
	}

    function includeInRAMS(address account) external onlyOwner whenNotPaused {
        require(excludedFromRAMS[account], "User is already included");
        excludedFromRAMS[account] = false;
        emit IncludedInRAMS(account);
	}

    function excludeFromRAMS(address account) external onlyOwner whenNotPaused {
        require(!excludedFromRAMS[account], "User is already excluded");
        excludedFromRAMS[account] = true;
        emit ExcludedFromRAMS(account);
	}

    function includeInLTAF(address account) external onlyOwner whenNotPaused {
        require(!includedInLTAF[account], "User is already included");
        includedInLTAF[account] = true;
        emit IncludedInLTAF(account);
	}

    function excludedFromLTAF(address account) external onlyOwner whenNotPaused {
        require(includedInLTAF[account], "User is already excluded");
        includedInLTAF[account] = false;
        emit ExcludedFromLTAF(account);
	}

    function updateLtafPercentage(uint256 percentage) external onlyOwner whenNotPaused {
        require(percentage > 0, "Percentage must be greater than zero");
        ltafPercentage = percentage;
        emit LtafPercentageUpdated(ltafPercentage);
    }

    /**
     * @dev Pause `contract` - pause events.
     *
     * See {ERC20Pausable-_pause}.
     */
    function pauseContract() external virtual onlyOwner {
        _pause();
    }
    
    /**
     * @dev Pause `contract` - pause events.
     *
     * See {ERC20Pausable-_pause}.
     */
    function unPauseContract() external virtual onlyOwner {
        _unpause();
    }

// SWC-135-Code With No Effects: L360
// SWC-105-Unprotected Ether Withdrawal: L361
    function withdrawBNBFromContract(address payable recipient, uint256 amount) external onlyOwner payable {
        require(recipient != address(0), "Address cant be zero address");
        require(amount <= address(this).balance, "withdrawBNBFromContract: withdraw amount exceeds BNB balance");              
        recipient.transfer(amount);        
        emit BNBFromContractTransferred(amount);
    }

    function withdrawToken(address _tokenContract, uint256 _amount) external onlyOwner {
        require(_tokenContract != address(0), "Address cant be zero address");
		// require amount greter than 0
		require(_amount > 0, "amount cannot be 0");
        IERC20Upgradeable tokenContract = IERC20Upgradeable(_tokenContract);
        require(tokenContract.balanceOf(address(this)) > _amount, "withdrawToken: withdraw amount exceeds token balance");
		tokenContract.transfer(msg.sender, _amount);
        emit ExternalTokenTransfered(_tokenContract, msg.sender, _amount);
	}

    // to recieve BNB
    receive() external payable {}

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
        require(!blacklisted[sender] || !blacklisted[recipient], "AOC: Cant't transfer, User is blacklisted");
        require(sender != address(0), "AOC: transfer from the zero address");
        require(recipient != address(0), "AOC: transfer to the zero address");

        if(includedInLTAF[sender] || !excludedFromRAMS[sender]) {
            // convert current timestamp to uint256
            (uint256 year, uint256 month, uint256 day) = DateTimeLibrary.timestampToDate(block.timestamp);
            if(day == 1 || year != userInfo[sender].year || month != userInfo[sender].month || userInfo[sender].level == 0) updateUserInfo(sender, year, month);

            if(includedInLTAF[sender]) {
                // validate amount
                require(amount <= ((userInfo[sender].balance * ltafPercentage) / 10**2), "BEP20: Amount is higher than LTAF percentage");
            } else if(!excludedFromRAMS[sender]) {
                // validate amount
                if(userInfo[sender].level > 0) require(amount <= ((userInfo[sender].balance * levels[userInfo[sender].level].percentage) / 10**2), "BEP20: Amount is higher");
            }
        }

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "BEP20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function updateUserInfo(address account, uint256 year, uint256 month) internal {
        userInfo[account].balance = _balances[account];
        userInfo[account].year = year;
        userInfo[account].month = month;
        for(uint256 i = 1; i <= 4; i++) {
            if(i == 4) {
                userInfo[account].level = i;
                break;
            }
            if(block.timestamp >= levels[i].start && block.timestamp <= levels[i].end) {
                userInfo[account].level = i;
                break;
            }
        }
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
        require(account != address(0), "BEP20: mint to the zero address");
        _totalSupply += amount;
        _balances[account] += amount;
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
        require(account != address(0), "BEP20: burn from the zero address");
        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "BEP20: burn amount exceeds balance");
        _balances[account] = accountBalance - amount;
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function addLevels(uint256 level, uint256 startDay, uint256 endDay, uint256 percentage) internal {
        levels[level] = Level({
            start: startDay,
            end: endDay,
            percentage: percentage
        });
    }
    
}