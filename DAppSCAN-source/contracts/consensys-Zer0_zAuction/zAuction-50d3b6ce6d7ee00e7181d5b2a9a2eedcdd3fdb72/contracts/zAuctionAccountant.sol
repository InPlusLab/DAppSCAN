// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./oz/util/SafeMath.sol";

contract zAuctionAccountant {
    address public zauction;
    address public admin;
    mapping(address => uint256) public ethbalance;

    event Deposited(address indexed depositer, uint256 amount);
    event Withdrew(address indexed withrawer, uint256 amount);
    event zDeposited(address indexed depositer, uint256 amount);
    event zWithdrew(address indexed withrawer, uint256 amount);
    event zExchanged(address indexed from, address indexed to, uint256 amount);
    event ZauctionSet(address);
    event AdminSet(address, address);
    
    constructor(){
        admin = msg.sender;
    }

    modifier onlyZauction(){
        require(msg.sender == zauction, 'zAuctionAccountant: sender is not zauction contract');
        _;
    }
    modifier onlyAdmin(){
        require(msg.sender == admin, 'zAuctionAccountant: sender is not admin');
        _;
    }
    
    function Deposit() external payable {
        ethbalance[msg.sender] = SafeMath.add(ethbalance[msg.sender], msg.value);
        emit Deposited(msg.sender, msg.value);
    }

    function Withdraw(uint256 amount) external {
        ethbalance[msg.sender] = SafeMath.sub(ethbalance[msg.sender], amount);
        payable(msg.sender).transfer(amount);
        emit Withdrew(msg.sender, amount);
    }
    // SWC-135-Code With No Effects: L44-52
    function zDeposit(address to) external payable onlyZauction {
        ethbalance[to] = SafeMath.add(ethbalance[to], msg.value);
        emit zDeposited(to, msg.value);
    }

    function zWithdraw(address from, uint256 amount) external onlyZauction {
        ethbalance[from] = SafeMath.sub(ethbalance[from], amount);
        emit zWithdrew(from, amount);
    }

    function Exchange(address from, address to, uint256 amount) external onlyZauction {
        ethbalance[from] = SafeMath.sub(ethbalance[from], amount);
        ethbalance[to] = SafeMath.add(ethbalance[to], amount);
        emit zExchanged(from, to, amount);
    } 
    // SWC-114-Transaction Order Dependence: L60-68
    function SetZauction(address zauctionaddress) external onlyAdmin{
        zauction = zauctionaddress;
        emit ZauctionSet(zauctionaddress);
    }

    function SetAdmin(address newadmin) external onlyAdmin{
        admin = newadmin;
        emit AdminSet(msg.sender, newadmin);
    }
}