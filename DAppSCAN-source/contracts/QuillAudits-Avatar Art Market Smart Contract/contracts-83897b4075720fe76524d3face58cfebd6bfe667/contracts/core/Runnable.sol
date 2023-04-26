// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";

abstract contract Runnable is Ownable {
    
    modifier isRunning{
        require(_isRunning, "Contract is paused");
        _;
    }
    
    bool internal _isRunning;
    
    constructor(){
        _isRunning = true;
    }
    
    function toggleRunningStatus() external onlyOwner{
        _isRunning = !_isRunning;
    }

    function getRunningStatus() external view returns(bool){
        return _isRunning;
    }
}