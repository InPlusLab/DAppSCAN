pragma solidity ^0.4.24;


/**
 * @title FeeService Interface 
 */
contract IFeeService {
    function getFeePerEther() public view returns(uint);
    function sendFee(address feePayer) external payable;
}