// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract OwnablePausable is Ownable, Pausable {
    /// @notice Address that can pause a contract.
    address public pauser;

    /// @notice An event thats emitted when an pauser address changed.
    event PauserChanged(address newPauser);

    constructor() internal {
        pauser = owner();
    }

    /**
     * @notice Change pauser account.
     * @param newPauser Address of new pauser account.
     */
    function changePauser(address newPauser) external onlyOwner {
        pauser = newPauser;
        emit PauserChanged(pauser);
    }

    /**
     * @notice Triggers stopped state.
     */
    function pause() public virtual {
        require(pauser == _msgSender() || owner() == _msgSender(), "OwnablePausable::pause: only pauser and owner must pause contract");
        _pause();
    }

    /**
     * @notice Returns to normal state.
     */
    function unpause() public virtual {
        require(pauser == _msgSender() || owner() == _msgSender(), "OwnablePausable::unpause: only pauser and owner must unpause contract");
        _unpause();
    }
}
