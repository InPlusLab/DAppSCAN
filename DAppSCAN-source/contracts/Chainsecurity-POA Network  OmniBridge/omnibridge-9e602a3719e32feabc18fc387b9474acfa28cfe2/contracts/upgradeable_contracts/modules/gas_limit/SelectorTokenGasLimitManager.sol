pragma solidity 0.7.5;

import "../../../interfaces/IAMB.sol";
import "../OwnableModule.sol";
import "../../BasicOmnibridge.sol";

/**
 * @title SelectorTokenGasLimitManager
 * @dev Multi token mediator functionality for managing request gas limits.
 */
contract SelectorTokenGasLimitManager is OwnableModule {
    IAMB public immutable bridge;

    uint256 internal defaultGasLimit;
    mapping(bytes4 => uint256) internal selectorGasLimit;
    mapping(bytes4 => mapping(address => uint256)) internal selectorTokenGasLimit;

    constructor(
        IAMB _bridge,
        address _owner,
        uint256 _gasLimit
    ) OwnableModule(_owner) {
        require(_gasLimit <= _bridge.maxGasPerTx());
        bridge = _bridge;
        defaultGasLimit = _gasLimit;
    }

    /**
     * @dev Throws if provided gas limit is greater then the maximum allowed gas limit in the AMB contract.
     * @param _gasLimit gas limit value to check.
     */
    modifier validGasLimit(uint256 _gasLimit) {
        require(_gasLimit <= bridge.maxGasPerTx());
        _;
    }

    /**
     * @dev Throws if one of the provided gas limits is greater then the maximum allowed gas limit in the AMB contract.
     * @param _length expected length of the _gasLimits array.
     * @param _gasLimits array of gas limit values to check, should contain exactly _length elements.
     */
    modifier validGasLimits(uint256 _length, uint256[] calldata _gasLimits) {
        require(_gasLimits.length == _length);
        uint256 maxGasLimit = bridge.maxGasPerTx();
        for (uint256 i = 0; i < _length; i++) {
            require(_gasLimits[i] <= maxGasLimit);
        }
        _;
    }

    /**
     * @dev Sets the default gas limit to be used in the message execution by the AMB bridge on the other network.
     * This value can't exceed the parameter maxGasPerTx defined on the AMB bridge.
     * Only the owner can call this method.
     * @param _gasLimit the gas limit for the message execution.
     */
    function setRequestGasLimit(uint256 _gasLimit) external onlyOwner validGasLimit(_gasLimit) {
        defaultGasLimit = _gasLimit;
    }

    /**
     * @dev Sets the selector-specific gas limit to be used in the message execution by the AMB bridge on the other network.
     * This value can't exceed the parameter maxGasPerTx defined on the AMB bridge.
     * Only the owner can call this method.
     * @param _selector method selector of the outgoing message payload.
     * @param _gasLimit the gas limit for the message execution.
     */
    function setRequestGasLimit(bytes4 _selector, uint256 _gasLimit) external onlyOwner validGasLimit(_gasLimit) {
        selectorGasLimit[_selector] = _gasLimit;
    }

    /**
     * @dev Sets the token-specific gas limit to be used in the message execution by the AMB bridge on the other network.
     * This value can't exceed the parameter maxGasPerTx defined on the AMB bridge.
     * Only the owner can call this method.
     * @param _selector method selector of the outgoing message payload.
     * @param _token address of the native token that is used in the first argument of handleBridgedTokens/handleNativeTokens.
     * @param _gasLimit the gas limit for the message execution.
     */
    function setRequestGasLimit(
        bytes4 _selector,
        address _token,
        uint256 _gasLimit
    ) external onlyOwner validGasLimit(_gasLimit) {
        selectorTokenGasLimit[_selector][_token] = _gasLimit;
    }

    /**
     * @dev Tells the default gas limit to be used in the message execution by the AMB bridge on the other network.
     * @return the gas limit for the message execution.
     */
    function requestGasLimit() public view returns (uint256) {
        return defaultGasLimit;
    }

    /**
     * @dev Tells the selector-specific gas limit to be used in the message execution by the AMB bridge on the other network.
     * @param _selector method selector for the passed message.
     * @return the gas limit for the message execution.
     */
    function requestGasLimit(bytes4 _selector) public view returns (uint256) {
        return selectorGasLimit[_selector];
    }

    /**
     * @dev Tells the token-specific gas limit to be used in the message execution by the AMB bridge on the other network.
     * @param _selector method selector for the passed message.
     * @param _token address of the native token that is used in the first argument of handleBridgedTokens/handleNativeTokens.
     * @return the gas limit for the message execution.
     */
    function requestGasLimit(bytes4 _selector, address _token) public view returns (uint256) {
        return selectorTokenGasLimit[_selector][_token];
    }

    /**
     * @dev Tells the gas limit to use for the message execution by the AMB bridge on the other network.
     * @param _data calldata to be used on the other side of the bridge, when execution a message.
     * @return the gas limit for the message execution.
     */
    function requestGasLimit(bytes memory _data) external view returns (uint256) {
        bytes4 selector;
        address token;
        assembly {
            // first 4 bytes of _data contain the selector of the function to be called on the other side of the bridge.
            // mload(add(_data, 4)) loads selector to the 28-31 bytes of the word.
            // shl(28 * 8, x) then used to correct the padding of the selector, putting it to 0-3 bytes of the word.
            selector := shl(224, mload(add(_data, 4)))
            // handleBridgedTokens/handleNativeTokens/... passes bridged token address as the first parameter.
            // it is located in the 4-35 bytes of the calldata.
            // 36 = bytes length padding (32) + selector length (4)
            token := mload(add(_data, 36))
        }
        uint256 gasLimit = selectorTokenGasLimit[selector][token];
        if (gasLimit == 0) {
            gasLimit = selectorGasLimit[selector];
            if (gasLimit == 0) {
                gasLimit = defaultGasLimit;
            }
        }
        return gasLimit;
    }

    /**
     * @dev Sets the default values for different Omnibridge selectors.
     * @param _gasLimits array with 7 gas limits for the following selectors of the outgoing messages:
     * - deployAndHandleBridgedTokens, deployAndHandleBridgedTokensAndCall
     * - handleBridgedTokens, handleBridgedTokensAndCall
     * - handleNativeTokens, handleNativeTokensAndCall
     * - fixFailedMessage
     * Only the owner can call this method.
     */
    function setCommonRequestGasLimits(uint256[] calldata _gasLimits) external onlyOwner validGasLimits(7, _gasLimits) {
        require(_gasLimits[1] >= _gasLimits[0]);
        require(_gasLimits[3] >= _gasLimits[2]);
        require(_gasLimits[5] >= _gasLimits[4]);
        require(_gasLimits[0] >= _gasLimits[2]);
        require(_gasLimits[1] >= _gasLimits[3]);
        selectorGasLimit[BasicOmnibridge.deployAndHandleBridgedTokens.selector] = _gasLimits[0];
        selectorGasLimit[BasicOmnibridge.deployAndHandleBridgedTokensAndCall.selector] = _gasLimits[1];
        selectorGasLimit[BasicOmnibridge.handleBridgedTokens.selector] = _gasLimits[2];
        selectorGasLimit[BasicOmnibridge.handleBridgedTokensAndCall.selector] = _gasLimits[3];
        selectorGasLimit[BasicOmnibridge.handleNativeTokens.selector] = _gasLimits[4];
        selectorGasLimit[BasicOmnibridge.handleNativeTokensAndCall.selector] = _gasLimits[5];
        selectorGasLimit[FailedMessagesProcessor.fixFailedMessage.selector] = _gasLimits[6];
    }

    /**
     * @dev Sets the request gas limits for some specific token bridged from Foreign side of the bridge.
     * @param _token address of the native token contract on the Foreign side.
     * @param _gasLimits array with 2 gas limits for the following selectors of the outgoing messages:
     * - handleNativeTokens, handleNativeTokensAndCall
     * Only the owner can call this method.
     */
    function setBridgedTokenRequestGasLimits(address _token, uint256[] calldata _gasLimits)
        external
        onlyOwner
        validGasLimits(2, _gasLimits)
    {
        require(_gasLimits[1] >= _gasLimits[0]);
        selectorTokenGasLimit[BasicOmnibridge.handleNativeTokens.selector][_token] = _gasLimits[0];
        selectorTokenGasLimit[BasicOmnibridge.handleNativeTokensAndCall.selector][_token] = _gasLimits[1];
    }

    /**
     * @dev Sets the request gas limits for some specific token native to the Home side of the bridge.
     * @param _token address of the native token contract on the Home side.
     * @param _gasLimits array with 4 gas limits for the following selectors of the outgoing messages:
     * - deployAndHandleBridgedTokens, deployAndHandleBridgedTokensAndCall
     * - handleBridgedTokens, handleBridgedTokensAndCall
     * Only the owner can call this method.
     */
    function setNativeTokenRequestGasLimits(address _token, uint256[] calldata _gasLimits)
        external
        onlyOwner
        validGasLimits(4, _gasLimits)
    {
        require(_gasLimits[1] >= _gasLimits[0]);
        require(_gasLimits[3] >= _gasLimits[2]);
        require(_gasLimits[0] >= _gasLimits[2]);
        require(_gasLimits[1] >= _gasLimits[3]);
        selectorTokenGasLimit[BasicOmnibridge.deployAndHandleBridgedTokens.selector][_token] = _gasLimits[0];
        selectorTokenGasLimit[BasicOmnibridge.deployAndHandleBridgedTokensAndCall.selector][_token] = _gasLimits[1];
        selectorTokenGasLimit[BasicOmnibridge.handleBridgedTokens.selector][_token] = _gasLimits[2];
        selectorTokenGasLimit[BasicOmnibridge.handleBridgedTokensAndCall.selector][_token] = _gasLimits[3];
    }
}
