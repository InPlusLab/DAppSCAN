pragma solidity ^0.5.2;

import '../converter/interfaces/IDFEngine.sol';
import '../utility/DSAuth.sol';

contract DFUpgrader is DSAuth {

    // MEMBERS
    // @dev  The reference to the active converter implementation.
    IDFEngine public iDFEngine;

    /// @dev  The map of lock ids to pending implementation changes.
    address newDFEngine;

    // CONSTRUCTOR
    constructor () public {
        iDFEngine = IDFEngine(0x0);
    }

    // PUBLIC FUNCTIONS
    // (UPGRADE)
    /** @notice  Requests a change of the active implementation associated
      * with this contract.
      *
      * @dev  Anyone can call this function, but confirming the request is authorized
      * by the custodian.
      *
      * @param  _newDFEngine  The address of the new active implementation.
      */
    function requestImplChange(address _newDFEngine) public onlyOwner {
        require(_newDFEngine != address(0), "_newDFEngine: The address is empty");

        newDFEngine = _newDFEngine;

        emit ImplChangeRequested(msg.sender, _newDFEngine);
    }

    /** @notice  Confirms a pending change of the active implementation
      * associated with this contract.
      *
      * @dev  the `Converter ConverterImpl` member will be updated
      * with the requested address.
      *
      */
    function confirmImplChange() public onlyOwner {
        iDFEngine = IDFEngine(newDFEngine);

        emit ImplChangeConfirmed(address(iDFEngine));
    }

    /// @dev  Emitted by successful `requestImplChange` calls.
    event ImplChangeRequested(address indexed _msgSender, address indexed _proposedImpl);

    /// @dev Emitted by successful `confirmImplChange` calls.
    event ImplChangeConfirmed(address indexed _newImpl);
}