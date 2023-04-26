/*

  Copyright 2019 ZeroEx Intl.

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.

*/

pragma solidity ^0.5.16;
pragma experimental ABIEncoderV2;

import "@0x/contracts-utils/contracts/src/LibBytes.sol";
import "@0x/contracts-asset-proxy/contracts/src/interfaces/IAssetData.sol";


library LibAssetData {

    using LibBytes for bytes;

    /// @dev Decode AssetProxy identifier
    /// @param assetData AssetProxy-compliant asset data describing an ERC-20, ERC-721, ERC1155, or MultiAsset asset.
    /// @return The AssetProxy identifier
    function decodeAssetProxyId(bytes memory assetData)
        public
        pure
        returns (
            bytes4 assetProxyId
        )
    {
        assetProxyId = assetData.readBytes4(0);

        require(
            assetProxyId == IAssetData(address(0)).ERC20Token.selector ||
            assetProxyId == IAssetData(address(0)).ERC721Token.selector ||
            assetProxyId == IAssetData(address(0)).ERC1155Assets.selector ||
            assetProxyId == IAssetData(address(0)).MultiAsset.selector ||
            assetProxyId == IAssetData(address(0)).StaticCall.selector,
            "WRONG_PROXY_ID"
        );
        return assetProxyId;
    }

    /// @dev Encode ERC-20 asset data into the format described in the AssetProxy contract specification.
    /// @param tokenAddress The address of the ERC-20 contract hosting the asset to be traded.
    /// @return AssetProxy-compliant data describing the asset.
    function encodeERC20AssetData(address tokenAddress)
        public
        pure
        returns (bytes memory assetData)
    {
        assetData = abi.encodeWithSelector(IAssetData(address(0)).ERC20Token.selector, tokenAddress);
        return assetData;
    }

    /// @dev Decode ERC-20 asset data from the format described in the AssetProxy contract specification.
    /// @param assetData AssetProxy-compliant asset data describing an ERC-20 asset.
    /// @return The AssetProxy identifier, and the address of the ERC-20
    /// contract hosting this asset.
    function decodeERC20AssetData(bytes memory assetData)
        public
        pure
        returns (
            bytes4 assetProxyId,
            address tokenAddress
        )
    {
        assetProxyId = assetData.readBytes4(0);

        require(
            assetProxyId == IAssetData(address(0)).ERC20Token.selector,
            "WRONG_PROXY_ID"
        );

        tokenAddress = assetData.readAddress(16);
        return (assetProxyId, tokenAddress);
    }

    /// @dev Encode ERC-721 asset data into the format described in the AssetProxy specification.
    /// @param tokenAddress The address of the ERC-721 contract hosting the asset to be traded.
    /// @param tokenId The identifier of the specific asset to be traded.
    /// @return AssetProxy-compliant asset data describing the asset.
    function encodeERC721AssetData(address tokenAddress, uint256 tokenId)
        public
        pure
        returns (bytes memory assetData)
    {
        assetData = abi.encodeWithSelector(
            IAssetData(address(0)).ERC721Token.selector,
            tokenAddress,
            tokenId
        );
        return assetData;
    }

    /// @dev Decode ERC-721 asset data from the format described in the AssetProxy contract specification.
    /// @param assetData AssetProxy-compliant asset data describing an ERC-721 asset.
    /// @return The ERC-721 AssetProxy identifier, the address of the ERC-721
    /// contract hosting this asset, and the identifier of the specific
    /// asset to be traded.
    function decodeERC721AssetData(bytes memory assetData)
        public
        pure
        returns (
            bytes4 assetProxyId,
            address tokenAddress,
            uint256 tokenId
        )
    {
        assetProxyId = assetData.readBytes4(0);

        require(
            assetProxyId == IAssetData(address(0)).ERC721Token.selector,
            "WRONG_PROXY_ID"
        );

        tokenAddress = assetData.readAddress(16);
        tokenId = assetData.readUint256(36);
        return (assetProxyId, tokenAddress, tokenId);
    }

    /// @dev Encode ERC-1155 asset data into the format described in the AssetProxy contract specification.
    /// @param tokenAddress The address of the ERC-1155 contract hosting the asset(s) to be traded.
    /// @param tokenIds The identifiers of the specific assets to be traded.
    /// @param tokenValues The amounts of each asset to be traded.
    /// @param callbackData Data to be passed to receiving contracts when a transfer is performed.
    /// @return AssetProxy-compliant asset data describing the set of assets.
    function encodeERC1155AssetData(
        address tokenAddress,
        uint256[] memory tokenIds,
        uint256[] memory tokenValues,
        bytes memory callbackData
    )
        public
        pure
        returns (bytes memory assetData)
    {
        assetData = abi.encodeWithSelector(
            IAssetData(address(0)).ERC1155Assets.selector,
            tokenAddress,
            tokenIds,
            tokenValues,
            callbackData
        );
        return assetData;
    }

    /// @dev Decode ERC-1155 asset data from the format described in the AssetProxy contract specification.
    /// @param assetData AssetProxy-compliant asset data describing an ERC-1155 set of assets.
    /// @return The ERC-1155 AssetProxy identifier, the address of the ERC-1155
    /// contract hosting the assets, an array of the identifiers of the
    /// assets to be traded, an array of asset amounts to be traded, and
    /// callback data.  Each element of the arrays corresponds to the
    /// same-indexed element of the other array.  Return values specified as
    /// `memory` are returned as pointers to locations within the memory of
    /// the input parameter `assetData`.
    function decodeERC1155AssetData(bytes memory assetData)
        public
        pure
        returns (
            bytes4 assetProxyId,
            address tokenAddress,
            uint256[] memory tokenIds,
            uint256[] memory tokenValues,
            bytes memory callbackData
        )
    {
        assetProxyId = assetData.readBytes4(0);

        require(
            assetProxyId == IAssetData(address(0)).ERC1155Assets.selector,
            "WRONG_PROXY_ID"
        );

        assembly {
            // Skip selector and length to get to the first parameter:
            assetData := add(assetData, 36)
            // Read the value of the first parameter:
            tokenAddress := mload(assetData)
            // Point to the next parameter's data:
            tokenIds := add(assetData, mload(add(assetData, 32)))
            // Point to the next parameter's data:
            tokenValues := add(assetData, mload(add(assetData, 64)))
            // Point to the next parameter's data:
            callbackData := add(assetData, mload(add(assetData, 96)))
        }

        return (
            assetProxyId,
            tokenAddress,
            tokenIds,
            tokenValues,
            callbackData
        );
    }

    /// @dev Encode data for multiple assets, per the AssetProxy contract specification.
    /// @param amounts The amounts of each asset to be traded.
    /// @param nestedAssetData AssetProxy-compliant data describing each asset to be traded.
    /// @return AssetProxy-compliant data describing the set of assets.
    function encodeMultiAssetData(uint256[] memory amounts, bytes[] memory nestedAssetData)
        public
        pure
        returns (bytes memory assetData)
    {
        assetData = abi.encodeWithSelector(
            IAssetData(address(0)).MultiAsset.selector,
            amounts,
            nestedAssetData
        );
        return assetData;
    }

    /// @dev Decode multi-asset data from the format described in the AssetProxy contract specification.
    /// @param assetData AssetProxy-compliant data describing a multi-asset basket.
    /// @return The Multi-Asset AssetProxy identifier, an array of the amounts
    /// of the assets to be traded, and an array of the
    /// AssetProxy-compliant data describing each asset to be traded.  Each
    /// element of the arrays corresponds to the same-indexed element of the other array.
    function decodeMultiAssetData(bytes memory assetData)
        public
        pure
        returns (
            bytes4 assetProxyId,
            uint256[] memory amounts,
            bytes[] memory nestedAssetData
        )
    {
        assetProxyId = assetData.readBytes4(0);

        require(
            assetProxyId == IAssetData(address(0)).MultiAsset.selector,
            "WRONG_PROXY_ID"
        );

        // solhint-disable indent
        (amounts, nestedAssetData) = abi.decode(
            assetData.slice(4, assetData.length),
            (uint256[], bytes[])
        );
        // solhint-enable indent
    }

    /// @dev Encode StaticCall asset data into the format described in the AssetProxy contract specification.
    /// @param staticCallTargetAddress Target address of StaticCall.
    /// @param staticCallData Data that will be passed to staticCallTargetAddress in the StaticCall.
    /// @param expectedReturnDataHash Expected Keccak-256 hash of the StaticCall return data.
    /// @return AssetProxy-compliant asset data describing the set of assets.
    function encodeStaticCallAssetData(
        address staticCallTargetAddress,
        bytes memory staticCallData,
        bytes32 expectedReturnDataHash
    )
        public
        pure
        returns (bytes memory assetData)
    {
        assetData = abi.encodeWithSelector(
            IAssetData(address(0)).StaticCall.selector,
            staticCallTargetAddress,
            staticCallData,
            expectedReturnDataHash
        );
        return assetData;
    }

    /// @dev Decode StaticCall asset data from the format described in the AssetProxy contract specification.
    /// @param assetData AssetProxy-compliant asset data describing a StaticCall asset
    /// @return The StaticCall AssetProxy identifier, the target address of the StaticCAll, the data to be
    /// passed to the target address, and the expected Keccak-256 hash of the static call return data.
    function decodeStaticCallAssetData(bytes memory assetData)
        public
        pure
        returns (
            bytes4 assetProxyId,
            address staticCallTargetAddress,
            bytes memory staticCallData,
            bytes32 expectedReturnDataHash
        )
    {
        assetProxyId = assetData.readBytes4(0);

        require(
            assetProxyId == IAssetData(address(0)).StaticCall.selector,
            "WRONG_PROXY_ID"
        );

        (staticCallTargetAddress, staticCallData, expectedReturnDataHash) = abi.decode(
            assetData.slice(4, assetData.length),
            (address, bytes, bytes32)
        );
    }

    /// @dev Decode ERC20Bridge asset data from the format described in the AssetProxy contract specification.
    /// @param assetData AssetProxy-compliant asset data describing an ERC20Bridge asset
    /// @return The ERC20BridgeProxy identifier, the address of the ERC20 token to transfer, the address
    /// of the bridge contract, and extra data to be passed to the bridge contract.
    function decodeERC20BridgeAssetData(bytes memory assetData)
        public
        pure
        returns (
            bytes4 assetProxyId,
            address tokenAddress,
            address bridgeAddress,
            bytes memory bridgeData
        )
    {
        assetProxyId = assetData.readBytes4(0);

        require(
            assetProxyId == IAssetData(address(0)).ERC20Bridge.selector,
            "WRONG_PROXY_ID"
        );

        (tokenAddress, bridgeAddress, bridgeData) = abi.decode(
            assetData.slice(4, assetData.length),
            (address, address, bytes)
        );
    }

    /// @dev Reverts if assetData is not of a valid format for its given proxy id.
    /// @param assetData AssetProxy compliant asset data.
    function revertIfInvalidAssetData(bytes memory assetData)
        public
        pure
    {
        bytes4 assetProxyId = assetData.readBytes4(0);

        if (assetProxyId == IAssetData(address(0)).ERC20Token.selector) {
            decodeERC20AssetData(assetData);
        } else if (assetProxyId == IAssetData(address(0)).ERC721Token.selector) {
            decodeERC721AssetData(assetData);
        } else if (assetProxyId == IAssetData(address(0)).ERC1155Assets.selector) {
            decodeERC1155AssetData(assetData);
        } else if (assetProxyId == IAssetData(address(0)).MultiAsset.selector) {
            decodeMultiAssetData(assetData);
        } else if (assetProxyId == IAssetData(address(0)).StaticCall.selector) {
            decodeStaticCallAssetData(assetData);
        } else if (assetProxyId == IAssetData(address(0)).ERC20Bridge.selector) {
            decodeERC20BridgeAssetData(assetData);
        } else {
            revert("WRONG_PROXY_ID");
        }
    }
}
