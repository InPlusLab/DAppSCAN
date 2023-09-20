/*

  Contract to implement Rouge ERC20 tokens for the Rouge Project.
  They are based on StandardToken from (https://github.com/ConsenSys/Tokens).

*/
//SWC-101-Integer Overflow and Underflow:all contract
import "./EIP20.sol";

pragma solidity ^0.4.18;

contract RGEToken is EIP20 {
    
    /* ERC20 */
    string public name = 'Rouge';
    string public symbol = 'RGE';
    uint8 public decimals = 6;
    
    /* RGEToken */
    address owner; 
    address public crowdsale;
    uint public endTGE;
    string public version = 'v0.2';
    uint256 public totalSupply = 1000000000 * 10**6;
    uint256 public   reserveY1 =  300000000 * 10**6;
    uint256 public   reserveY2 =  200000000 * 10**6;

    modifier onlyBy(address _account) {
        require(msg.sender == _account);
        _;
    }
    
    function RGEToken (uint _endTGE) EIP20 (totalSupply, name, decimals, symbol) public {
        owner = msg.sender;
        endTGE = _endTGE;
        crowdsale = address(0);
    }
//    SWC-101-Integer Overflow and Underflow:L43,69,79,80
    function startCrowdsaleY0(address _crowdsale) onlyBy(owner) public {
        require(crowdsale == address(0));
        require(now < endTGE);
        crowdsale = _crowdsale;
        balances[crowdsale] = totalSupply - reserveY1 - reserveY2;
        Transfer(address(0), crowdsale, balances[crowdsale]);
    }

    function startCrowdsaleY1(address _crowdsale) onlyBy(owner) public {
        require(crowdsale == address(0));
        require(reserveY1 > 0);
        require(now >= endTGE + 31536000); /* Y+1 crowdsale can only start after a year */
        crowdsale = _crowdsale;
        balances[crowdsale] = reserveY1;
        Transfer(address(0), crowdsale, reserveY1);
        reserveY1 = 0;
    }

    function startCrowdsaleY2(address _crowdsale) onlyBy(owner) public {
        require(crowdsale == address(0));
        require(reserveY2 > 0);
        require(now >= endTGE + 63072000); /* Y+2 crowdsale can only start after 2 years */
        crowdsale = _crowdsale;
        balances[crowdsale] = reserveY2;
        Transfer(address(0), crowdsale, reserveY2);
        reserveY2 = 0;
    }

    // later than end of TGE to let people withdraw (put a max?)
    function endCrowdsale(uint256 _unsold) onlyBy(crowdsale) public {
        reserveY2 += _unsold;
        Transfer(crowdsale, address(0), _unsold);
        crowdsale = address(0);
    }

    event Burn(address indexed burner, uint256 value);

    function burn(uint256 _value) public returns (bool success) {
        require(_value > 0);
        require(balances[msg.sender] >= _value);
        balances[msg.sender] -= _value;
        totalSupply -= _value;
        Transfer(msg.sender, address(0), _value);
        Burn(msg.sender, _value);
        return true;
    }

}
