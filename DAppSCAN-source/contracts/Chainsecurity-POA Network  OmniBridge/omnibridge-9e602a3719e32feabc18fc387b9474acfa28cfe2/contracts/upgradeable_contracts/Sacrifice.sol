pragma solidity 0.7.5;

contract Sacrifice {
    constructor(address payable _recipient) payable {
        selfdestruct(_recipient);
    }
}
