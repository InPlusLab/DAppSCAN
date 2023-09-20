pragma solidity 0.7.5;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../../../interfaces/IERC677.sol";
import "../../../libraries/Bytes.sol";
import "../../ReentrancyGuard.sol";
import "../../BasicAMBMediator.sol";

/**
 * @title TokensRelayer
 * @dev Functionality for bridging multiple tokens to the other side of the bridge.
 */
abstract contract TokensRelayer is BasicAMBMediator, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC677;

    /**
     * @dev ERC677 transfer callback function.
     * @param _from address of tokens sender.
     * @param _value amount of transferred tokens.
     * @param _data additional transfer data, can be used for passing alternative receiver address.
     */
    function onTokenTransfer(
        address _from,
        uint256 _value,
        bytes memory _data
    ) external returns (bool) {
        if (!lock()) {
            bytes memory data = new bytes(0);
            address receiver = _from;
            if (_data.length >= 20) {
                receiver = Bytes.bytesToAddress(_data);
                if (_data.length > 20) {
                    assembly {
                        let size := sub(mload(_data), 20)
                        data := add(_data, 20)
                        mstore(data, size)
                    }
                }
            }
            bridgeSpecificActionsOnTokenTransfer(msg.sender, _from, receiver, _value, data);
        }
        return true;
    }

    /**
     * @dev Initiate the bridge operation for some amount of tokens from msg.sender.
     * The user should first call Approve method of the ERC677 token.
     * @param token bridged token contract address.
     * @param _receiver address that will receive the native tokens on the other network.
     * @param _value amount of tokens to be transferred to the other network.
     */
    function relayTokens(
        IERC677 token,
        address _receiver,
        uint256 _value
    ) external {
        _relayTokens(token, _receiver, _value, new bytes(0));
    }

    /**
     * @dev Initiate the bridge operation for some amount of tokens from msg.sender to msg.sender on the other side.
     * The user should first call Approve method of the ERC677 token.
     * @param token bridged token contract address.
     * @param _value amount of tokens to be transferred to the other network.
     */
    function relayTokens(IERC677 token, uint256 _value) external {
        _relayTokens(token, msg.sender, _value, new bytes(0));
    }

    /**
     * @dev Initiate the bridge operation for some amount of tokens from msg.sender.
     * The user should first call Approve method of the ERC677 token.
     * @param token bridged token contract address.
     * @param _receiver address that will receive the native tokens on the other network.
     * @param _value amount of tokens to be transferred to the other network.
     * @param _data additional transfer data to be used on the other side.
     */
    function relayTokensAndCall(
        IERC677 token,
        address _receiver,
        uint256 _value,
        bytes memory _data
    ) external {
        _relayTokens(token, _receiver, _value, _data);
    }

    /**
     * @dev Validates that the token amount is inside the limits, calls transferFrom to transfer the tokens to the contract
     * and invokes the method to burn/lock the tokens and unlock/mint the tokens on the other network.
     * The user should first call Approve method of the ERC677 token.
     * @param token bridge token contract address.
     * @param _receiver address that will receive the native tokens on the other network.
     * @param _value amount of tokens to be transferred to the other network.
     * @param _data additional transfer data to be used on the other side.
     */
    // SWC-107-Reentrancy: L99-117
    function _relayTokens(
        IERC677 token,
        address _receiver,
        uint256 _value,
        bytes memory _data
    ) internal {
        // This lock is to prevent calling passMessage twice if a ERC677 token is used.
        // When transferFrom is called, after the transfer, the ERC677 token will call onTokenTransfer from this contract
        // which will call passMessage.
        require(!lock());

        uint256 balanceBefore = token.balanceOf(address(this));
        setLock(true);
        token.safeTransferFrom(msg.sender, address(this), _value);
        setLock(false);
        uint256 balanceDiff = token.balanceOf(address(this)).sub(balanceBefore);
        require(balanceDiff <= _value);
        bridgeSpecificActionsOnTokenTransfer(address(token), msg.sender, _receiver, balanceDiff, _data);
    }

    function bridgeSpecificActionsOnTokenTransfer(
        address _token,
        address _from,
        address _receiver,
        uint256 _value,
        bytes memory _data
    ) internal virtual;
}
