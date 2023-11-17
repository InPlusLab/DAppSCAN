/*
 * Hubii Nahmii
 *
 * Compliant with the Hubii Nahmii specification v0.12.
 *
 * Copyright (C) 2017-2018 Hubii AS
 */

pragma solidity ^0.4.25;
pragma experimental ABIEncoderV2;

import {SafeMathIntLib} from "./SafeMathIntLib.sol";
import {SafeMathUintLib} from "./SafeMathUintLib.sol";
import {Challenge} from "./Challenge.sol";
import {Validatable} from "./Validatable.sol";
import {Ownable} from "./Ownable.sol";
import {NahmiiTypesLib} from "./NahmiiTypesLib.sol";

/**
 * @title CancelOrdersChallenge
 * @notice Where orders are cancelled and cancellations challenged
 */
contract CancelOrdersChallenge is Ownable, Challenge, Validatable {
    using SafeMathIntLib for int256;
    using SafeMathUintLib for uint256;

    //
    // Variables
    // -----------------------------------------------------------------------------------------------------------------
    address[] public cancellingWallets;

    mapping(address => mapping(bytes32 => bool)) public walletOrderOperatorHashCancelledMap;

    mapping(address => bytes32[]) public walletCancelledOrderOperatorHashes;
    mapping(address => mapping(bytes32 => uint256)) public walletCancelledOrderOperatorHashIndexMap;

    mapping(address => uint256) public walletOrderCancelledTimeoutMap;

    //
    // Events
    // -----------------------------------------------------------------------------------------------------------------
    event CancelOrdersEvent(bytes32[] orderOperatorHashes, address wallet);
    event ChallengeEvent(bytes32 orderOperatorHash, bytes32 tradeHash, address wallet);

    //
    // Constructor
    // -----------------------------------------------------------------------------------------------------------------
    constructor(address deployer) Ownable(deployer) public {
    }

    //
    // Functions
    // -----------------------------------------------------------------------------------------------------------------
    /// @notice Get count of wallets that have cancelled orders
    /// @return The count of cancelling wallets
    function cancellingWalletsCount()
    public
    view
    returns (uint256)
    {
        return cancellingWallets.length;
    }

    /// @notice Get count of cancelled orders for given wallet
    /// @param wallet The wallet for which to return the count of cancelled orders
    /// @return The count of cancelled orders
    function cancelledOrdersCount(address wallet)
    public
    view
    returns (uint256)
    {
        uint256 count = 0;
        for (uint256 i = 0; i < walletCancelledOrderOperatorHashes[wallet].length; i++) {
            bytes32 operatorHash = walletCancelledOrderOperatorHashes[wallet][i];
            if (walletOrderOperatorHashCancelledMap[wallet][operatorHash])
                count++;
        }
        return count;
    }

    /// @notice Get wallets cancelled status of order
    /// @param wallet The ordering wallet
    /// @param orderHash The (operator) hash of the order
    /// @return true if order is cancelled, else false
    function isOrderCancelled(address wallet, bytes32 orderHash)
    public
    view
    returns (bool)
    {
        return walletOrderOperatorHashCancelledMap[wallet][orderHash];
    }

    /// @notice Get cancelled order hashes for given wallet in the given index range
    /// @param wallet The wallet for which to return the nonces of cancelled orders
    /// @param low The lower inclusive index from which to extract orders
    /// @param up The upper inclusive index from which to extract orders
    /// @return The array of cancelled operator hashes
    function cancelledOrderHashesByIndices(address wallet, uint256 low, uint256 up)
    public
    view
    returns (bytes32[])
    {
        require(0 < walletCancelledOrderOperatorHashes[wallet].length);
        require(low <= up);

        up = up > walletCancelledOrderOperatorHashes[wallet].length - 1 ? walletCancelledOrderOperatorHashes[wallet].length - 1 : up;
        bytes32[] memory hashes = new bytes32[](up - low + 1);
        for (uint256 i = low; i <= up; i++)
            hashes[i - low] = walletCancelledOrderOperatorHashes[wallet][i];
        return hashes;
    }

    /// @notice Cancel orders of msg.sender
    /// @param orders The orders to cancel
    function cancelOrders(NahmiiTypesLib.Order[] orders)
    public
    onlyOperationalModeNormal
    {
        for (uint256 i = 0; i < orders.length; i++) {
            require(msg.sender == orders[i].wallet);
            require(validator.isGenuineOrderSeals(orders[i]));

            if (0 == walletCancelledOrderOperatorHashes[msg.sender].length)
                cancellingWallets.push(msg.sender);

            walletOrderOperatorHashCancelledMap[msg.sender][orders[i].seals.operator.hash] = true;
            walletCancelledOrderOperatorHashes[msg.sender].push(orders[i].seals.operator.hash);
            walletCancelledOrderOperatorHashIndexMap[msg.sender][orders[i].seals.operator.hash] = walletCancelledOrderOperatorHashes[msg.sender].length - 1;
        }

        walletOrderCancelledTimeoutMap[msg.sender] = block.timestamp.add(configuration.cancelOrderChallengeTimeout());

        emit CancelOrdersEvent(orderOperatorHashes(orders), msg.sender);
    }

    /// @notice Challenge cancelled order
    /// @param trade The trade that challenges a cancelled order
    /// @param wallet The address of the concerned wallet
    function challenge(NahmiiTypesLib.Trade trade, address wallet)
    public
    onlyOperationalModeNormal
    onlySealedTrade(trade)
    {
        require(block.timestamp < walletOrderCancelledTimeoutMap[wallet]);

        bytes32 tradeOrderOperatorHash = (
        wallet == trade.buyer.wallet ?
        trade.buyer.order.hashes.operator :
        trade.seller.order.hashes.operator
        );

        require(walletOrderOperatorHashCancelledMap[wallet][tradeOrderOperatorHash]);

        walletOrderOperatorHashCancelledMap[wallet][tradeOrderOperatorHash] = false;

        emit ChallengeEvent(tradeOrderOperatorHash, trade.seal.hash, msg.sender);
    }

    /// @notice Get current phase of a wallets cancelled order challenge
    /// @param wallet The address of wallet for which the cancelled order challenge phase is returned
    /// @return The challenge phase
    function challengePhase(address wallet)
    public
    view
    returns (NahmiiTypesLib.ChallengePhase)
    {
        if (0 < walletCancelledOrderOperatorHashes[wallet].length && block.timestamp < walletOrderCancelledTimeoutMap[wallet])
            return NahmiiTypesLib.ChallengePhase.Dispute;
        else
            return NahmiiTypesLib.ChallengePhase.Closed;
    }

    function orderOperatorHashes(NahmiiTypesLib.Order[] orders)
    private
    pure
    returns (bytes32[])
    {
        bytes32[] memory operatorHashes = new bytes32[](orders.length);
        for (uint256 i = 0; i < orders.length; i++)
            operatorHashes[i] = orders[i].seals.operator.hash;
        return operatorHashes;
    }
}