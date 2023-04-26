pragma solidity 0.7.5;

import "../upgradeability/EternalStorage.sol";
import "../interfaces/IUpgradeabilityOwnerStorage.sol";

/**
 * @title Ownable
 * @dev This contract has an owner address providing basic authorization control
 */
contract Ownable is EternalStorage {
    bytes4 internal constant UPGRADEABILITY_OWNER = 0x6fde8202; // upgradeabilityOwner()

    /**
     * @dev Event to show ownership has been transferred
     * @param previousOwner representing the address of the previous owner
     * @param newOwner representing the address of the new owner
     */
    event OwnershipTransferred(address previousOwner, address newOwner);

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _onlyOwner();
        _;
    }

    /**
     * @dev Internal function for reducing onlyOwner modifier bytecode overhead.
     */
    function _onlyOwner() internal view {
        require(msg.sender == owner());
    }

    /**
     * @dev Throws if called through proxy by any account other than contract itself or an upgradeability owner.
     */
    modifier onlyRelevantSender() {
        (bool isProxy, bytes memory returnData) =
            address(this).staticcall(abi.encodeWithSelector(UPGRADEABILITY_OWNER));
        require(
            !isProxy || // covers usage without calling through storage proxy
                (returnData.length == 32 && msg.sender == abi.decode(returnData, (address))) || // covers usage through regular proxy calls
                msg.sender == address(this) // covers calls through upgradeAndCall proxy method
        );
        _;
    }

    bytes32 internal constant OWNER = 0x02016836a56b71f0d02689e69e326f4f4c1b9057164ef592671cf0d37c8040c0; // keccak256(abi.encodePacked("owner"))

    /**
     * @dev Tells the address of the owner
     * @return the address of the owner
     */
    function owner() public view returns (address) {
        return addressStorage[OWNER];
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner the address to transfer ownership to.
     */
    function transferOwnership(address newOwner) external onlyOwner {
        _setOwner(newOwner);
    }

    /**
     * @dev Sets a new owner address
     */
    function _setOwner(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(owner(), newOwner);
        addressStorage[OWNER] = newOwner;
    }
}
