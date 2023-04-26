pragma solidity ^0.8.0;


interface ITest {
    function add(uint a, uint b) external;
}

contract Test is ITest {
    uint public a;
    uint public b;
    uint public sum;
    constructor(uint a, uint b){
        sum = a + b;
    }

    function add(uint a, uint b) external override {
        sum = a+b;
    }
}