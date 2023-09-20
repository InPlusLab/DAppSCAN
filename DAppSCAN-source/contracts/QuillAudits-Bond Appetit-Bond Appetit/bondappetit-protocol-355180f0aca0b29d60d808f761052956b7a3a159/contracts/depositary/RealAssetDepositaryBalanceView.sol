// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../utils/AccessControl.sol";
import "./IDepositaryBalanceView.sol";

contract RealAssetDepositaryBalanceView is IDepositaryBalanceView, AccessControl {
    using SafeMath for uint256;

    /// @notice Signed data of asset information.
    struct Proof {
        string data;
        string signature;
    }

    /// @notice Asset information.
    struct Asset {
        string id;
        uint256 amount;
        uint256 price;
    }

    /// @notice The number of assets in depositary.
    uint256 public maxSize;

    /// @notice Decimals balance.
    uint256 public override decimals = 6;

    /// @notice Assets list.
    Asset[] public portfolio;

    /// @dev Assets list index.
    mapping(string => uint256) internal portfolioIndex;

    /// @notice An event thats emitted when asset updated in portfolio.
    event AssetUpdated(string id, uint256 updatedAt, Proof proof);

    /// @notice An event thats emitted when asset removed from portfolio.
    event AssetRemoved(string id);

    /**
     * @param _decimals Decimals balance.
     * @param _maxSize Max number assets in depositary.
     */
    constructor(uint256 _decimals, uint256 _maxSize) public {
        decimals = _decimals;
        maxSize = _maxSize;
    }

    /**
     * @return Assets count of depositary.
     */
    function size() public view returns (uint256) {
        return portfolio.length;
    }

    /**
     * @return Assets list.
     */
    function assets() external view returns (Asset[] memory) {
        Asset[] memory result = new Asset[](size());

        for (uint256 i = 0; i < size(); i++) {
            result[i] = portfolio[i];
        }

        return result;
    }

    /**
     * @notice Update information of asset.
     * @param id Asset identificator.
     * @param amount Amount of asset.
     * @param price Cost of one asset in base currency.
     * @param updatedAt Timestamp of updated.
     * @param proofData Signed data.
     * @param proofSignature Data signature.
     */
    //  SWC-122-Lack of Proper Signature Verification: L89
    function put(
        string calldata id,
        uint256 amount,
        uint256 price,
        uint256 updatedAt,
        string calldata proofData,
        string calldata proofSignature
    ) external onlyAllowed {
        require(size() < maxSize, "RealAssetDepositaryBalanceView::put: too many assets");

        uint256 valueIndex = portfolioIndex[id];
        if (valueIndex != 0) {
            portfolio[valueIndex.sub(1)] = Asset(id, amount, price);
        } else {
            portfolio.push(Asset(id, amount, price));
            portfolioIndex[id] = size();
        }
        emit AssetUpdated(id, updatedAt, Proof(proofData, proofSignature));
    }

    /**
     * @notice Remove information of asset.
     * @param id Asset identificator.
     */
    function remove(string calldata id) external onlyAllowed {
        uint256 valueIndex = portfolioIndex[id];
        require(valueIndex != 0, "RealAssetDepositaryBalanceView::remove: asset already removed");

        uint256 toDeleteIndex = valueIndex.sub(1);
        uint256 lastIndex = size().sub(1);
        Asset memory lastValue = portfolio[lastIndex];
        portfolio[toDeleteIndex] = lastValue;
        portfolioIndex[lastValue.id] = toDeleteIndex.add(1);
        portfolio.pop();
        delete portfolioIndex[id];

        emit AssetRemoved(id);
    }

    function balance() external view override returns (uint256) {
        uint256 result;

        for (uint256 i = 0; i < size(); i++) {
            result = result.add(portfolio[i].amount.mul(portfolio[i].price));
        }

        return result;
    }
}
