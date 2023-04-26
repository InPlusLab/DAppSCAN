// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Portfolio is Initializable, AccessControlUpgradeable, UUPSUpgradeable {
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    uint256 public constant TOTAL_WEIGHT = 100000; // 100000 ~ 100%

    mapping(address => uint256) public assetInfoPositions;
    AssetInfo[] public assetInfos;
    mapping(address => uint256) public assetWeightPositions;
    AssetWeight[] public assetWeights;

    event UpdatedAssetWeight(
        uint256 index,
        address asset,
        uint256 minWeight,
        uint256 targetWeight,
        uint256 maxWeight
    );
    event UpdatedAssetInfo(uint256 index, address asset, address priceGetter);

    struct AssetWeight {
        address asset;
        uint256 minWeight;
        uint256 targetWeight;
        uint256 maxWeight;
    }

    struct AssetInfo {
        address asset;
        address priceGetter;
    }

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Restricted to admins");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize() initializer public {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPGRADER_ROLE, msg.sender);
    }

    function _authorizeUpgrade(address newImplementation)
    internal
    onlyRole(UPGRADER_ROLE)
    override
    {}

    function setAssetInfos(AssetInfo[] calldata _assetInfos) external onlyAdmin {
        for (uint8 i = 0; i < _assetInfos.length; i++) {
            _addAssetInfoAt(_assetInfos[i], i);
        }
        // truncate array if needed
        if (assetInfos.length > _assetInfos.length) {
            uint256 removeCount = assetInfos.length - _assetInfos.length;
            for (uint8 i = 0; i < removeCount; i++) {
                //TODO: do we need remove from mapping?
                assetInfos.pop();
            }
        }
    }

    function addAssetInfoAt(AssetInfo calldata assetInfo, uint256 index) external onlyAdmin {
        _addAssetInfoAt(assetInfo, index);
    }

    function _addAssetInfoAt(AssetInfo calldata assetInfo, uint256 index) internal {
        uint256 currentlength = assetInfos.length;
        // expand array id needed
        if (currentlength == 0 || currentlength - 1 < index) {
            uint256 additionalCount = index - currentlength + 1;
            for (uint8 i = 0; i < additionalCount; i++) {
                assetInfos.push();
            }
        }
        assetInfos[index] = assetInfo;
        assetInfoPositions[assetInfo.asset] = index;
        emit UpdatedAssetInfo(index, assetInfo.asset, assetInfo.priceGetter);
    }

    function setWeights(AssetWeight[] calldata _assetWeights) external onlyAdmin {
        uint256 totalTarget = 0;
        for (uint8 i = 0; i < _assetWeights.length; i++) {
            AssetWeight memory assetWeight = _assetWeights[i];
            require(assetWeight.asset != address(0), "weight without asset");
            require(
                assetWeight.minWeight <= assetWeight.targetWeight,
                "minWeight shouldn't higher than targetWeight"
            );
            require(
                assetWeight.targetWeight <= assetWeight.maxWeight,
                "targetWeight shouldn't higher than maxWeight"
            );
            totalTarget += assetWeight.targetWeight;
        }
        require(totalTarget == TOTAL_WEIGHT, "Total target should equal to TOTAL_WEIGHT");

        for (uint8 i = 0; i < _assetWeights.length; i++) {
            _addWeightAt(_assetWeights[i], i);
            assetWeightPositions[assetWeights[i].asset] = i;
        }

        // truncate if need
        if (assetWeights.length > _assetWeights.length) {
            uint256 removeCount = assetWeights.length - _assetWeights.length;
            for (uint8 i = 0; i < removeCount; i++) {
                assetWeights.pop();
            }
        }
    }

    function _addWeightAt(AssetWeight memory assetWeight, uint256 index) internal {
        uint256 currentLength = assetWeights.length;
        // expand if need
        if (currentLength == 0 || currentLength - 1 < index) {
            uint256 additionalCount = index - currentLength + 1;
            for (uint8 i = 0; i < additionalCount; i++) {
                assetWeights.push();
            }
        }
        assetWeights[index] = assetWeight;
        emit UpdatedAssetWeight(
            index,
            assetWeight.asset,
            assetWeight.minWeight,
            assetWeight.targetWeight,
            assetWeight.maxWeight
        );
    }

    function getAssetInfo(address asset) external view returns (AssetInfo memory) {
        return assetInfos[assetInfoPositions[asset]];
    }

    function getAllAssetInfos() external view returns (AssetInfo[] memory) {
        return assetInfos;
    }

    function getAssetWeight(address asset) external view returns (AssetWeight memory) {
        return assetWeights[assetWeightPositions[asset]];
    }

    function getAllAssetWeights() external view returns (AssetWeight[] memory) {
        return assetWeights;
    }
}
