// SWC-102-Outdated Compiler Version: L3
// SWC-103-Floating Pragma: L3
pragma solidity ^0.4.18;

   /**
    * @title SafeMath
    * @dev Math operations with safety checks that throw on error
    */
 
 
library SafeMath {

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a * b;

        assert(a == 0 || c / a == b);

        return c;
    }


    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity automatically throws when dividing by 0
        uint256 c = a / b;

        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return c;
    }


    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);

        return a - b;
    }


    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;

        assert(c >= a);

        return c;
    }
}

   /**
    * @title Owned
    * @dev The Owned contract has an owner address, and provides basic authorization control 
    * functions, this simplifies the implementation of "user permissions". 
    */
 
 
contract Owned {

  address public owner;
  address public newOwner;

  // Events ---------------------------

  event OwnershipTransferProposed(address indexed _from, address indexed _to);
  event OwnershipTransferred(address indexed _from, address indexed _to);

  // Modifier -------------------------

  modifier onlyOwner {
    require( msg.sender == owner );
    _;
  }

  // Functions ------------------------

  function Owned() public {
    owner = msg.sender;
  }

  function transferOwnership(address _newOwner) public onlyOwner {
    require( _newOwner != owner );
    require( _newOwner != address(0x0) );
    OwnershipTransferProposed(owner, _newOwner);
    newOwner = _newOwner;
  }

  function acceptOwnership() public {
    require(msg.sender == newOwner);
    OwnershipTransferred(owner, newOwner);
    owner = newOwner;
  }

}

/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Owned {
  event Pause();
  event Unpause();

  bool public paused = false;


  /**
   * @dev Modifier to make a function callable only when the contract is not paused.
   */
  modifier whenNotPaused() {
    require(!paused);
    _;
  }

  /**
   * @dev Modifier to make a function callable only when the contract is paused.
   */
  modifier whenPaused() {
    require(paused);
    _;
  }

  /**
   * @dev called by the owner to pause, triggers stopped state
   */
  function pause() onlyOwner whenNotPaused public {
    paused = true;
    Pause();
  }

  /**
   * @dev called by the owner to unpause, returns to normal state
   */
  function unpause() onlyOwner whenPaused public {
    paused = false;
    Unpause();
  }
}



   /**
    * @title ERC20 Interface
    * @dev Simpler version of ERC20 interface
    * @dev see https://github.com/ethereum/EIPs/issues/20
    */
 
 
contract ERC20Interface {

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    function totalSupply() public view returns (uint256);

    function balanceOf(address _owner) public view returns (uint256 balance);
    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    function transfer(address _to, uint256 _value) public returns (bool success);
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);
    function approve(address _spender, uint256 _value) public returns (bool success);
}

   /**
    * @title Basic token
    * @dev Basic version of StandardToken, with no allowances.
    */
 
 
contract BasicToken is ERC20Interface, Owned {
  using SafeMath for uint256;
  
  string public constant name     = "Bitpara TRY";
  string public constant symbol   = "BTRY";
  uint8  public constant decimals = 6;
  uint256 public tokensIssuedTotal = 0;
  uint256 public fee = 0;

  mapping(address => uint256) balances;

    // fee can't be higher than 10 bucks
    function changeFee(uint256 _fee) onlyOwner public {
    require(_fee <= 10000000);
    fee = _fee;
  }

   /**
    * @dev transfer token for a specified address
    * @param _to The address to transfer to.
    * @param _value The amount to be transferred.
    */
    
    
  function transfer(address _to, uint256 _value) public returns (bool) {
    require(_to != address(0));

    // SafeMath.sub will throw if there is not enough balance.
    balances[msg.sender] = balances[msg.sender].sub(_value);
    uint256 netbakiye = _value.sub(fee);
    balances[_to] = balances[_to].add(netbakiye);
    Transfer(msg.sender, _to, netbakiye);
    if (fee > 0) {
    balances[owner] = balances[owner].add(fee);
    Transfer(msg.sender, owner, fee);
    }
    return true;
  }

  function totalSupply() public view returns (uint256) {
    return tokensIssuedTotal;
  }
  
   /**
    * @dev Gets the balance of the specified address.
    * @param _owner The address to query the the balance of.
    * @return An uint256 representing the amount owned by the passed address.
    */
  
  
  function balanceOf(address _owner) public view returns (uint256 balance) {
    return balances[_owner];
  }
 }
 

   /**
    * @title Standard ERC20 token
    *
    * @dev Implementation of the basic standard token.
    * @dev https://github.com/ethereum/EIPs/issues/20
    * @dev Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
    */
    
    
