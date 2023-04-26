pragma solidity 0.5.13;

import "@openzeppelin/contracts/math/SafeMath.sol";

// this is only for ganache testing. Public chain deployments will use the existing dai contract. 

contract CashMockup

{

    using SafeMath for uint256;

    mapping (address => uint256) public balances;
    mapping (address => mapping (address => uint256 ) ) public allowances;

    function approve(address _spender, uint256 _amount) external returns (bool)
    {
        allowances[_spender][msg.sender] = _amount;
        return true;
    }

    function balanceOf(address _owner) public view returns (uint256)
    {
        return balances[_owner];
    }

    function faucet(uint256 _amount) external
    {
        balances[msg.sender] = balances[msg.sender].add(_amount);
    }

    function transfer(address _to, uint256 _amount) external returns (bool)
    {   
        require (balances[msg.sender] >= _amount, "Insufficient balance");
        balances[msg.sender] = balances[msg.sender].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _amount) external returns (bool)
    {
        require (allowances[msg.sender][_from] >= _amount, "Insufficient approval");
        require (balances[_from] >= _amount, "Insufficient balance");
        balances[_from] = balances[_from].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        return true;
    }

    function transferFromNoApproval(address _from, address _to, uint256 _amount) external returns (bool)
    {
        require (balances[_from] >= _amount, "Insufficient balance");
        balances[_from] = balances[_from].sub(_amount);
        balances[_to] = balances[_to].add(_amount);
        return true;
    }

    function resetBalance(address _victim) external returns (bool)
    {   
        balances[_victim] = 0;
    }

}