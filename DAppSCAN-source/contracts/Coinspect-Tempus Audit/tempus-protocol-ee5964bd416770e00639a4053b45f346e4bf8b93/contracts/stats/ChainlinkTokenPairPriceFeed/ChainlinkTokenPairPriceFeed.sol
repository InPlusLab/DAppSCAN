// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.6;

import "./IChainlinkAggregator.sol";
import "./IENS.sol";
import "../ITokenPairPriceFeed.sol";

abstract contract ChainlinkTokenPairPriceFeed is ITokenPairPriceFeed {
    // The ENS registry (same for mainnet and all major test nets)
    IENS public constant ENS = IENS(0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e);

    function getRate(bytes32 chainlinkAggregatorNodeHash)
        public
        view
        override
        returns (uint256 rate, uint256 rateDenominator)
    {
        IENSResolver ensResolver = ENS.resolver(chainlinkAggregatorNodeHash);
        IChainlinkAggregator chainLinkAggregator = IChainlinkAggregator(ensResolver.addr(chainlinkAggregatorNodeHash));

        (, int256 latestRate, , , ) = chainLinkAggregator.latestRoundData();

        require(latestRate >= 0, "latest chainlink rate too small"); // prevents underflow when casting to uint256

        return (uint256(latestRate), 10**chainLinkAggregator.decimals());
    }
}
