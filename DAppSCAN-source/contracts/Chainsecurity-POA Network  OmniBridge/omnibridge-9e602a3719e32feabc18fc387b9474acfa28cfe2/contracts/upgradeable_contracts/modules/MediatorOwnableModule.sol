pragma solidity 0.7.5;

import "@openzeppelin/contracts/utils/Address.sol";
import "./OwnableModule.sol";

/**
 * @title MediatorOwnableModule
 * @dev Common functionality for non-upgradeable Omnibridge extension module.
 */
contract MediatorOwnableModule is OwnableModule {
    address public mediator;

    /**
     * @dev Initializes this contract.
     * @param _mediator address of the deployed Omnibridge extension for which this module is deployed.
     * @param _owner address of the owner that is allowed to perform additional actions on the particular module.
     */
    constructor(address _mediator, address _owner) OwnableModule(_owner) {
        require(Address.isContract(_mediator));
        mediator = _mediator;
    }

    /**
     * @dev Throws if sender is not the Omnibridge extension.
     */
    modifier onlyMediator {
        require(msg.sender == mediator);
        _;
    }
}
