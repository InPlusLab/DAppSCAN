pragma solidity 0.7.5;

import "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title OwnableModule
 * @dev Common functionality for multi-token extension non-upgradeable module.
 */
contract OwnableModule {
    address public owner;

    /**
     * @dev Initializes this contract.
     * @param _owner address of the owner that is allowed to perform additional actions on the particular module.
     */
    constructor(address _owner) {
        owner = _owner;
    }

    /**
     * @dev Throws if sender is not the owner of this contract.
     */
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev Changes the owner of this contract.
     * @param _newOwner address of the new owner.
     */
    function transferOwnership(address _newOwner) external onlyOwner {
        owner = _newOwner;
    }
}
