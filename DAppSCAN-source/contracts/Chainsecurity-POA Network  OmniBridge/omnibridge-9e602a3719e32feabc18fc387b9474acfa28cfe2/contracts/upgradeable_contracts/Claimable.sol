pragma solidity 0.7.5;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../libraries/AddressHelper.sol";

/**
 * @title Claimable
 * @dev Implementation of the claiming utils that can be useful for withdrawing accidentally sent tokens that are not used in bridge operations.
 */
contract Claimable {
    using SafeERC20 for IERC20;

    /**
     * Throws if a given address is equal to address(0)
     */
    modifier validAddress(address _to) {
        require(_to != address(0));
        _;
    }

    /**
     * @dev Withdraws the erc20 tokens or native coins from this contract.
     * Caller should additionally check that the claimed token is not a part of bridge operations (i.e. that token != erc20token()).
     * @param _token address of the claimed token or address(0) for native coins.
     * @param _to address of the tokens/coins receiver.
     */
    function claimValues(address _token, address _to) internal validAddress(_to) {
        if (_token == address(0)) {
            claimNativeCoins(_to);
        } else {
            claimErc20Tokens(_token, _to);
        }
    }

    /**
     * @dev Internal function for withdrawing all native coins from the contract.
     * @param _to address of the coins receiver.
     */
    function claimNativeCoins(address _to) internal {
        uint256 value = address(this).balance;
        AddressHelper.safeSendValue(payable(_to), value);
    }

    /**
     * @dev Internal function for withdrawing all tokens of ssome particular ERC20 contract from this contract.
     * @param _token address of the claimed ERC20 token.
     * @param _to address of the tokens receiver.
     */
    function claimErc20Tokens(address _token, address _to) internal {
        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(_to, balance);
    }
}
