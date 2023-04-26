pragma solidity ^0.4.24;

import "../project/ProjectWallet.sol";

contract MockProjectWallet {

    uint public called = 0;
    address sender;
    address receiver;
    uint256 amt;

    constructor(address _sender, address _receiver, uint256 _amt) public {
        sender = _sender;
        receiver = _receiver;
        amt = _amt;
    }

    function transfer(address _sender, address _receiver, uint256 _amt) public returns (bool)
    {
        require(sender == _sender, "sender mismatch");
        require(receiver == _receiver, "receiver mismatch");
        require(amt == _amt, "amt mismatch");
        called = called + 1;
        return true;
    }

}


