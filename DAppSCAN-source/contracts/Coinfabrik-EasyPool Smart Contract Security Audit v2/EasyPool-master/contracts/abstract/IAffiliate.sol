pragma solidity ^0.4.24;


/**
 * @title Affiliate Interface 
 */
contract IAffiliate {
    function getSharePerEther(address subscriber) external view returns(uint sharePerEther, bool success);
    function sendRevenueShare(address subscriber) external payable;
}