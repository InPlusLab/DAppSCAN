pragma solidity ^0.4.24;

import "../abstract/IPoolRegistry.sol";
import "../zeppelin/NoEther.sol";
import "./Restricted.sol";


/**
 * @title PoolRegistry 
 */
contract PoolRegistry is IPoolRegistry, HasNoEther, Restricted {

    /**
     * @dev Register new pool.
     */
    function register(
        address creatorAddress,
        address poolAddress,
        uint poolVersion,
        uint details
    ) 
        external
        onlyOperator
    {
        require(
            creatorAddress != address(0) &&
            creatorAddress != poolAddress
        );        
        
        emit PoolRegistered(
            creatorAddress,
            poolVersion,
            details,
            poolAddress
        );
    }

    event PoolRegistered(
        address indexed creatorAddress,
        uint indexed poolVersion,
        uint indexed details,
        address poolAddress              
    );    
}