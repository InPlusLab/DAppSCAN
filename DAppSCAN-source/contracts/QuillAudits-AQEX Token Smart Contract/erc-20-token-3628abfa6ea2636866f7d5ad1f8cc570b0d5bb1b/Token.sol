
// SPDX-License-Identifier: MIT
// SWC-103-Floating Pragma: L4
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)
pragma solidity ^0.8.0;
contract Ownable is Context {
    address private _owner;
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor() {
        _transferOwnership(_msgSender());
    }

    function owner() public view virtual returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

pragma solidity ^0.8.0;

contract TOKEN is Ownable{
   // specify `cap_supply`, declare `minter` and `supply`
    uint256 cap_supply = 500000000 ether ;
    uint256 supply = 100000000 ether;
    string symbol = "TST";
        address private minter;

        // burn tokens by updating senders's balance and total supply
        function burn(uint256 amount) public onlyOwner{
        require(balances[msg.sender] >= amount); // must have enough balance to burn
        supply -= amount;
        cap_supply -= amount;
        transfer(address(0), amount); // burn tokens by sending tokens to `address(0)`
        }

        // mint tokens by updating receiver's balance and total supply
        function mint(address receiver, uint256 amount) public onlyOwner  {
        require((amount + supply) <= cap_supply, "Cap Reached"); // total supply must not exceed `cap_supply` 
        balances[receiver] += amount;
        supply += amount;
        emit Transfer(msg.sender, receiver, amount);
        }

         // transfer of tokens
        function transfer(address _to, uint256 _value) public {
        require((_value) <= balances[msg.sender]); // NOTE: sender needs to have enough tokens
        if(_to == address(0)){
            balances[_to] += _value;
            balances[msg.sender] -= _value;
            emit Transfer(msg.sender, address(0), _value);
        }
        else{balances[_to] += _value; // transfer `_value` tokens from sender to `_to`
        balances[msg.sender] -= (_value); // NOTE: transfer value needs to be sufficient to cover fee
        emit Transfer(msg.sender, _to, _value);
        }
    }

    
    // event to be emitted on transfer 
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    
    // event to be emitted on approval
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
    
    // create mapping for balances
    mapping(address => uint256) public balances;
    
    // create mapping for allowances
    mapping(address => mapping(address => uint)) public allowances;
    
    // return the balance of _owner 
    function balanceOf(address _owner) public view returns (uint256) {return balances[_owner];}

    function allowance(address _owner, address _spender) public view returns (uint256 remaining)
        {remaining = allowances[_owner][_spender]; 
        require(remaining <= balances[_owner]);
        return remaining;} // return how much `_spender` is allowed to spend on behalf of `_owner` 
    
    // if an allowance already exists, it should be overwritten
    function approve(address _spender, uint256 _value) public {
        allowances[msg.sender][_spender] = _value; // allow `_spender` to spend `_value` on sender's behalf 
        require(balances[msg.sender] >= _value);
        emit Approval(msg.sender, _spender, _value);
        }
        
    constructor(){balances[msg.sender] = supply; minter = msg.sender;} // sender's balance = total supply, sender is minter
    
    function totalSupply() public view returns (uint256) {return supply;} //return total supply
   
}
