pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "../../Lib/LibEIP712.sol";

/// @title Opium.Matching.SwaprateMatch.LibSwaprateOrder contract implements EIP712 signed SwaprateOrder for Opium.Matching.SwaprateMatch
contract LibSwaprateOrder is LibEIP712 {
    /**
        Structure of order
        Description should be considered from the order signer (maker) perspective

        syntheticId - address of derivative syntheticId
        oracleId - address of derivative oracleId
        token - address of derivative margin token

        makerMarginAddress - address of token that maker is willing to pay with
        takerMarginAddress - address of token that maker is willing to receive

        makerAddress - address of maker
        takerAddress - address of counterparty (taker). If zero address, then taker could be anyone

        senderAddress - address which is allowed to settle the order on-chain. If zero address, then anyone could settle

        relayerAddress - address of the relayer fee recipient
        affiliateAddress - address of the affiliate fee recipient

        feeTokenAddress - address of token which is used for fees

        endTime - timestamp of derivative maturity

        quantity - quantity of positions maker wants to receive
        partialFill - whether maker allows partial fill of it's order

        param0...param9 - additional params to pass it to syntheticId

        relayerFee - amount of fee in feeToken that should be paid to relayer
        affiliateFee - amount of fee in feeToken that should be paid to affiliate

        nonce - unique order ID

        signature - Signature of EIP712 message. Not used in hash, but then set for order processing purposes

     */
    struct SwaprateOrder {
        address syntheticId;
        address oracleId;
        address token;

        address makerAddress;
        address takerAddress;

        address senderAddress;

        address relayerAddress;
        address affiliateAddress;

        address feeTokenAddress;

        uint256 endTime;

        uint256 quantity;
        uint256 partialFill;

        uint256 param0;
        uint256 param1;
        uint256 param2;
        uint256 param3;
        uint256 param4;
        uint256 param5;
        uint256 param6;
        uint256 param7;
        uint256 param8;
        uint256 param9;

        uint256 relayerFee;
        uint256 affiliateFee;

        uint256 nonce;

        // Not used in hash
        bytes signature;
    }

    // Calculate typehash of Order
    bytes32 constant internal EIP712_ORDER_TYPEHASH = keccak256(abi.encodePacked(
        "Order(",
        "address syntheticId,",
        "address oracleId,",
        "address token,",

        "address makerAddress,",
        "address takerAddress,",

        "address senderAddress,",

        "address relayerAddress,",
        "address affiliateAddress,",

        "address feeTokenAddress,",

        "uint256 endTime,",

        "uint256 quantity,",
        "uint256 partialFill,",

        "uint256 param0,",
        "uint256 param1,",
        "uint256 param2,",
        "uint256 param3,",
        "uint256 param4,",
        "uint256 param5,",
        "uint256 param6,",
        "uint256 param7,",
        "uint256 param8,",
        "uint256 param9,",

        "uint256 relayerFee,",
        "uint256 affiliateFee,",

        "uint256 nonce",
        ")"
    ));

    /// @notice Hashes the order
    /// @param _order SwaprateOrder Order to hash
    /// @return hash bytes32 Order hash
    function hashOrder(SwaprateOrder memory _order) internal pure returns (bytes32 hash) {
        hash = keccak256(
            abi.encodePacked(
                abi.encodePacked(
                    EIP712_ORDER_TYPEHASH,
                    uint256(_order.syntheticId),
                    uint256(_order.oracleId),
                    uint256(_order.token),

                    uint256(_order.makerAddress),
                    uint256(_order.takerAddress),

                    uint256(_order.senderAddress),

                    uint256(_order.relayerAddress),
                    uint256(_order.affiliateAddress),

                    uint256(_order.feeTokenAddress)
                ),
                abi.encodePacked(
                    _order.endTime,
                    _order.quantity,
                    _order.partialFill
                ),
                abi.encodePacked(
                    _order.param0,
                    _order.param1,
                    _order.param2,
                    _order.param3,
                    _order.param4
                ),
                abi.encodePacked(
                    _order.param5,
                    _order.param6,
                    _order.param7,
                    _order.param8,
                    _order.param9
                ),
                abi.encodePacked(
                    _order.relayerFee,
                    _order.affiliateFee,

                    _order.nonce
                )
            )
        );
    }

    /// @notice Verifies order signature
    /// @param _hash bytes32 Hash of the order
    /// @param _signature bytes Signature of the order
    /// @param _address address Address of the order signer
    /// @return bool Returns whether `_signature` is valid and was created by `_address`
    function verifySignature(bytes32 _hash, bytes memory _signature, address _address) internal view returns (bool) {
        require(_signature.length == 65, "ORDER:INVALID_SIGNATURE_LENGTH");

        bytes32 digest = hashEIP712Message(_hash);
        address recovered = retrieveAddress(digest, _signature);
        return _address == recovered;
    }

    /// @notice Helping function to recover signer address
    /// @param _hash bytes32 Hash for signature
    /// @param _signature bytes Signature
    /// @return address Returns address of signature creator
    function retrieveAddress(bytes32 _hash, bytes memory _signature) private pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        // Divide the signature in r, s and v variables
        // ecrecover takes the signature parameters, and the only way to get them
        // currently is to use assembly.
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            r := mload(add(_signature, 32))
            s := mload(add(_signature, 64))
            v := byte(0, mload(add(_signature, 96)))
        }

        // Version of signature should be 27 or 28, but 0 and 1 are also possible versions
        if (v < 27) {
            v += 27;
        }

        // If the version is correct return the signer address
        if (v != 27 && v != 28) {
            return (address(0));
        } else {
            // solium-disable-next-line arg-overflow
            return ecrecover(_hash, v, r, s);
        }
    }
}