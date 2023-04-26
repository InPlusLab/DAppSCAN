pragma solidity ^0.4.24;

import "../ProPool.sol";
import "../abstract/IPoolFactory.sol";
import "../zeppelin/NoEther.sol";
import "./Restricted.sol";


/**
 * @title PoolFactory 
 */
contract PoolFactory is IPoolFactory, HasNoEther, Restricted {

    /**
     * @dev Deploy new pool.
     */
    function deploy(
        uint maxBalance,
        uint minContribution,
        uint maxContribution,
        uint ctorFeePerEther,        
        address creatorAddress,
        address presaleAddress,        
        address feeServiceAddr,
        address[] whitelist,
        address[] admins
    ) 
        external
        onlyOperator
        returns (address poolAddress, uint poolVersion) 
    {
        ProPool pool = new ProPool(
            maxBalance,
            minContribution,
            maxContribution,
            ctorFeePerEther,
            whitelist.length > 0,
            creatorAddress,
            presaleAddress,        
            feeServiceAddr,
            whitelist,
            admins
        );
                
        poolAddress = address(pool);        
        poolVersion = pool.getLibVersion();
    }
}