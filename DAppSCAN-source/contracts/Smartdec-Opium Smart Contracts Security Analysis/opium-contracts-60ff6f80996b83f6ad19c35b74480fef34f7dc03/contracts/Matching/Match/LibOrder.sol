pragma solidity ^0.5.4;
pragma experimental ABIEncoderV2;

import "../../Lib/LibEIP712.sol";

/// @title Opium.Matching.Match.LibOrder contract implements EIP712 signed Order for Opium.Matching.Match
contract LibOrder is LibEIP712 {
    /**
        Structure of order
        Description should be considered from the order signer (maker) perspective

        makerMarginAddress - address of token that maker is willing to pay with
        takerMarginAddress - address of token that maker is willing to receive

        makerAddress - address of maker
        takerAddress - address of counterparty (taker). If zero address, then taker could be anyone

        senderAddress - address which is allowed to settle the order on-chain. If zero address, then anyone could settle

        relayerAddress - address of the relayer fee recipient
        affiliateAddress - address of the affiliate fee recipient

        feeTokenAddress - address of token which is used for fees

        makerTokenId - tokenId of position, that maker is willing to pay
        makerTokenAmount - amount of position tokens that maker is willing to pay
        makerMarginAmount - amount of margin token that maker is willing to pay
        takerTokenId - tokenId of position, that maker wants to receive. Create new derivative with this tokenId in case of calling Match.create(). Swap to this tokenId in case Match.swap() is called.
        takerTokenAmount - amount of tokens that maker wants to receive
        takerMarginAmount - amount of margin that maker wants to receive

        relayerFee - amount of fee in feeToken that should be paid to relayer
        affiliateFee - amount of fee in feeToken that should be paid to affiliate

        nonce - unique order ID
        expiresAt - UNIX timestamp of order expiration. Zero for Good-Till-Cancel order

        signature - Signature of EIP712 message. Not used in hash, but then set for order processing purposes

     */
    struct Order {
        address makerMarginAddress;
        address takerMarginAddress;

        address makerAddress;
        address takerAddress;

        address senderAddress;

        address relayerAddress;
        address affiliateAddress;

        address feeTokenAddress;

        uint256 makerTokenId;
        uint256 makerTokenAmount;
        uint256 makerMarginAmount;
        uint256 takerTokenId;
        uint256 takerTokenAmount;
        uint256 takerMarginAmount;

        uint256 relayerFee;
        uint256 affiliateFee;

        uint256 nonce;
        uint256 expiresAt;

        // Not used in hash
        bytes signature;
    }

    // Calculate typehash of Order
    bytes32 constant internal EIP712_ORDER_TYPEHASH = keccak256(abi.encodePacked(
        "Order(",
        "address makerMarginAddress,",
        "address takerMarginAddress,",

        "address makerAddress,",
        "address takerAddress,",

        "address senderAddress,",

        "address relayerAddress,",
        "address affiliateAddress,",

        "address feeTokenAddress,",

        "uint256 makerTokenId,",
        "uint256 makerTokenAmount,",
        "uint256 makerMarginAmount,",
        "uint256 takerTokenId,",
        "uint256 takerTokenAmount,",
        "uint256 takerMarginAmount,",
        
        "uint256 relayerFee,",
        "uint256 affiliateFee,",

        "uint256 nonce,",
        "uint256 expiresAt",
        ")"
    ));

    /// @notice Hashes the order
    /// @param _order Order Order to hash
    /// @return hash bytes32 Order hash
    function hashOrder(Order memory _order) internal pure returns (bytes32 hash) {
        hash = keccak256(
            abi.encodePacked(
                abi.encodePacked(
                    EIP712_ORDER_TYPEHASH,
                    uint256(_order.makerMarginAddress),
                    uint256(_order.takerMarginAddress),

                    uint256(_order.makerAddress),
                    uint256(_order.takerAddress),

                    uint256(_order.senderAddress),

                    uint256(_order.relayerAddress),
                    uint256(_order.affiliateAddress),

                    uint256(_order.feeTokenAddress)
                ),
                abi.encodePacked(
                    _order.makerTokenId,
                    _order.makerTokenAmount,
                    _order.makerMarginAmount,
                    _order.takerTokenId,
                    _order.takerTokenAmount,
                    _order.takerMarginAmount
                ),
                abi.encodePacked(
                    _order.relayerFee,
                    _order.affiliateFee,

                    _order.nonce,
                    _order.expiresAt
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