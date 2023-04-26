pragma solidity ^0.4.24;

import "../abstract/IPoolRegistry.sol";
import "../abstract/IPoolFactory.sol";
import "../zeppelin/Pausable.sol";
import "../zeppelin/NoEther.sol";


/**
* @title Contracts Manager Service
*/
contract CMService is Pausable, HasNoEther {     

    address public feeService;      
    IPoolFactory public poolFactory;
    IPoolRegistry public poolRegistry;    

    /**
     * @dev Deploy new pool contract.
     */
    function deployPoolContract(
        uint details,
        uint maxBalance,
        uint minContribution,
        uint maxContribution,
        uint ctorFeePerEther,
        address presaleAddr,
        address[] whitelist,
        address[] admins
    ) 
        external 
        whenNotPaused
    {
        require(feeService != address(0));
        uint dts = details;

        uint poolVersion;
        address poolAddress;        
        (poolAddress, poolVersion) = poolFactory.deploy(
            maxBalance,
            minContribution,
            maxContribution,
            ctorFeePerEther,            
            msg.sender,
            presaleAddr,
            feeService,
            whitelist,
            admins
        );     

        poolRegistry.register(
            msg.sender,
            poolAddress,
            poolVersion,
            dts
        );
    }

    /**
     * @dev Set new fee service.
     */
    function setFeeService(address newFeeService) external onlyOwner {
        emit FeeServiceAttached(newFeeService);
        feeService = newFeeService;        
    }

    /**
     * @dev Set new pool factory.
     */
    function setPoolFactory(address newPoolFactory) external onlyOwner {
        emit PoolFactoryAttached(newPoolFactory);
        poolFactory = IPoolFactory(newPoolFactory);        
    }

    /**
     * @dev Set new pool registry.
     */
    function setPoolRegistry(address newPoolRegistry) external onlyOwner {
        emit PoolRegistryAttached(newPoolRegistry);
        poolRegistry = IPoolRegistry(newPoolRegistry);        
    }

    event FeeServiceAttached(address newFeeService);
    event PoolFactoryAttached(address newPoolFactory);
    event PoolRegistryAttached(address newPoolRegistry);       
}