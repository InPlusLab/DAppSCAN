// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.7;

contract ERC20TrueReturner {

    function transfer(address to, uint256 value) external pure returns (bool) {
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external pure returns (bool) {
        return true;
    }
    
    function approve(address to, uint256 value) external pure returns (bool) {
        return true;
    }

}

contract ERC20FalseReturner {

    function transfer(address to, uint256 value) external pure returns (bool) {
        return false;
    }

    function transferFrom(address from, address to, uint256 value) external pure returns (bool) {
        return false;
    }
    
    function approve(address to, uint256 value) external pure returns (bool) {
        return false;
    }

}

contract ERC20NoReturner {

    function transfer(address to, uint256 value) external {}

    function transferFrom(address from, address to, uint256 value) external {}
    
    function approve(address to, uint256 value) external {}

}

contract ERC20Reverter {

    function transfer(address to, uint256 value) external pure returns (bool) {
        require(false);
    }

    function transferFrom(address from, address to, uint256 value) external pure returns (bool) {
        require(false);
    }
    
    function approve(address to, uint256 value) external pure returns (bool) {
        require(false);
    }

}
