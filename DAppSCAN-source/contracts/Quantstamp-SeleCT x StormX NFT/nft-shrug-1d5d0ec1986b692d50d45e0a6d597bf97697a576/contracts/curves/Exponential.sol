// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IAggregator.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract Exponential is Ownable {
    uint256 constant public decimals = 10**18;

    IAggregator public ETHUSDAggregator;
    IAggregator public USDTUSDAggregator;
    IAggregator public STMXUSDAggregator;

    function calculatePrice(
        uint256 totalSupply,
        uint256 currency
    )   public
        view
        returns (uint256)
    {
        if(currency == 0)
            return  decimals * 20477 * (totalSupply + 1) ** 11 / 10 ** 32 + decimals * 2 / 100;

        if(currency == 1)
            return (decimals * 20477 * (totalSupply + 1) ** 11 / 10 ** 32 + decimals * 2 / 100) * uint256(ETHUSDAggregator.latestAnswer()) / uint256(USDTUSDAggregator.latestAnswer()) / 10 ** 12;
            
        return (decimals * 20477 * (totalSupply + 1) ** 11 / 10 ** 32 + decimals * 2 / 100) * uint256(ETHUSDAggregator.latestAnswer()) / uint256(STMXUSDAggregator.latestAnswer());
    }

    /**
     * @dev Owner can set ETH / USD Aggregator contract
     * @param _addr Address of aggregator contract
     */
    function setETHUSDAggregatorContract(address _addr) public onlyOwner {
        ETHUSDAggregator = IAggregator(address(_addr));
    }

    /**
     * @dev Owner can set USDT / USD Aggregator contract
     * @param _addr Address of aggregator contract
     */
    function setUSDTUSDAggregatorContract(address _addr) public onlyOwner {
        USDTUSDAggregator = IAggregator(address(_addr));
    }

    /**
     * @dev Owner can set STMX / USD Aggregator contract
     * @param _addr Address of aggregator contract
     */
    function setSTMXUSDAggregatorContract(address _addr) public onlyOwner {
        STMXUSDAggregator = IAggregator(address(_addr));
    }
}