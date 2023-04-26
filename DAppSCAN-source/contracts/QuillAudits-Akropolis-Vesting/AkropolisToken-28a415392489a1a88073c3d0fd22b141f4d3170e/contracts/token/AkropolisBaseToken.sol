pragma solidity >=0.4.24;

import "./dataStorage/TokenStorage.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/AddressUtils.sol";
import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "../helpers/Ownable.sol";

/**
* @title AkropolisBaseToken
* @notice A basic ERC20 token with modular data storage
*/
contract AkropolisBaseToken is ERC20, TokenStorage, Ownable {
    using SafeMath for uint256;

    /** Events */
    event Mint(address indexed to, uint256 value);
    event Burn(address indexed burner, uint256 value);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);


    constructor (address _balances, address _allowances, string _name, uint8 _decimals, string _symbol) public 
    TokenStorage(_balances, _allowances, _name, _decimals, _symbol) {}

    /** Modifiers **/

    /** Functions **/

    function mint(address _to, uint256 _amount) public onlyOwner {
        return _mint(_to, _amount);
    }

    function burn(uint256 _amount) public {
        _burn(msg.sender, _amount);
    }

    function approve(address _spender, uint256 _value) 
    public returns (bool) {
        allowances.setAllowance(msg.sender, _spender, _value);
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    function transfer(address _to, uint256 _amount) public returns (bool) {
        require(_to != address(0),"to address cannot be 0x0");
        require(_amount <= balanceOf(msg.sender),"not enough balance to transfer");

        balances.subBalance(msg.sender, _amount);
        balances.addBalance(_to, _amount);
        emit Transfer(msg.sender, _to, _amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) 
    public returns (bool) {
        require(_amount <= allowance(_from, msg.sender),"not enough allowance to transfer");
        require(_to != address(0),"to address cannot be 0x0");
        require(_amount <= balanceOf(_from),"not enough balance to transfer");
        
        allowances.subAllowance(_from, msg.sender, _amount);
        balances.addBalance(_to, _amount);
        balances.subBalance(_from, _amount);
        emit Transfer(_from, _to, _amount);
        return true;
    }

    /**
    * @notice Implements balanceOf() as specified in the ERC20 standard.
    */
    function balanceOf(address who) public view returns (uint256) {
        return balances.balanceOf(who);
    }

    /**
    * @notice Implements allowance() as specified in the ERC20 standard.
    */
    function allowance(address owner, address spender) public view returns (uint256) {
        return allowances.allowanceOf(owner, spender);
    }

    /**
    * @notice Implements totalSupply() as specified in the ERC20 standard.
    */
    function totalSupply() public view returns (uint256) {
        return balances.totalSupply();
    }


    /** Internal functions **/

    function _burn(address _tokensOf, uint256 _amount) internal {
        require(_amount <= balanceOf(_tokensOf),"not enough balance to burn");
        // no need to require value <= totalSupply, since that would imply the
        // sender's balance is greater than the totalSupply, which *should* be an assertion failure
        balances.subBalance(_tokensOf, _amount);
        balances.subTotalSupply(_amount);
        emit Burn(_tokensOf, _amount);
        emit Transfer(_tokensOf, address(0), _amount);
    }

    function _mint(address _to, uint256 _amount) internal {
        balances.addTotalSupply(_amount);
        balances.addBalance(_to, _amount);
        emit Mint(_to, _amount);
        emit Transfer(address(0), _to, _amount);
    }

}