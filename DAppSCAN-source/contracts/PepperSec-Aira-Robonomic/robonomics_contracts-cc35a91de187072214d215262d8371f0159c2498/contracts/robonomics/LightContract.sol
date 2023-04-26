pragma solidity ^0.4.24;

contract LightContract {
    /**
     * @dev Shared code smart contract 
     */
    address lib;

    constructor(address _library) public {
        lib = _library;
    }

    function() public {
        require(lib.delegatecall(msg.data));
    }
}
