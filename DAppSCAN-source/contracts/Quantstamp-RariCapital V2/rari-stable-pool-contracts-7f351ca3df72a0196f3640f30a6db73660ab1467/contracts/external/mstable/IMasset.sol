// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity 0.5.17;
pragma experimental ABIEncoderV2;

import "./MassetStructs.sol";

/**
 * @title IMasset
 * @dev   (Internal) Interface for interacting with Masset
 *        VERSION: 1.0
 *        DATE:    2020-05-05
 */
contract IMasset is MassetStructs {
    // Mint
    function mint(
        address _input,
        uint256 _inputQuantity,
        uint256 _minOutputQuantity,
        address _recipient
    ) external returns (uint256 mintOutput);

    function mintMulti(
        address[] calldata _inputs,
        uint256[] calldata _inputQuantities,
        uint256 _minOutputQuantity,
        address _recipient
    ) external returns (uint256 mintOutput);

    function getMintOutput(address _input, uint256 _inputQuantity)
        external
        view
        returns (uint256 mintOutput);

    function getMintMultiOutput(address[] calldata _inputs, uint256[] calldata _inputQuantities)
        external
        view
        returns (uint256 mintOutput);

    // Swaps
    function swap(
        address _input,
        address _output,
        uint256 _inputQuantity,
        uint256 _minOutputQuantity,
        address _recipient
    ) external returns (uint256 swapOutput);

    function getSwapOutput(
        address _input,
        address _output,
        uint256 _inputQuantity
    ) external view returns (uint256 swapOutput);

    // Redemption
    function redeem(
        address _output,
        uint256 _mAssetQuantity,
        uint256 _minOutputQuantity,
        address _recipient
    ) external returns (uint256 outputQuantity);

    function redeemMasset(
        uint256 _mAssetQuantity,
        uint256[] calldata _minOutputQuantities,
        address _recipient
    ) external returns (uint256[] memory outputQuantities);

    function redeemExactBassets(
        address[] calldata _outputs,
        uint256[] calldata _outputQuantities,
        uint256 _maxMassetQuantity,
        address _recipient
    ) external returns (uint256 mAssetRedeemed);

    function getRedeemOutput(address _output, uint256 _mAssetQuantity)
        external
        view
        returns (uint256 bAssetOutput);

    function getRedeemExactBassetsOutput(
        address[] calldata _outputs,
        uint256[] calldata _outputQuantities
    ) external view returns (uint256 mAssetAmount);

    // Views
    function getBasket() external view returns (bool, bool);

    function getBasset(address _token)
        external
        view
        returns (BassetPersonal memory personal, BassetData memory data);

    function getBassets()
        external
        view
        returns (BassetPersonal[] memory personal, BassetData[] memory data);

    function bAssetIndexes(address) external view returns (uint8);

    // SavingsManager
    function collectInterest() external returns (uint256 swapFeesGained, uint256 newSupply);

    function collectPlatformInterest()
        external
        returns (uint256 mintAmount, uint256 newSupply);

    // Admin
    function setCacheSize(uint256 _cacheSize) external;

    function upgradeForgeValidator(address _newForgeValidator) external;

    function setFees(uint256 _swapFee, uint256 _redemptionFee) external;

    function setTransferFeesFlag(address _bAsset, bool _flag) external;

    function migrateBassets(address[] calldata _bAssets, address _newIntegration) external;
}
