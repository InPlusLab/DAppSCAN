pragma solidity ^0.4.18;

import 'zeppelin-solidity/contracts/token/ERC20/StandardToken.sol';
import 'zeppelin-solidity/contracts/token/ERC20/BurnableToken.sol';
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';


contract Cloudbric is StandardToken, BurnableToken, Ownable {
    using SafeMath for uint256;

    string public constant symbol = "CLB";
    string public constant name = "Cloudbric";
    uint8 public constant decimals = 18;
    uint256 public constant INITIAL_SUPPLY = 1000000000 * (10 ** uint256(decimals));
    uint256 public constant TOKEN_SALE_ALLOWANCE = 540000000 * (10 ** uint256(decimals));
    uint256 public constant ADMIN_ALLOWANCE = INITIAL_SUPPLY - TOKEN_SALE_ALLOWANCE;

    // Address of token administrator
    address public adminAddr;

    // Address of token sale contract
    address public tokenSaleAddr;

    // Enable transfer after token sale is completed
    bool public transferEnabled = false;
//SWC-108-State Variable Default Visibility:L29
    // Accounts to be locked for certain period
    mapping(address => uint256) private lockedAccounts;

    /*
     *
     * Permissions when transferEnabled is false :
     *              ContractOwner    Admin    SaleContract    Others
     * transfer            x           v            v           x
     * transferFrom        x           v            v           x
     *
     * Permissions when transferEnabled is true :
     *              ContractOwner    Admin    SaleContract    Others
     * transfer            v           v            v           v
     * transferFrom        v           v            v           v
     *
     */

    /*
     * Check if token transfer is allowed
     * Permission table above is result of this modifier
     */
    modifier onlyWhenTransferAllowed() {
        require(transferEnabled == true
            || msg.sender == adminAddr
            || msg.sender == tokenSaleAddr);
        _;
    }

    /*
     * Check if token sale address is not set
     */
    modifier onlyWhenTokenSaleAddrNotSet() {
        require(tokenSaleAddr == address(0x0));
        _;
    }

    /*
     * Check if token transfer destination is valid
     */
    modifier onlyValidDestination(address to) {
        require(to != address(0x0)
            && to != address(this)
            && to != owner
            && to != adminAddr
            && to != tokenSaleAddr);
        _;
    }

    modifier onlyAllowedAmount(address from, uint256 amount) {
        require(balances[from].sub(amount) >= lockedAccounts[from]);
        _;
    }
    /*
     * The constructor of Cloudbric contract
     *
     * @param _adminAddr: Address of token administrator
     */
    function Cloudbric(address _adminAddr) public {
        totalSupply_ = INITIAL_SUPPLY;

        balances[msg.sender] = totalSupply_;
        Transfer(address(0x0), msg.sender, totalSupply_);

        adminAddr = _adminAddr;
        approve(adminAddr, ADMIN_ALLOWANCE);
    }

    /*
     * Set amount of token sale to approve allowance for sale contract
     *
     * @param _tokenSaleAddr: Address of sale contract
     * @param _amountForSale: Amount of token for sale
     */
    function setTokenSaleAmount(address _tokenSaleAddr, uint256 amountForSale)
        external
        onlyOwner
        onlyWhenTokenSaleAddrNotSet
    {
        require(!transferEnabled);

        uint256 amount = (amountForSale == 0) ? TOKEN_SALE_ALLOWANCE : amountForSale;
        require(amount <= TOKEN_SALE_ALLOWANCE);

        approve(_tokenSaleAddr, amount);
        tokenSaleAddr = _tokenSaleAddr;
    }

    /*
     * Set transferEnabled variable to true
     */
    function enableTransfer() external onlyOwner {
        transferEnabled = true;
        approve(tokenSaleAddr, 0);
    }

    /*
     * Set transferEnabled variable to false
     */
    function disableTransfer() external onlyOwner {
        transferEnabled = false;
    }

    /*
     * Transfer token from message sender to another
     *
     * @param to: Destination address
     * @param value: Amount of AMO token to transfer
     */
    function transfer(address to, uint256 value)
        public
        onlyWhenTransferAllowed
        onlyValidDestination(to)
        onlyAllowedAmount(msg.sender, value)
        returns (bool)
    {
        return super.transfer(to, value);
    }

    /*
     * Transfer token from 'from' address to 'to' addreess
     *
     * @param from: Origin address
     * @param to: Destination address
     * @param value: Amount of tokens to transfer
     */
    function transferFrom(address from, address to, uint256 value)
        public
        onlyWhenTransferAllowed
        onlyValidDestination(to)
        onlyAllowedAmount(from, value)
        returns (bool)
    {
        return super.transferFrom(from, to, value);
    }

    /*
     * Burn token, only owner is allowed
     *
     * @param value: Amount of tokens to burn
     */
    function burn(uint256 value) public onlyOwner {
        require(transferEnabled);
        super.burn(value);
    }

    /*
     * Disable transfering tokens more than allowed amount from certain account
     *
     * @param addr: Account to set allowed amount
     * @param amount: Amount of tokens to allow
     */
    function lockAccount(address addr, uint256 amount)
        external
        onlyOwner
        onlyValidDestination(addr)
    {
        require(amount > 0);
        lockedAccounts[addr] = amount;
    }

    /*
     * Enable transfering tokens of locked account
     *
     * @param addr: Account to unlock
     */

    function unlockAccount(address addr)
        external
        onlyOwner
        onlyValidDestination(addr)
    {
        lockedAccounts[addr] = 0;
    }
}