contract StandardToken is BasicToken {
 
 
  mapping (address => mapping (address => uint256)) internal allowed;


   /**
    * @dev Transfer tokens from one address to another
    * @param _from address The address which you want to send tokens from
    * @param _to address The address which you want to transfer to
    * @param _value uint the amount of tokens to be transferred
    */
    
   
  function transferFrom(address _from, address _to, uint256 _value) public returns (bool) {
    require(_to != address(0));

    balances[_from] = balances[_from].sub(_value);
    uint256 netbakiye = _value.sub(fee);
    balances[_to] = balances[_to].add(netbakiye);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    Transfer(_from, _to, netbakiye);
    if (fee > 0) {
    balances[owner] = balances[owner].add(fee);
    Transfer(_from, owner, fee);
    }
    return true;
  }

   /**
    * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
    *
    * Beware that changing an allowance with this method brings the risk that someone may use both the old
    * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
    * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
    * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    * @param _spender The address which will spend the funds.
    * @param _value The amount of tokens to be spent.
    */
   
  function approve(address _spender, uint256 _value) public returns (bool) {
    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

   /**
    * @dev Function to check the amount of tokens that an owner allowed to a spender.
    * @param _owner address The address which owns the funds.
    * @param _spender address The address which will spend the funds.
    * @return A uint256 specifying the amount of tokens still available for the spender.
    */

  function allowance(address _owner, address _spender) public view returns (uint256 remaining) {
    return allowed[_owner][_spender];
  }

}


contract BanList is Owned, StandardToken {

    function getBanStatus(address _unclear) external view returns (bool) {
        return checkBan[_unclear];
    }

    function getOwner() external view returns (address) {
        return owner;
    }

    mapping (address => bool) public checkBan;
    
    function addBanList (address _banned) onlyOwner public {
        checkBan[_banned] = true;
        addedBanList(_banned);
    }

    function deletefromBanList (address _unban) onlyOwner public {
        checkBan[_unban] = false;
        deletedfromBanList(_unban);
    }

    function burnBannedUserBalance (address _bannedUser) onlyOwner public {
        require(checkBan[_bannedUser]);
        uint BannedUserBalance = balanceOf(_bannedUser);
        balances[_bannedUser] = 0;
        tokensIssuedTotal = tokensIssuedTotal.sub(BannedUserBalance);
        burnedBannedUserBalance(_bannedUser, BannedUserBalance);
    }

    event burnedBannedUserBalance(address _bannedUser, uint _balance);

    event addedBanList(address _user);

    event deletedfromBanList(address _user);

}

 
 contract PausableToken is BanList, Pausable {

  function transfer(address _to, uint256 _value) public whenNotPaused returns (bool) {
    require(!checkBan[msg.sender]);
    return super.transfer(_to, _value);
  }

  function transferFrom(address _from, address _to, uint256 _value) public whenNotPaused returns (bool) {
    require(!checkBan[_from]);
    return super.transferFrom(_from, _to, _value);
  }

  function approve(address _spender, uint256 _value) public whenNotPaused returns (bool) {
    return super.approve(_spender, _value);
  }

}

   /**
    * @title Mintable token
    * @dev Simple ERC20 Token example, with mintable token creation
    * @dev Issue: * https://github.com/OpenZeppelin/zeppelin-solidity/issues/120
    * Based on code by TokenMarketNet: https://github.com/TokenMarketNet/ico/blob/master/contracts/MintableToken.sol
    */

contract MintableToken is PausableToken {
   event Mint(address indexed owner, uint _amount);

  /**
   * @dev Function to mint tokens
   * @return A boolean that indicates if the operation was successful.
   */
   
   
  function mint(uint256 _amount) onlyOwner public returns (bool) {
    tokensIssuedTotal = tokensIssuedTotal.add(_amount);
    balances[owner] = balances[owner].add(_amount);
    Mint(owner, _amount);
    Transfer(0, owner, _amount);
    return true;
  }
  
}

   /**
    * @title Burnable Token
    * @dev Token that can be irreversibly burned (destroyed).
    */
 
 
contract BurnableToken is MintableToken {

    event Burn(address indexed owner, uint256 _value);
    
    /**
     * @dev Burns a specific amount of tokens.
     * @param _value The amount of token to be burned.
     */
     
    function burn(uint256 _value) onlyOwner public returns (bool) {
        require(_value > 0);
        balances[owner] = balances[owner].sub(_value);
        tokensIssuedTotal = tokensIssuedTotal.sub(_value);
        Burn(owner, _value);
        return true;
    }
}

contract Bitpara is BurnableToken {

    /**
     * @dev It will transfer to owner a specific amount of tokens.
     * @param _value The amount of token to be transferred.
     */

  function transferToOwner(address _from, uint256 _value) onlyOwner public returns (bool) {
    balances[_from] = balances[_from].sub(_value);
    balances[owner] = balances[owner].add(_value);
    Transfer(_from, owner, _value);
    return true;
  }
}
