// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./utils/Common.sol";
import "./utils/ERC1155Base.sol";

import "./interface/IERC1155TokenReceiver.sol";

import "./CashMarket.sol";
//SWC-135-Code With No Effects:L10
/**
 * @notice Implements the ERC1155 token standard for transferring fCash tokens within Notional. ERC1155 ids
 * encode an identifier that represents assets that are fungible with each other. For example, two fCash tokens
 * that asset in the same market and mature at the same time are fungible with each other and therefore will have the
 * same id. `CASH_PAYER` tokens are not transferrable because they have negative value.
 */
contract ERC1155Token is ERC1155Base {

    /**
     * @notice Transfers tokens between from and to addresses.
     * @dev - INVALID_ADDRESS: destination address cannot be 0
     *  - INTEGER_OVERFLOW: value cannot overflow uint128
     *  - CANNOT_TRANSFER_PAYER: cannot transfer assets that confer obligations
     *  - CANNOT_TRANSFER_MATURED_ASSET: cannot transfer asset that has matured
     *  - INSUFFICIENT_BALANCE: from account does not have sufficient tokens
     *  - ERC1155_NOT_ACCEPTED: to contract must accept the transfer
     * @param from Source address
     * @param to Target address
     * @param id ID of the token type
     * @param value Transfer amount
     * @param data Additional data with no specified format, unused by this contract but forwarded unaltered
     * to the ERC1155TokenReceiver.
     */
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external override {
        _transfer(from, to, id, value);
        emit TransferSingle(msg.sender, from, to, id, value);

        // If code size > 0 call onERC1155received
        uint256 codeSize;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            codeSize := extcodesize(to)
        }
        if (codeSize > 0) {
            require(
                IERC1155TokenReceiver(to).onERC1155Received(msg.sender, from, id, value, data) == ERC1155_ACCEPTED,
                $$(ErrorCode(ERC1155_NOT_ACCEPTED))
            );
        }
    }

    /**
     * @notice Transfers tokens between from and to addresses in batch.
     * @dev - INVALID_ADDRESS: destination address cannot be 0
     *  - INTEGER_OVERFLOW: value cannot overflow uint128
     *  - CANNOT_TRANSFER_PAYER: cannot transfer assets that confer obligations
     *  - CANNOT_TRANSFER_MATURED_ASSET: cannot transfer asset that has matured
     *  - INSUFFICIENT_BALANCE: from account does not have sufficient tokens
     *  - ERC1155_NOT_ACCEPTED: to contract must accept the transfer
     * @param from Source address
     * @param to Target address
     * @param ids IDs of each token type (order and length must match _values array)
     * @param values Transfer amounts per token type (order and length must match _ids array)
     * @param data Additional data with no specified format, unused by this contract but forwarded unaltered
     * to the ERC1155TokenReceiver.
     */
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external override {
        for (uint256 i; i < ids.length; i++) {
            _transfer(from, to, ids[i], values[i]);
        }

        emit TransferBatch(msg.sender, from, to, ids, values);

        // If code size > 0 call onERC1155received
        uint256 codeSize;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            codeSize := extcodesize(to)
        }
        if (codeSize > 0) {
            require(
                IERC1155TokenReceiver(to).onERC1155BatchReceived(msg.sender, from, ids, values, data) ==
                    ERC1155_BATCH_ACCEPTED,
                $$(ErrorCode(ERC1155_NOT_ACCEPTED))
            );
        }
    }

    /**
     * Internal method for validating and updating state within a transfer.
     * @dev batch updates can be made a lot more efficient by not looping through this
     * code and updating storage on each loop, we can do it in memory and then flush to
     * storage just once.
     *
     * @param from the token holder
     * @param to the new token holder
     * @param id the token id
     * @param _value the notional amount to transfer
     */
    function _transfer(
        address from,
        address to,
        uint256 id,
        uint256 _value
    ) internal {
        require(to != address(0), $$(ErrorCode(INVALID_ADDRESS)));
        uint128 value = uint128(_value);
        require(uint256(value) == _value, $$(ErrorCode(INTEGER_OVERFLOW)));
        require(msg.sender == from || isApprovedForAll(from, msg.sender), $$(ErrorCode(UNAUTHORIZED_CALLER)));

        bytes1 assetType = Common.getAssetType(id);
        // Transfers can only be entitlements to receive which are a net benefit.
        require(Common.isReceiver(assetType), $$(ErrorCode(CANNOT_TRANSFER_PAYER)));

        (uint8 cashGroupId, uint16 instrumentId, uint32 maturity) = Common.decodeAssetId(id);
        require(maturity > block.timestamp, $$(ErrorCode(CANNOT_TRANSFER_MATURED_ASSET)));

        Portfolios().transferAccountAsset(
            from,
            to,
            assetType,
            cashGroupId,
            instrumentId,
            maturity,
            value
        );
    }
}
