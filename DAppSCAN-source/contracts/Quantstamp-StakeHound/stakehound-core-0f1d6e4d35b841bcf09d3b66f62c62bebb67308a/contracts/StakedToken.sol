// contracts/StakedToken.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.6.10;

import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";
import "./DownstreamCaller.sol";

contract StakedToken is IERC20, Initializable, OwnableUpgradeSafe, PausableUpgradeSafe  {
    using SafeMath for uint256;

    /**
     * @dev Emitted when supply controller is changed
     */
    event LogSupplyControllerUpdated(address supplyController);
    /**
     * @dev Emitted when token distribution happens
     */
    event LogTokenDistribution(uint256 oldTotalSupply, uint256 supplyChange, bool positive, uint256 newTotalSupply);


    address public supplyController;

    uint256 private MAX_UINT256;

    // Defines the multiplier applied to shares to arrive at the underlying balance
    uint256 private _maxSupply;

    uint256 private _sharesPerToken;
    uint256 private _totalSupply;
    uint256 private _totalShares;

    mapping(address => uint256) private _shareBalances;
    //Denominated in tokens not shares, to align with user expectations
    mapping(address => mapping(address => uint256)) private _allowedTokens;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    mapping(address => bool) public isBlacklisted;
    /**
     * @dev Emitted when account blacklist status changes
     */
    event Blacklisted(address indexed account, bool isBlacklisted);

    DownstreamCaller public downstreamCaller;

    modifier onlySupplyController() {
        require(msg.sender == supplyController);
        _;
    }

    modifier validRecipient(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    function initialize(
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        uint256 maxSupply_,
        uint256 initialSupply_
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        supplyController = msg.sender;

        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;

        MAX_UINT256 = ~uint256(0);

        // Maximise precision by picking the largest possible sharesPerToken value
        // It is crucial to pick a maxSupply value that will never be exceeded
        _sharesPerToken = MAX_UINT256.div(maxSupply_);

        _maxSupply = maxSupply_;
        _totalSupply = initialSupply_;
        _totalShares = initialSupply_.mul(_sharesPerToken);
        _shareBalances[msg.sender] = _totalShares;

        downstreamCaller = new DownstreamCaller();

        emit Transfer(address(0x0), msg.sender, _totalSupply);
    }

    /**
     * Set the address that can mint, burn and rebase
     *
     * @param supplyController_ Address of the new supply controller
     */
    function setSupplyController(address supplyController_) external onlyOwner {
        supplyController = supplyController_;
        emit LogSupplyControllerUpdated(supplyController);
    }

    /**
     * Distribute a supply increase to all token holders proportionally
     *
     * @param supplyChange_ Increase of supply in token units
     * @return The updated total supply
     */
    function distributeTokens(uint256 supplyChange_, bool positive) external onlySupplyController returns (uint256) {
        uint256 newTotalSupply;
        if (positive) {
            newTotalSupply = _totalSupply.add(supplyChange_);
        } else {
            newTotalSupply = _totalSupply.sub(supplyChange_);
        }

        require(newTotalSupply > 0, "rebase cannot make supply 0");

        _sharesPerToken = _totalShares.div(newTotalSupply);

        // Set correct total supply in case of mismatch caused by integer division
        newTotalSupply = _totalShares.div(_sharesPerToken);

        emit LogTokenDistribution(_totalSupply, supplyChange_, positive, newTotalSupply);

        _totalSupply = newTotalSupply;

        // Call downstream transactions
        downstreamCaller.executeTransactions();

        return _totalSupply;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
     * Set the name of the token
     * @param name_ the new name of the token.
     */
    function setName(string calldata name_) external onlyOwner {
        _name = name_;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    /**
     * Set the symbol of the token
     * @param symbol_ the new symbol of the token.
     */
    function setSymbol(string calldata symbol_) external onlyOwner {
        _symbol = symbol_;
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
     * @return The total supply of the underlying token
     */
    function totalSupply() external override view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @return The total supply in shares
     */
    function totalShares() external view returns (uint256) {
        return _totalShares;
    }

    /**
     * @param who The address to query.
     * @return The balance of the specified address.
     */
    function balanceOf(address who) external override view returns (uint256) {
        return _shareBalances[who].div(_sharesPerToken);
    }

    /**
     * @param who The address to query.
     * @return The balance of the specified address in shares.
     */
    function sharesOf(address who) external view returns (uint256) {
        return _shareBalances[who];
    }

    /**
     * @dev Transfer tokens to a specified address.
     * @param to The address to transfer to.
     * @param value The amount to be transferred.
     * @return True on success, false otherwise.
     */
    function transfer(address to, uint256 value) external override validRecipient(to) whenNotPaused returns (bool) {
        require(!isBlacklisted[msg.sender], "from blacklisted");
        require(!isBlacklisted[to], "to blacklisted");

        uint256 shareValue = value.mul(_sharesPerToken);
        _shareBalances[msg.sender] = _shareBalances[msg.sender].sub(
            shareValue,
            "transfer amount exceed account balance"
        );
        _shareBalances[to] = _shareBalances[to].add(shareValue);
        emit Transfer(msg.sender, to, value);
        return true;
    }

    /**
     * @dev Function to check the amount of tokens that an owner has allowed to a spender.
     * @param owner_ The address which owns the funds.
     * @param spender The address which will spend the funds.
     * @return The number of tokens still available for the spender.
     */
    function allowance(address owner_, address spender) external override view returns (uint256) {
        return _allowedTokens[owner_][spender];
    }

    /**
     * @dev Transfer tokens from one address to another.
     * @param from The address you want to send tokens from.
     * @param to The address you want to transfer to.
     * @param value The amount of tokens to be transferred.
     */
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external override validRecipient(to) whenNotPaused returns (bool) {
        require(!isBlacklisted[from], "from blacklisted");
        require(!isBlacklisted[to], "to blacklisted");

        _allowedTokens[from][msg.sender] = _allowedTokens[from][msg.sender].sub(
            value,
            "transfer amount exceeds allowance"
        );

        uint256 shareValue = value.mul(_sharesPerToken);
        _shareBalances[from] = _shareBalances[from].sub(shareValue, "transfer amount exceeds account balance");
        _shareBalances[to] = _shareBalances[to].add(shareValue);
        emit Transfer(from, to, value);

        return true;
    }

    /**
     * @dev Approve the passed address to spend the specified amount of tokens on behalf of
     * msg.sender. This method is included for ERC20 compatibility.
     * increaseAllowance and decreaseAllowance should be used instead.
     * Changing an allowance with this method brings the risk that someone may transfer both
     * the old and the new allowance - if they are both greater than zero - if a transfer
     * transaction is mined before the later approve() call is mined.
     *
     * @param spender The address which will spend the funds.
     * @param value The amount of tokens to be spent.
     */
    function approve(address spender, uint256 value) external override returns (bool) {
        require(!isBlacklisted[msg.sender], "owner blacklisted");
        require(!isBlacklisted[spender], "spender blacklisted");

        _allowedTokens[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /**
     * @dev Increase the amount of tokens that an owner has allowed to a spender.
     * This method should be used instead of approve() to avoid the double approval vulnerability
     * described above.
     * @param spender The address which will spend the funds.
     * @param addedValue The amount of tokens to increase the allowance by.
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        require(!isBlacklisted[msg.sender], "owner blacklisted");
        require(!isBlacklisted[spender], "spender blacklisted");

        _allowedTokens[msg.sender][spender] = _allowedTokens[msg.sender][spender].add(addedValue);
        emit Approval(msg.sender, spender, _allowedTokens[msg.sender][spender]);
        return true;
    }

    /**
     * @dev Decrease the amount of tokens that an owner has allowed to a spender.
     *
     * @param spender The address which will spend the funds.
     * @param subtractedValue The amount of tokens to decrease the allowance by.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool) {
        require(!isBlacklisted[msg.sender], "owner blacklisted");
        require(!isBlacklisted[spender], "spender blacklisted");

        uint256 oldValue = _allowedTokens[msg.sender][spender];
        if (subtractedValue >= oldValue) {
            _allowedTokens[msg.sender][spender] = 0;
        } else {
            _allowedTokens[msg.sender][spender] = oldValue.sub(subtractedValue);
        }
        emit Approval(msg.sender, spender, _allowedTokens[msg.sender][spender]);
        return true;
    }

    /** Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply, keeping the tokens per shares constant
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     */
    function mint(address account, uint256 amount) external onlySupplyController validRecipient(account) {
        require(!isBlacklisted[account], "account blacklisted");

        _totalSupply = _totalSupply.add(amount);
        uint256 shareAmount = amount.mul(_sharesPerToken);
        _totalShares = _totalShares.add(shareAmount);
        _shareBalances[account] = _shareBalances[account].add(shareAmount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * Destroys `amount` tokens from `account`, reducing the
     * total supply while keeping the tokens per shares ratio constant
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function burn(uint256 amount) external onlySupplyController {
        address account = msg.sender;

        uint256 shareAmount = amount.mul(_sharesPerToken);
        _shareBalances[account] = _shareBalances[account].sub(shareAmount, "burn amount exceeds balance");
        _totalShares = _totalShares.sub(shareAmount);
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }


    // Downstream transactions

    /**
     * @return Address of the downstream caller contract
     */
    function downstreamCallerAddress() external view returns (address) {
        return address(downstreamCaller);
    }

    /**
     * @param _downstreamCaller Address of the new downstream caller contract
     */
    function setDownstreamCaller(DownstreamCaller _downstreamCaller) external onlyOwner {
        downstreamCaller = _downstreamCaller;
    }

    /**
     * @notice Adds a transaction that gets called for a downstream receiver of token distributions
     * @param destination Address of contract destination
     * @param data Transaction data payload
     */
    function addTransaction(address destination, bytes memory data) external onlySupplyController {
        downstreamCaller.addTransaction(destination, data);
    }

    /**
     * @param index Index of transaction to remove.
     *              Transaction ordering may have changed since adding.
     */
    function removeTransaction(uint256 index) external onlySupplyController {
        downstreamCaller.removeTransaction(index);
    }

    /**
     * @param index Index of transaction. Transaction ordering may have changed since adding.
     * @param enabled True for enabled, false for disabled.
     */
    function setTransactionEnabled(uint256 index, bool enabled) external onlySupplyController {
        downstreamCaller.setTransactionEnabled(index, enabled);
    }

    /**
     * @return Number of transactions, both enabled and disabled, in transactions list.
     */
    function transactionsSize() external view returns (uint256) {
        return downstreamCaller.transactionsSize();
    }


    /**
     * @dev Triggers stopped state.
     */
    function pause() external onlySupplyController {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     */
    function unpause() external onlySupplyController {
        _unpause();
    }

    /**
     * @dev Set blacklisted status for the account.
     * @param account address to set blacklist flag for
     * @param _isBlacklisted blacklist flag value
     *
     * Requirements:
     *
     * - `msg.sender` should be owner.
     */
    function setBlacklisted(address account, bool _isBlacklisted) external onlySupplyController {
        isBlacklisted[account] = _isBlacklisted;
        emit Blacklisted(account, _isBlacklisted);
    }
}
