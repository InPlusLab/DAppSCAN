// SPDX-License-Identifier: MIT
/// @dev size: 1.943 Kbytes
pragma solidity 0.8.4;

import "./Vesting.sol";
import "../proxy/Clones.sol";
import "../security/Ownable.sol";
import "../utils/NonZeroAddressGuard.sol";

/// @title Vesting instance factory
/// @notice Create vesting schedule instance contract for an organization
contract VestingFactory is Ownable, NonZeroAddressGuard {
    struct Instance {
        address instanceAddr;
        address owner;
        address tokenAddr;
    }

    Instance[] public instances;
    address public libraryAddress;

    event InstanceCreated(address indexed instance, address owner, address token);
    event LibraryChanged(address oldLibrary, address newLibrary);

    /**
     * @notice Contract constructor
     * @dev Prior to deployment you must deploy one copy of `Vesting` which
     * is used as a library for vesting contracts deployed by this factory
     * @param _libraryAddress `Vesting` contract address
    */
    constructor(address _libraryAddress) {
        require(_libraryAddress != address(0), "Library address cannot be 0");

        libraryAddress = _libraryAddress;
    }

    /**
     * @notice Update the `Vesting` library address
     * @dev Only the owner can update the library address
     * @param _libraryAddress `Vesting` contract address
     */
    function setLibraryAddress(address _libraryAddress) external onlyOwner {
        address currentLibrary = libraryAddress;
        require(_libraryAddress != address(0), "Library address cannot be 0");
        require(_libraryAddress != currentLibrary, "Library address cannot be the same as the current one");

        libraryAddress = _libraryAddress;
        emit LibraryChanged(currentLibrary, libraryAddress);
    }

    /** 
     * @notice Deploy a new vesting contract
     * @param _token Address of the ERC20 token being distributed
    */
    function createVestingContract(IERC20 _token) external virtual nonZeroAddress(address(_token)) {
        address _contract = Clones.createClone(libraryAddress);

        Vesting(_contract).initialize(msg.sender, _token);
        instances.push(Instance(_contract, msg.sender, address(_token)));

        emit InstanceCreated(_contract, msg.sender, address(_token));
    }

    function getBlockTimestamp() public virtual view returns (uint256) {
        return block.timestamp;
    }
}