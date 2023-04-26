pragma solidity ^0.4.24;


/**
 * @title PoolFactory Interface 
 */
contract IPoolFactory {
    function deploy
    (
        uint maxBalance,
        uint minContribution,
        uint maxContribution,
        uint ctorFeePerEther,        
        address creatorAddress,
        address presaleAddress,
        address feeManagerAddr,
        address[] whitelist,
        address[] adminis
    )
        external
        returns (address poolAddress, uint poolVersion);
}