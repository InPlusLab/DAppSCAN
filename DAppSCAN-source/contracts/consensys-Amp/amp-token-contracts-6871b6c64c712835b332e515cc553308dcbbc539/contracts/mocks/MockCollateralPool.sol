// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;

import "../erc1820/ERC1820Client.sol";
import "../erc1820/ERC1820Implementer.sol";


interface IAmp {
    function registerCollateralManager() external;

    function authorizeOperator(address) external;

    function operatorTransferByPartition(
        bytes32 _partition,
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data,
        bytes calldata _operatorData
    ) external returns (bytes32);
}


contract MockCollateralPool is ERC1820Implementer, ERC1820Client {
    string internal constant AMP_TOKENS_RECIPIENT = "AmpTokensRecipient";
    string internal constant AMP_TOKENS_SENDER = "AmpTokensSender";

    bytes2 internal constant VALID_DATA = 0x1111;

    address owner;

    mapping(address => uint256) _suppliers;

    IAmp amp;

    event SimplePoolSupply(bytes data);

    constructor(address _amp, bool _selfRegister) public {
        // Register as handler for self for AMP_TOKENS_RECIPIENT
        ERC1820Client.setInterfaceImplementation(AMP_TOKENS_RECIPIENT, address(this));
        ERC1820Implementer._setInterface(AMP_TOKENS_RECIPIENT);

        ERC1820Client.setInterfaceImplementation(AMP_TOKENS_SENDER, address(this));
        ERC1820Implementer._setInterface(AMP_TOKENS_SENDER);

        owner = msg.sender;

        amp = IAmp(_amp);
        if (_selfRegister) {
            amp.registerCollateralManager();
        }

        amp.authorizeOperator(owner);
    }

    function supplyOf(address supplier) external view returns (uint256) {
        return _suppliers[supplier];
    }

    function canReceive(
        bytes4, /* functionSig */
        bytes32, /* partition */
        address, /* operator */
        address, /* from */
        address, /* to */
        uint256, /* value */
        bytes calldata, /* data */
        bytes calldata /* operatorData */
    ) external pure returns (bool) {
        return true;
    }

    function tokensReceived(
        bytes4, /* functionSig */
        bytes32, /* partition */
        address, /* operator */
        address _from,
        address, /* to */
        uint256 _value,
        bytes calldata _data,
        bytes calldata /* operatorData */
    ) external {
        _suppliers[_from] = _value;

        emit SimplePoolSupply(_data);
    }

    function tokensToTransfer(
        bytes4, /* functionSig */
        bytes32, /* partition */
        address _operator,
        address, /* from */
        address, /* to */
        uint256, /* value */
        bytes calldata, /* data */
        bytes calldata _operatorData
    ) external view {
        // Add this line to bypass the operator data check when this hook would
        // be invoked due to a transfer initiated the contract's owner
        if (_operator == owner) {
            return;
        }

        bytes memory odata = _operatorData;
        bytes32 proof;
        assembly {
            proof := mload(add(odata, 32))
        }
        require(
            bytes2(proof) == VALID_DATA,
            "Holder cant transfer: Tokens collateralization"
        );
    }

    function testConsume(
        bytes32 _fromPartition,
        address _from,
        uint256 _value,
        bytes calldata _data
    ) external {
        amp.operatorTransferByPartition(
            _fromPartition,
            _from,
            address(this),
            _value,
            _data,
            ""
        );
    }
}
