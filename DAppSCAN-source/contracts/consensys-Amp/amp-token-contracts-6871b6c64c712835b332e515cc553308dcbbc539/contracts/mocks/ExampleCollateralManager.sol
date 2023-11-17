// SPDX-License-Identifier: MIT

/*
    PLEASE NOTE: This example is used for demonstration purposes only, and has
    not been audited. Please use for inspiration only.
*/

pragma solidity 0.6.9;

import "../erc1820/ERC1820Client.sol";
import "../erc1820/ERC1820Implementer.sol";


// Define the methods on Amp that the ExampleCollateralManager contract needs
// to interact with.
interface IAmp {
    function balanceOf(address) external returns (uint256);

    function totalBalanceOf(address) external returns (uint256);

    function registerCollateralManager() external;

    function authorizeOperator(address) external;

    function authorizeOperatorByPartition(bytes32, address) external;

    function operatorTransferByPartition(
        bytes32 _partition,
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data,
        bytes calldata _operatorData
    ) external returns (bytes32);
}


// ExampleCollateralManager is used to demostrate common use cases for Amp and
// collateral managers, including:
// - Supplying collateral
// - Withdrawing collateral
// - The collateral manager consuming collateral
// - The collateral manager rewarding collateral to suppliers
// This is a simple example, but demonstrates the power of the token transfer
// hooks that are built into Amp. They allow the collateral manager to define
// valid parameters and conditions for transfers, and store and update state
// specific to it's use cases.
//
// Note that while this collateral manager uses a "one big pool" strategy, and
// therefore could use the Collateral Pool partion strategy, this shows that
// an implmentation does not have to.
contract ExampleCollateralManager is ERC1820Implementer, ERC1820Client {
    string internal constant AMP_TOKENS_RECIPIENT = "AmpTokensRecipient";
    string internal constant AMP_TOKENS_SENDER = "AmpTokensSender";

    bytes2 internal constant VALID_DATA = 0x1111;

    bytes2 constant FLAG_CLAIM_REWARDS = 0xbaba;

    address owner;

    bytes32 badPartition = 0x000000000000000000000000000000000000000000000000000000000000dEaD;
    bytes32 collateralPartition = 0x0000000000000000000000000000000000000000000000000000000000001111;
    bytes32 consumePartition = 0x0000000000000000000000000000000000000000000000000000000000002222;

    mapping(address => uint256) _supplyOf;

    mapping(address => uint256) _rewardsOf;

    mapping(address => uint256) _consumedFor;

    IAmp amp;

    event GenericReceive(address from, uint256 value);

    event UninterestingTransferFrom(address to, uint256 value);

    event Supply(
        address supplier,
        uint256 value,
        uint256 holderBalance,
        uint256 poolBalance,
        bytes data
    );

    event Withdraw(address supplier, uint256 value, bytes data);

    event Reward(address supplier, uint256 value, bytes data);

    event Consume(address supplier, uint256 value, bytes data);

    constructor(address _amp) public {
        // Register as handler for self for AMP_TOKENS_RECIPIENT
        ERC1820Client.setInterfaceImplementation(AMP_TOKENS_RECIPIENT, address(this));
        ERC1820Implementer._setInterface(AMP_TOKENS_RECIPIENT);

        ERC1820Client.setInterfaceImplementation(AMP_TOKENS_SENDER, address(this));
        ERC1820Implementer._setInterface(AMP_TOKENS_SENDER);

        owner = msg.sender;

        amp = IAmp(_amp);
        amp.registerCollateralManager();
        amp.authorizeOperator(owner);
    }

    function supplyOf(address _supplier) external view returns (uint256) {
        return _supplyOf[_supplier];
    }

    function rewardsOf(address _supplier) external view returns (uint256) {
        return _rewardsOf[_supplier];
    }

    function tokensToTransfer(
        bytes4, /* _functionSig */
        bytes32 _fromPartition,
        address _operator,
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data,
        bytes calldata _operatorData
    ) external {
        // We only care about transferring from the collateral partition
        if (_fromPartition != collateralPartition) {
            emit UninterestingTransferFrom(_from, _value);
            return;
        }

        // Add this line to bypass the operator data check when this hook would
        // be invoked due to a transfer initiated by the contract's owner
        if (_operator == owner) {
            if (_to == address(this)) {
                address supplier = _getSupplierFromData(_operatorData);
                _execConsume(supplier, _value, _data);
            }
            return;
        }

        if (_rewardsOf[_to] > 0) {
            _execWithdrawalReentrance(
                _operator,
                _from,
                _to,
                _value,
                _data,
                _operatorData
            );
        } else {
            // If we have reached here, we are attempting a withdraw
            _execWithdrawal(_operator, _from, _to, _value, _data, _operatorData);
        }
    }

    function canReceive(
        bytes4 _functionSig,
        bytes32 _toPartition,
        address _operator,
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data,
        bytes calldata _operatorData
    ) external view returns (bool) {
        return
            _canReceive(
                _functionSig,
                _toPartition,
                _operator,
                _from,
                _to,
                _value,
                _data,
                _operatorData
            );
    }

    function tokensReceived(
        bytes4 _functionSig,
        bytes32 _toPartition,
        address _operator,
        address _from,
        address _to,
        uint256 _value,
        bytes calldata _data,
        bytes calldata _operatorData
    ) external {
        require(
            _canReceive(
                _functionSig,
                _toPartition,
                _operator,
                _from,
                _to,
                _value,
                _data,
                _operatorData
            ),
            "Invalid transfer to pool: Can't receive"
        );

        // If not sent to the default partition, then who cares.
        if (_toPartition != collateralPartition) {
            emit GenericReceive(_from, _value);
            return;
        }

        // You can also use interesting semantics like accepting a 0 value transfer
        // in conjunction with data or operator data to drive operations on chain.
        if (_value == 0) {
            // i.e. if the supplier has included the "claim rewards" flag, they
            // could be requesting the application of some reward to their
            // supplied balance.
            bytes memory operatorData = _operatorData;
            bytes32 flag;
            assembly {
                flag := mload(add(operatorData, 32))
            }
            if (bytes2(flag) == FLAG_CLAIM_REWARDS) {
                _execApplyRewards(_from);
            } else {
                // Or maybe the semantics mean that some event should be created
                // for an off chain listener to process.
                _execSendMessageOffChain(_from, _data, _operatorData);
            }

            return;
        }

        // If the tokens are coming from a partition on this contract, then the
        // tokens are being transferred to the pool as a reward for a supplier.
        // Use the operator data to find out who they are for.
        if (_from == address(this)) {
            address supplier = _getSupplierFromData(_operatorData);
            _execReward(supplier, _value, _data);
            return;
        } else {
            // Otherwise it is just a regular supply from a token holder.
            _execSupply(
                _toPartition,
                _operator,
                _from,
                _to,
                _value,
                _data,
                _operatorData
            );
        }
    }

    function _canReceive(
        bytes4, /* functionSig */
        bytes32 _toPartition,
        address, /* operator */
        address, /* from */
        address, /* to */
        uint256, /* value */
        bytes memory, /* data */
        bytes memory /* operatorData */
    ) internal view returns (bool) {
        // You can enforce that the tokens cannot be sent to a certain partition
        return _toPartition != badPartition;
    }

    function _execSupply(
        bytes32, /* _fromPartition */
        address, /* operator */
        address _from,
        address, /* to */
        uint256 _value,
        bytes memory _data,
        bytes memory /* _operatorData */
    ) internal {
        address supplier = _from;

        _supplyOf[supplier] += _value;

        // Give the supplier permission to "withdraw"
        amp.authorizeOperatorByPartition(collateralPartition, supplier);

        uint256 holderBalance = amp.totalBalanceOf(supplier);
        uint256 poolBalance = amp.totalBalanceOf(address(this));

        emit Supply(supplier, _value, holderBalance, poolBalance, _data);
    }

    function _execSupplyReentrance(
        bytes32, /* _fromPartition */
        address, /* operator */
        address _from,
        address, /* to */
        uint256 _value,
        bytes memory _data,
        bytes memory /* _operatorData */
    ) internal {
        uint256 holderBalance = amp.totalBalanceOf(_from);
        uint256 poolBalance = amp.totalBalanceOf(address(this));

        _supplyOf[_from] += _value;

        emit Supply(_from, _value, holderBalance, poolBalance, _data);

        // Simulate reentry
        if (false && _supplyOf[_from] == _value) {
            amp.operatorTransferByPartition(0x0, _from, address(this), _value, _data, "");
        }

        // Give them permission to "withdraw"
        amp.authorizeOperatorByPartition(collateralPartition, _from);
    }

    // A hook that can be called when a collateral supplier wants to withdraw
    // their collateral
    function _execWithdrawal(
        address _operator,
        address, /* _from */
        address _to,
        uint256 _value,
        bytes memory _data,
        bytes memory _operatorData
    ) internal {
        address supplier = _to;
        require(
            _supplyOf[supplier] >= _value,
            "_execWithdrawal: Supplier does not have enough to withdraw"
        );

        bytes32 proof;
        assembly {
            proof := mload(add(_operatorData, 32))
        }
        // Use data (could come offchain, for example) to gaurd the withdraw
        require(bytes2(proof) == VALID_DATA, "_execWithdrawal: Invalid data provided");

        _supplyOf[supplier] -= _value;

        emit Withdraw(_operator, _value, _data);
    }

    function _execWithdrawalReentrance(
        address _operator,
        address, /* _from */
        address _to,
        uint256 _value,
        bytes memory _data,
        bytes memory _operatorData
    ) internal {
        address supplier = _to;
        require(
            _supplyOf[supplier] >= _value,
            "_execWithdrawalReentrance: Supplier does not have enough to withdraw"
        );

        bytes32 proof;
        assembly {
            proof := mload(add(_operatorData, 32))
        }
        require(
            bytes2(proof) == VALID_DATA,
            "_execWithdrawalReentrance: Invalid data provided"
        );

        _supplyOf[supplier] -= _value;

        // Call back into the Amp contract to perform another transfer to
        // withdrawal all of the user's rewards, if present.
        if (_rewardsOf[supplier] > 0) {
            uint256 rewards = _rewardsOf[supplier];
            _execApplyRewards(supplier);
            amp.operatorTransferByPartition(
                collateralPartition,
                address(this),
                _to,
                rewards,
                _data,
                _operatorData
            );
        }

        emit Withdraw(_operator, _value, _data);
    }

    function _execConsume(
        address _supplier,
        uint256 _value,
        bytes memory _data
    ) internal {
        _supplyOf[_supplier] -= _value;
        emit Consume(_supplier, _value, _data);
    }

    function _execReward(
        address _supplier,
        uint256 _value,
        bytes memory _data
    ) internal {
        _rewardsOf[_supplier] += _value;
        emit Reward(_supplier, _value, _data);

        amp.authorizeOperatorByPartition(collateralPartition, _supplier);
    }

    event RewardsApplied(address supplier, uint256 value);

    function _execApplyRewards(address _supplier) internal {
        uint256 rewards = _rewardsOf[_supplier];
        require(rewards > 0, "Supplier has no rewards");

        _supplyOf[_supplier] += rewards;
        _rewardsOf[_supplier] = 0;

        emit RewardsApplied(_supplier, rewards);
    }

    event SendMessageToOffchain(address from, bytes data, bytes operatorData);

    function _execSendMessageOffChain(
        address _from,
        bytes memory _data,
        bytes memory _operatorData
    ) internal {
        emit SendMessageToOffchain(_from, _data, _operatorData);
    }

    function _getSupplierFromData(bytes memory _data) internal pure returns (address) {
        bytes32 supplierPart;
        assembly {
            supplierPart := mload(add(_data, 32))
        }
        address supplier = address(uint160(bytes20(supplierPart)));
        return supplier;
    }
}
