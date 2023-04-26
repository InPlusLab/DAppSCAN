//SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@maticnetwork/fx-portal/contracts/tunnel/FxBaseRootTunnel.sol";
import "../Maker/NftOwnership.sol";

/// @dev This contract lives on the L1 and allows NFT owners to register NFTs that live on the L1.
/// Once ownership is verified, it will send a message up to the contracts on the L2 specifying that
/// the NFT has been registered or unregistered.
/// This is not an upgradeable contract and should not be used with a proxy.
contract RootRegistrar is FxBaseRootTunnel {
    bytes32 public constant REGISTER = keccak256("REGISTER");
    bytes32 public constant DE_REGISTER = keccak256("DE_REGISTER");

    /// @param _checkpointManager This is a well known contract deployed by matic that is used to verify messages coming from the L2 down to L1.
    /// @param _fxRoot This is a well known contract deployed by matic that will emit the events going from L1 to L2.
    /// @dev You must call setFxChildTunnel() with the ChildRegistrar address on the L2 after deployment
    constructor(address _checkpointManager, address _fxRoot)
        FxBaseRootTunnel(_checkpointManager, _fxRoot)
    {}

    /// @dev Allows a NFT owner to register the NFT in the protocol on L1
    /// Once the ownership is verified a message will be sent to the Child contract
    /// on the L2 chain that will trigger a registration there.
    function registerNft(
        address nftContractAddress,
        uint256 nftId,
        address creatorAddress,
        uint256 creatorSaleBasisPoints,
        uint256 optionBits
    ) external {
        // Verify ownership
        require(
            NftOwnership._verifyOwnership(
                nftContractAddress,
                nftId,
                msg.sender
            ),
            "NFT not owned"
        );

        // REGISTER, encode(owner, chainId, nftContractAddress, nftId, creatorAddress, optionBits)
        bytes memory message = abi.encode(
            REGISTER,
            abi.encode(
                msg.sender,
                block.chainid,
                nftContractAddress,
                nftId,
                creatorAddress,
                creatorSaleBasisPoints,
                optionBits
            )
        );
        _sendMessageToChild(message);
    }

    /// @dev Allows a NFT owner to de-register the NFT in the protocol on L1
    /// Once the ownership is verified a message will be sent to the Child contract
    /// on the L2 chain that will trigger a desgregistration there.
    function deRegisterNft(address nftContractAddress, uint256 nftId) external {
        // Verify ownership
        require(
            NftOwnership._verifyOwnership(
                nftContractAddress,
                nftId,
                msg.sender
            ),
            "NFT not owned"
        );

        // DERegister, encode(address owner, uint256 chainId, address nftContractAddress, uint256 nftId)
        bytes memory message = abi.encode(
            DE_REGISTER,
            abi.encode(msg.sender, block.chainid, nftContractAddress, nftId)
        );
        _sendMessageToChild(message);
    }

    /// @dev NOOP - No messages come from L2 down to L1
    function _processMessageFromChild(bytes memory data) internal override {}
}
