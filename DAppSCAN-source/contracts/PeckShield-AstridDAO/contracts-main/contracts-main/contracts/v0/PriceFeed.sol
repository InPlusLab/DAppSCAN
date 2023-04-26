// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Interfaces/IPriceFeed.sol";
import "../Interfaces/ITellorCaller.sol";
import "../Dependencies/AggregatorV3Interface.sol";
import "../Dependencies/SafeMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/BaseMath.sol";
import "../Dependencies/AstridMath.sol";
import "../Dependencies/console.sol";

import "./Interfaces/IDIAOracleV2.sol";

// This is a PriceFeed based on DiaOracleV2.
// See https://docs.diadata.org/documentation/oracle-documentation/access-the-oracle.

/*
 * Oracle Addresses:
 * ETH: 0xa93546947f3015c986695750b8bbEa8e26D65856
 *
 * Testnets:
 * Shiden: 0xCe784F99f87dBa11E0906e2fE954b08a8cc9815d
 * Shibuya: 0x1232acd632dd75f874e357c77295da3f5cd7733e
 *
 * Our deployed:
 * Shibuya: 0xA0A64Dd853594BB6bFFE109F41bd23d7ab2d4f20
 */

contract PriceFeed is Ownable, CheckContract, BaseMath, IPriceFeed {
    using SafeMath for uint256;

    string constant public NAME = "PriceFeed";
    // Note: based on https://etherscan.io/address/0xa93546947f3015c986695750b8bbea8e26d65856#events
    // the key should be a token/fiat pair.
    string constant public COL_KEY = "ASTR/USD";

    // Deduced values. Please verify.
    uint constant public DIA_PRICE_UNIT = 1e8;
    uint constant public TOKEN_BASE_UNIT = 1e18;
    uint constant public DIA_PRICE_SCALING_FACTOR = TOKEN_BASE_UNIT / DIA_PRICE_UNIT;

    IDIAOracleV2 public diaOracle;

    uint public lastFetchedPrice;  // Note: we have scaled it to 1e18 (Wei as unit)
    uint public lastFetchedTimestamp;  // Note: in seconds

    constructor(address _diaOracleV2Address)
    Ownable()
    {
        checkContract(_diaOracleV2Address);
        diaOracle = IDIAOracleV2(_diaOracleV2Address);
    }

    function setOracleAddress(address _newDiaOracleV2Address) public onlyOwner {
        checkContract(_newDiaOracleV2Address);
        diaOracle = IDIAOracleV2(_newDiaOracleV2Address);
    }

    function fetchCachedPrice() external view returns (uint price, uint timestamp) {
        require(lastFetchedTimestamp > 0, "PriceFeed: no cached price yet");
        price = lastFetchedPrice;
        timestamp = lastFetchedTimestamp;
    }

    function fetchPrice() public override returns (uint) {
        // Note that price fetched by DIA is NOT denoted by Wei.
        (uint diaLastFetchedPrice, uint diaLastFetchedTimestamp) = diaOracle.getValue(COL_KEY);
        lastFetchedPrice = diaLastFetchedPrice * DIA_PRICE_SCALING_FACTOR;
        lastFetchedTimestamp = diaLastFetchedTimestamp;
        return lastFetchedPrice;
    }
}