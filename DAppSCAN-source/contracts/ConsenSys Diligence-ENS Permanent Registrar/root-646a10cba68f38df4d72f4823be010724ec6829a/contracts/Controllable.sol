pragma solidity ^0.5.0;

import "./Ownable.sol";

contract Controllable is Ownable {
    mapping(address=>bool) public controllers;

    modifier onlyController {
        require(controllers[msg.sender]);
        _;
    }

    function setController(address controller, bool enabled) public onlyOwner {
        controllers[controller] = enabled;
    }
}
