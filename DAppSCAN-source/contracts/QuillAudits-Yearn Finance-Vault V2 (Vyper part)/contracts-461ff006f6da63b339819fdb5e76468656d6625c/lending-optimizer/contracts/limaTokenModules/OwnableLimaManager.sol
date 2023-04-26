pragma solidity ^0.6.6;


// import "@openzeppelin/upgrades/contracts/Initializable.sol";
import { Initializable} from "@openzeppelin/contracts-ethereum-package/contracts/GSN/Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an limaManager) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the limaManager account will be the one that deploys the contract. This
 * can later be changed with {transferLimaManagerOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyLimaManager`, which can be applied to your functions to restrict their use to
 * the limaManager.
 */
contract OwnableLimaManager is Initializable {
    address private _limaManager;

    event LimaManagerOwnershipTransferred(address indexed previousLimaManager, address indexed newLimaManager);

    /**
     * @dev Initializes the contract setting the deployer as the initial limaManager.
     */

    function __OwnableLimaManager_init_unchained() internal initializer {
        address msgSender = msg.sender;
        _limaManager = msgSender;
        emit LimaManagerOwnershipTransferred(address(0), msgSender);

    }


    /**
     * @dev Returns the address of the current limaManager.
     */
    function limaManager() public view returns (address) {
        return _limaManager;
    }

    /**
     * @dev Throws if called by any account other than the limaManager.
     */
    modifier onlyLimaManager() {
        require(_limaManager == msg.sender, "OwnableLimaManager: caller is not the limaManager");
        _;
    }

    /**
     * @dev Transfers limaManagership of the contract to a new account (`newLimaManager`).
     * Can only be called by the current limaManager.
     */
    function transferLimaManagerOwnership(address newLimaManager) public virtual onlyLimaManager {
        require(newLimaManager != address(0), "OwnableLimaManager: new limaManager is the zero address");
        emit LimaManagerOwnershipTransferred(_limaManager, newLimaManager);
        _limaManager = newLimaManager;
    }

}
