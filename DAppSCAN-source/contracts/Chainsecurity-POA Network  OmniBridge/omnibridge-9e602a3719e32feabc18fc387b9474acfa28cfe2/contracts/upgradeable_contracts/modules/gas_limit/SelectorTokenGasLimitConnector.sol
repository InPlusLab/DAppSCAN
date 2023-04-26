pragma solidity 0.7.5;

import "../../Ownable.sol";
import "./SelectorTokenGasLimitManager.sol";
import "../../BasicAMBMediator.sol";

/**
 * @title SelectorTokenGasLimitConnector
 * @dev Connectivity functionality that is required for using gas limit manager.
 */
abstract contract SelectorTokenGasLimitConnector is Ownable, BasicAMBMediator {
    bytes32 internal constant GAS_LIMIT_MANAGER_CONTRACT =
        0x5f5bc4e0b888be22a35f2166061a04607296c26861006b9b8e089a172696a822; // keccak256(abi.encodePacked("gasLimitManagerContract"))

    /**
     * @dev Updates an address of the used gas limit manager contract.
     * @param _manager address of gas limit manager contract.
     */
    function setGasLimitManager(address _manager) external onlyOwner {
        _setGasLimitManager(_manager);
    }

    /**
     * @dev Retrieves an address of the gas limit manager contract.
     * @return address of the gas limit manager contract.
     */
    function gasLimitManager() public view returns (SelectorTokenGasLimitManager) {
        return SelectorTokenGasLimitManager(addressStorage[GAS_LIMIT_MANAGER_CONTRACT]);
    }

    /**
     * @dev Internal function for updating an address of the used gas limit manager contract.
     * @param _manager address of gas limit manager contract.
     */
    function _setGasLimitManager(address _manager) internal {
        require(_manager == address(0) || Address.isContract(_manager));
        addressStorage[GAS_LIMIT_MANAGER_CONTRACT] = _manager;
    }

    /**
     * @dev Tells the gas limit to use for the message execution by the AMB bridge on the other network.
     * @param _data calldata to be used on the other side of the bridge, when execution a message.
     * @return the gas limit for the message execution.
     */
    function _chooseRequestGasLimit(bytes memory _data) internal view returns (uint256) {
        SelectorTokenGasLimitManager manager = gasLimitManager();
        if (address(manager) == address(0)) {
            return bridgeContract().maxGasPerTx();
        } else {
            return manager.requestGasLimit(_data);
        }
    }
}
