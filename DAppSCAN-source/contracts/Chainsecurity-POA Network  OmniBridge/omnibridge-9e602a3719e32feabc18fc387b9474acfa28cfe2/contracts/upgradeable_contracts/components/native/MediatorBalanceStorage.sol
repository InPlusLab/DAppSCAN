pragma solidity 0.7.5;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../../../upgradeability/EternalStorage.sol";

/**
 * @title MediatorBalanceStorage
 * @dev Functionality for storing expected mediator balance for native tokens.
 */
contract MediatorBalanceStorage is EternalStorage {
    /**
     * @dev Tells the expected token balance of the contract.
     * @param _token address of token contract.
     * @return the current tracked token balance of the contract.
     */
    function mediatorBalance(address _token) public view returns (uint256) {
        return uintStorage[keccak256(abi.encodePacked("mediatorBalance", _token))];
    }

    /**
     * @dev Updates expected token balance of the contract.
     * @param _token address of token contract.
     * @param _balance the new token balance of the contract.
     */
    function _setMediatorBalance(address _token, uint256 _balance) internal {
        uintStorage[keccak256(abi.encodePacked("mediatorBalance", _token))] = _balance;
    }
}
