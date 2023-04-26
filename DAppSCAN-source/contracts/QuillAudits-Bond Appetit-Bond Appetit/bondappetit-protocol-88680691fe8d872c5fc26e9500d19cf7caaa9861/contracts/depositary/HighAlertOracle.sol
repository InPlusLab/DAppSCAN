// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../utils/OwnablePausable.sol";

contract HighAlertOracle is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Pausable list.
    EnumerableSet.AddressSet private contracts;

    /// @notice An event emitted when contract added to pausable list.
    event ContractAdded(address addedContract);

    /// @notice An event emitted when contract removed at pausable list.
    event ContractRemoved(address removedContract);

    /// @notice An event emitted when paused all contracts.
    event PausedAll(string reason);

    /// @notice An event emitted when unpaused all contracts.
    event UnpausedAll(string reason);

    /**
     * @notice Add contract to pausable list.
     * @param _contract Target contract.
     */
    function addContract(address _contract) external onlyOwner {
        contracts.add(_contract);
        emit ContractAdded(_contract);
    }

    /**
     * @notice Remove contract at pausable list.
     * @param _contract Target contract.
     */
    function removeContract(address _contract) external onlyOwner {
        contracts.add(_contract);
        emit ContractRemoved(_contract);
    }

    /**
     * @notice Return all pausable contracts.
     * @return Pausable contracts list.
     */
    function getContracts() external view returns (address[] memory) {
        address[] memory result;

        for (uint256 i = 0; i < contracts.length(); i++) {
            result[i] = contracts.at(i);
        }

        return result;
    }

    /**
     * @dev Pause all pausable contracts.
     * @param reason Reason of pause.
     */
    function _pauseAll(string memory reason) internal {
        for (uint256 i = 0; i < contracts.length(); i++) {
            OwnablePausable(contracts.at(i)).pause();
        }
        emit PausedAll(reason);
    }

    /**
     * @dev Unpause all pausable contracts.
     * @param reason Reason of unpause.
     */
    function _unpauseAll(string memory reason) internal {
        for (uint256 i = 0; i < contracts.length(); i++) {
            OwnablePausable(contracts.at(i)).unpause();
        }
        emit UnpausedAll(reason);
    }

    /**
     * @notice Pause all pausable contracts.
     * @param reason Reason of pause.
     */
    function pauseAll(string calldata reason) external onlyOwner {
        _pauseAll(reason);
    }

    /**
     * @notice Unpause all pausable contracts.
     * @param reason Reason of unpause.
     */
    function unpauseAll(string calldata reason) external onlyOwner {
        _unpauseAll(reason);
    }
}
