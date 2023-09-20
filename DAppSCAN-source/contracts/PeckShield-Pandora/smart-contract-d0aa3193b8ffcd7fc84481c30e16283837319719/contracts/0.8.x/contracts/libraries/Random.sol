// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "hardhat/console.sol";

library Random {
    address constant BNB = 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE; // mainnet 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE
    address constant BTC = 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf; // mainnet 0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf
    address constant ETH = 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e; // mainnet 0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e

    uint256 constant PRECISION = 1e20;

    function getLatestPrice(address _addr) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_addr);
        (, int256 _price, , , ) = priceFeed.latestRoundData();
        return uint256(_price);
    }
    //SWC-120-Weak Sources of Randomness from Chain Attributes: L20-L41
    function computerSeed(uint256 salt) internal view returns (uint256) {
        uint256 seed =
        uint256(
            keccak256(
                abi.encodePacked(
                    (block.timestamp)
                    + block.gaslimit
                    + uint256(keccak256(abi.encodePacked(blockhash(block.number)))) / (block.timestamp)
                    + uint256(keccak256(abi.encodePacked(block.coinbase))) / (block.timestamp)
                    + (uint256(keccak256(abi.encodePacked(tx.origin)))) / (block.timestamp)
                    + block.number * block.timestamp
                )
            )
        );
        seed = (seed % PRECISION) * getLatestPrice(BNB);
        seed = (seed % PRECISION) * getLatestPrice(ETH);
        seed = (seed % PRECISION) * getLatestPrice(BTC);
        if (salt > 0) {
            seed = seed % PRECISION * salt;
        }
        return seed;
    }
}