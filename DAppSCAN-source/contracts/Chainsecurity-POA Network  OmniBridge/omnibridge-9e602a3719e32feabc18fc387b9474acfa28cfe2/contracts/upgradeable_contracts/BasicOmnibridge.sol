pragma solidity 0.7.5;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Initializable.sol";
import "./Upgradeable.sol";
import "./Claimable.sol";
import "./components/bridged/BridgedTokensRegistry.sol";
import "./components/native/NativeTokensRegistry.sol";
import "./components/native/MediatorBalanceStorage.sol";
import "./components/common/TokensRelayer.sol";
import "./components/common/OmnibridgeInfo.sol";
import "./components/common/TokensBridgeLimits.sol";
import "./components/common/FailedMessagesProcessor.sol";
import "./modules/factory/TokenFactoryConnector.sol";
import "../interfaces/IBurnableMintableERC677Token.sol";
import "../interfaces/IERC20Metadata.sol";
import "../interfaces/IERC20Receiver.sol";
import "../libraries/TokenReader.sol";
import "../libraries/SafeMint.sol";

/**
 * @title BasicOmnibridge
 * @dev Common functionality for multi-token mediator intended to work on top of AMB bridge.
 */
abstract contract BasicOmnibridge is
    Initializable,
    Upgradeable,
    Claimable,
    OmnibridgeInfo,
    TokensRelayer,
    FailedMessagesProcessor,
    BridgedTokensRegistry,
    NativeTokensRegistry,
    MediatorBalanceStorage,
    TokenFactoryConnector,
    TokensBridgeLimits
{
    using SafeERC20 for IERC677;
    using SafeMint for IBurnableMintableERC677Token;
    using SafeMath for uint256;

    // Workaround for storing variable up-to-32 bytes suffix
    uint256 private immutable SUFFIX_SIZE;
    bytes32 private immutable SUFFIX;

    // Since contract is intended to be deployed under EternalStorageProxy, only constant and immutable variables can be set here
    constructor(string memory _suffix) {
        require(bytes(_suffix).length <= 32);
        bytes32 suffix;
        assembly {
            suffix := mload(add(_suffix, 32))
        }
        SUFFIX = suffix;
        SUFFIX_SIZE = bytes(_suffix).length;
    }

    /**
     * @dev Handles the bridged tokens for the first time, includes deployment of new TokenProxy contract.
     * Checks that the value is inside the execution limits and invokes the Mint or Unlock accordingly.
     * @param _token address of the native ERC20/ERC677 token on the other side.
     * @param _name name of the native token, name suffix will be appended, if empty, symbol will be used instead.
     * @param _symbol symbol of the bridged token, if empty, name will be used instead.
     * @param _decimals decimals of the bridge foreign token.
     * @param _recipient address that will receive the tokens.
     * @param _value amount of tokens to be received.
     */
    function deployAndHandleBridgedTokens(
        address _token,
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        address _recipient,
        uint256 _value
    ) external onlyMediator {
        address bridgedToken = _getBridgedTokenOrDeploy(_token, _name, _symbol, _decimals);

        _handleTokens(bridgedToken, false, _recipient, _value);
    }

    /**
     * @dev Handles the bridged tokens for the first time, includes deployment of new TokenProxy contract.
     * Executes a callback on the receiver.
     * Checks that the value is inside the execution limits and invokes the Mint accordingly.
     * @param _token address of the native ERC20/ERC677 token on the other side.
     * @param _name name of the native token, name suffix will be appended, if empty, symbol will be used instead.
     * @param _symbol symbol of the bridged token, if empty, name will be used instead.
     * @param _decimals decimals of the bridge foreign token.
     * @param _recipient address that will receive the tokens.
     * @param _value amount of tokens to be received.
     * @param _data additional data passed from the other chain.
     */
    function deployAndHandleBridgedTokensAndCall(
        address _token,
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals,
        address _recipient,
        uint256 _value,
        bytes calldata _data
    ) external onlyMediator {
        address bridgedToken = _getBridgedTokenOrDeploy(_token, _name, _symbol, _decimals);

        _handleTokens(bridgedToken, false, _recipient, _value);

        _receiverCallback(_recipient, bridgedToken, _value, _data);
    }

    /**
     * @dev Handles the bridged tokens for the already registered token pair.
     * Checks that the value is inside the execution limits and invokes the Mint accordingly.
     * @param _token address of the native ERC20/ERC677 token on the other side.
     * @param _recipient address that will receive the tokens.
     * @param _value amount of tokens to be received.
     */
    function handleBridgedTokens(
        address _token,
        address _recipient,
        uint256 _value
    ) external onlyMediator {
        address token = bridgedTokenAddress(_token);

        require(isTokenRegistered(token));

        _handleTokens(token, false, _recipient, _value);
    }

    /**
     * @dev Handles the bridged tokens for the already registered token pair.
     * Checks that the value is inside the execution limits and invokes the Unlock accordingly.
     * Executes a callback on the receiver.
     * @param _token address of the native ERC20/ERC677 token on the other side.
     * @param _recipient address that will receive the tokens.
     * @param _value amount of tokens to be received.
     * @param _data additional transfer data passed from the other side.
     */
    function handleBridgedTokensAndCall(
        address _token,
        address _recipient,
        uint256 _value,
        bytes memory _data
    ) external onlyMediator {
        address token = bridgedTokenAddress(_token);

        require(isTokenRegistered(token));

        _handleTokens(token, false, _recipient, _value);

        _receiverCallback(_recipient, token, _value, _data);
    }

    /**
     * @dev Handles the bridged tokens that are native to this chain.
     * Checks that the value is inside the execution limits and invokes the Unlock accordingly.
     * @param _token native ERC20 token.
     * @param _recipient address that will receive the tokens.
     * @param _value amount of tokens to be received.
     */
    function handleNativeTokens(
        address _token,
        address _recipient,
        uint256 _value
    ) external onlyMediator {
        _ackBridgedTokenDeploy(_token);

        _handleTokens(_token, true, _recipient, _value);
    }

    /**
     * @dev Handles the bridged tokens that are native to this chain.
     * Checks that the value is inside the execution limits and invokes the Unlock accordingly.
     * Executes a callback on the receiver.
     * @param _token native ERC20 token.
     * @param _recipient address that will receive the tokens.
     * @param _value amount of tokens to be received.
     * @param _data additional transfer data passed from the other side.
     */
    function handleNativeTokensAndCall(
        address _token,
        address _recipient,
        uint256 _value,
        bytes memory _data
    ) external onlyMediator {
        _ackBridgedTokenDeploy(_token);

        _handleTokens(_token, true, _recipient, _value);

        _receiverCallback(_recipient, _token, _value, _data);
    }

    /**
     * @dev Checks if a given token is a bridged token that is native to this side of the bridge.
     * @param _token address of token contract.
     * @return message id of the send message.
     */
    function isRegisteredAsNativeToken(address _token) public view returns (bool) {
        return isTokenRegistered(_token) && nativeTokenAddress(_token) == address(0);
    }

    /**
     * @dev Unlock back the amount of tokens that were bridged to the other network but failed.
     * @param _token address that bridged token contract.
     * @param _recipient address that will receive the tokens.
     * @param _value amount of tokens to be received.
     */
    function executeActionOnFixedTokens(
        address _token,
        address _recipient,
        uint256 _value
    ) internal override {
        _releaseTokens(nativeTokenAddress(_token) == address(0), _token, _recipient, _value, _value);
    }

    /**
     * @dev Allows to pre-set the bridged token contract for not-yet bridged token.
     * Only the owner can call this method.
     * @param _nativeToken address of the token contract on the other side that was not yet bridged.
     * @param _bridgedToken address of the bridged token contract.
     */
    function setCustomTokenAddressPair(address _nativeToken, address _bridgedToken) external onlyOwner {
        require(!isTokenRegistered(_bridgedToken));
        require(nativeTokenAddress(_bridgedToken) == address(0));
        require(bridgedTokenAddress(_nativeToken) == address(0));
        // Unfortunately, there is no simple way to verify that the _nativeToken address
        // does not belong to the bridged token on the other side,
        // since information about bridged tokens addresses is not transferred back.
        // Therefore, owner account calling this function SHOULD manually verify on the other side of the bridge that
        // nativeTokenAddress(_nativeToken) == address(0) && isTokenRegistered(_nativeToken) == false.

        IBurnableMintableERC677Token(_bridgedToken).safeMint(address(this), 1);
        IBurnableMintableERC677Token(_bridgedToken).burn(1);

        _setTokenAddressPair(_nativeToken, _bridgedToken);
    }

    /**
     * @dev Allows to send to the other network the amount of locked tokens that can be forced into the contract
     * without the invocation of the required methods. (e. g. regular transfer without a call to onTokenTransfer)
     * @param _token address of the token contract.
     * Before calling this method, it must be carefully investigated how imbalance happened
     * in order to avoid an attempt to steal the funds from a token with double addresses
     * (e.g. TUSD is accessible at both 0x8dd5fbCe2F6a956C3022bA3663759011Dd51e73E and 0x0000000000085d4780B73119b644AE5ecd22b376)
     * @param _receiver the address that will receive the tokens on the other network.
     */
    function fixMediatorBalance(address _token, address _receiver)
        external
        onlyIfUpgradeabilityOwner
        validAddress(_receiver)
    {
        require(isRegisteredAsNativeToken(_token));

        uint256 balance = IERC677(_token).balanceOf(address(this));
        uint256 expectedBalance = mediatorBalance(_token);
        require(balance > expectedBalance);
        uint256 diff = balance - expectedBalance;
        uint256 available = maxAvailablePerTx(_token);
        require(available > 0);
        if (diff > available) {
            diff = available;
        }
        addTotalSpentPerDay(_token, getCurrentDay(), diff);

        bytes memory data = _prepareMessage(address(0), _token, _receiver, diff, new bytes(0));
        bytes32 _messageId = _passMessage(data, true);
        _recordBridgeOperation(_messageId, _token, _receiver, diff);
    }

    /**
     * @dev Claims stuck tokens. Only unsupported tokens can be claimed.
     * When dealing with already supported tokens, fixMediatorBalance can be used instead.
     * @param _token address of claimed token, address(0) for native
     * @param _to address of tokens receiver
     */
    function claimTokens(address _token, address _to) external onlyIfUpgradeabilityOwner {
        // Only unregistered tokens and native coins are allowed to be claimed with the use of this function
        require(_token == address(0) || !isTokenRegistered(_token));
        claimValues(_token, _to);
    }

    /**
     * @dev Withdraws erc20 tokens or native coins from the bridged token contract.
     * Only the proxy owner is allowed to call this method.
     * @param _bridgedToken address of the bridged token contract.
     * @param _token address of the claimed token or address(0) for native coins.
     * @param _to address of the tokens/coins receiver.
     */
    function claimTokensFromTokenContract(
        address _bridgedToken,
        address _token,
        address _to
    ) external onlyIfUpgradeabilityOwner {
        IBurnableMintableERC677Token(_bridgedToken).claimTokens(_token, _to);
    }

    /**
     * @dev Internal function for recording bridge operation for further usage.
     * Recorded information is used for fixing failed requests on the other side.
     * @param _messageId id of the sent message.
     * @param _token bridged token address.
     * @param _sender address of the tokens sender.
     * @param _value bridged value.
     */
    function _recordBridgeOperation(
        bytes32 _messageId,
        address _token,
        address _sender,
        uint256 _value
    ) internal {
        setMessageToken(_messageId, _token);
        setMessageRecipient(_messageId, _sender);
        setMessageValue(_messageId, _value);

        emit TokensBridgingInitiated(_token, _sender, _value, _messageId);
    }

    /**
     * @dev Constructs the message to be sent to the other side. Burns/locks bridged amount of tokens.
     * @param _nativeToken address of the native token contract.
     * @param _token bridged token address.
     * @param _receiver address of the tokens receiver on the other side.
     * @param _value bridged value.
     * @param _data additional transfer data passed from the other side.
     */
    function _prepareMessage(
        address _nativeToken,
        address _token,
        address _receiver,
        uint256 _value,
        bytes memory _data
    ) internal returns (bytes memory) {
        bool withData = _data.length > 0 || msg.sig == this.relayTokensAndCall.selector;

        // process token is native with respect to this side of the bridge
        if (_nativeToken == address(0)) {
            _setMediatorBalance(_token, mediatorBalance(_token).add(_value));

            // process token which bridged alternative was already ACKed to be deployed
            if (isBridgedTokenDeployAcknowledged(_token)) {
                return
                    withData
                        ? abi.encodeWithSelector(
                            this.handleBridgedTokensAndCall.selector,
                            _token,
                            _receiver,
                            _value,
                            _data
                        )
                        : abi.encodeWithSelector(this.handleBridgedTokens.selector, _token, _receiver, _value);
            }

            uint8 decimals = TokenReader.readDecimals(_token);
            string memory name = TokenReader.readName(_token);
            string memory symbol = TokenReader.readSymbol(_token);

            require(bytes(name).length > 0 || bytes(symbol).length > 0);

            return
                withData
                    ? abi.encodeWithSelector(
                        this.deployAndHandleBridgedTokensAndCall.selector,
                        _token,
                        name,
                        symbol,
                        decimals,
                        _receiver,
                        _value,
                        _data
                    )
                    : abi.encodeWithSelector(
                        this.deployAndHandleBridgedTokens.selector,
                        _token,
                        name,
                        symbol,
                        decimals,
                        _receiver,
                        _value
                    );
        }

        // process already known token that is bridged from other chain
        IBurnableMintableERC677Token(_token).burn(_value);
        return
            withData
                ? abi.encodeWithSelector(
                    this.handleNativeTokensAndCall.selector,
                    _nativeToken,
                    _receiver,
                    _value,
                    _data
                )
                : abi.encodeWithSelector(this.handleNativeTokens.selector, _nativeToken, _receiver, _value);
    }

    /**
     * @dev Internal function for getting minter proxy address.
     * @param _token address of the token to mint.
     * @return address of the minter contract that should be used for calling mint(address,uint256)
     */
    function _getMinterFor(address _token) internal pure virtual returns (IBurnableMintableERC677Token) {
        return IBurnableMintableERC677Token(_token);
    }

    /**
     * Internal function for unlocking some amount of tokens.
     * @param _isNative true, if token is native w.r.t. to this side of the bridge.
     * @param _token address of the token contract.
     * @param _recipient address of the tokens receiver.
     * @param _value amount of tokens to unlock.
     * @param _balanceChange amount of balance to subtract from the mediator balance.
     */
    function _releaseTokens(
        bool _isNative,
        address _token,
        address _recipient,
        uint256 _value,
        uint256 _balanceChange
    ) internal virtual {
        if (_isNative) {
            IERC677(_token).safeTransfer(_recipient, _value);
            _setMediatorBalance(_token, mediatorBalance(_token).sub(_balanceChange));
        } else {
            _getMinterFor(_token).safeMint(_recipient, _value);
        }
    }

    /**
     * Internal function for getting address of the bridged token. Deploys new token if necessary.
     * @param _token address of the token contract on the other side of the bridge.
     * @param _name name of the native token, name suffix will be appended, if empty, symbol will be used instead.
     * @param _symbol symbol of the bridged token, if empty, name will be used instead.
     * @param _decimals decimals of the bridge foreign token.
     */
    function _getBridgedTokenOrDeploy(
        address _token,
        string calldata _name,
        string calldata _symbol,
        uint8 _decimals
    ) internal returns (address) {
        address bridgedToken = bridgedTokenAddress(_token);
        if (bridgedToken == address(0)) {
            string memory name = _name;
            string memory symbol = _symbol;
            require(bytes(name).length > 0 || bytes(symbol).length > 0);
            if (bytes(name).length == 0) {
                name = symbol;
            } else if (bytes(symbol).length == 0) {
                symbol = name;
            }
            name = _transformName(name);
            bridgedToken = tokenFactory().deploy(name, symbol, _decimals, bridgeContract().sourceChainId());
            _setTokenAddressPair(_token, bridgedToken);
            _initializeTokenBridgeLimits(bridgedToken, _decimals);
        } else if (!isTokenRegistered(bridgedToken)) {
            require(IERC20Metadata(bridgedToken).decimals() == _decimals);
            _initializeTokenBridgeLimits(bridgedToken, _decimals);
        }
        return bridgedToken;
    }

    /**
     * Notifies receiving contract about the completed bridging operation.
     * @param _recipient address of the tokens receiver.
     * @param _token address of the bridged token.
     * @param _value amount of tokens transferred.
     * @param _data additional data passed to the callback.
     */
    function _receiverCallback(
        address _recipient,
        address _token,
        uint256 _value,
        bytes memory _data
    ) internal {
        if (Address.isContract(_recipient)) {
            _recipient.call(abi.encodeWithSelector(IERC20Receiver.onTokenBridged.selector, _token, _value, _data));
        }
    }

    /**
     * @dev Internal function for transforming the bridged token name. Appends a side-specific suffix.
     * @param _name bridged token from the other side.
     * @return token name for this side of the bridge.
     */
    function _transformName(string memory _name) internal view returns (string memory) {
        string memory result = string(abi.encodePacked(_name, SUFFIX));
        uint256 size = SUFFIX_SIZE;
        assembly {
            mstore(result, add(mload(_name), size))
        }
        return result;
    }

    function _handleTokens(
        address _token,
        bool _isNative,
        address _recipient,
        uint256 _value
    ) internal virtual;
}
