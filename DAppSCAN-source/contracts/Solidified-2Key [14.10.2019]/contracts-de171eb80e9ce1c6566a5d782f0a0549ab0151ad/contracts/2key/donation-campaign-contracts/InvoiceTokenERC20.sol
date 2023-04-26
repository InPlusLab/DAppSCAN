pragma solidity ^0.4.24;

import "./ERC20.sol";
import "../libraries/SafeMath.sol";

/**
 * @title Contract to handle ERC20 invoices
 * @author Nikola Madjarevic
 * Created at 2/22/19
 */
contract InvoiceTokenERC20 is ERC20 {

    using SafeMath for uint256;

    uint256 internal totalSupply_ = 10000000000000000000000000000;
    string public name;
    string public symbol;
    uint8 public decimals = 18;

    address public owner;


    mapping (address => mapping (address => uint256)) internal allowed;
    mapping(address => uint256) internal balances;


    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }


    constructor(string _name, string _symbol, address _tokensOwner) public {
        owner = _tokensOwner;
        name = _name;
        symbol = _symbol;
        balances[_tokensOwner] = totalSupply_;
    }

    /**
     * @dev Transfer tokens from one address to another
     * @param _from address The address which you want to send tokens from
     * @param _to address The address which you want to transfer to
     * @param _value uint256 the amount of tokens to be transferred
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
    public
    returns (bool)
    {
        revert();
    }

    /**
     * @dev approve is not supported regarding the specs
     * @param _value The amount of tokens to be spent.
     */
    function approve(address _spender, uint256 _value) public returns (bool) {
        revert();
    }

    /**
     * @dev Function to check the amount of tokens that an owner allowed to a spender.
     * @param _owner address The address which owns the funds.
     * @param _spender address The address which will spend the funds.
     * @return A uint256 specifying the amount of tokens still available for the spender.
     */
    function allowance(
        address _owner,
        address _spender
    )
    public
    view
    returns (uint256)
    {
        return allowed[_owner][_spender];
    }

    /**
     * @dev Total number of tokens in existence
     */
    function totalSupply() public view returns (uint256) {
        return totalSupply_;
    }

    /**
     * @dev Transfer token for a specified address
     * @param _to The address to transfer to.
     * @param _value The amount to be transferred.
     */
    function transfer(address _to, uint256 _value) public onlyOwner returns (bool) {
        require(_value <= balances[msg.sender]);
        require(_to != address(0));
        balances[msg.sender] = balances[msg.sender].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(msg.sender, _to, _value);
        return true;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _owner The address to query the the balance of.
     * @return An uint256 representing the amount owned by the passed address.
     */
    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

}
