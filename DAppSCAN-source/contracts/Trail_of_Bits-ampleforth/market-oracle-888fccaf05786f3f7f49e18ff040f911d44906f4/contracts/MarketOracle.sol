pragma solidity 0.4.24;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/ownership/Ownable.sol";

import "./MarketSource.sol";


/**
 * @title Market Oracle
 *
 * @dev Provides the exchange rate and volume data onchain using data from a whitelisted
 *      set of market source contracts.
 *      Exchange rate is the TOKEN:TARGET rate.
 *      Volume is a 24 hour trading volume in Token volume.
 */
contract MarketOracle is Ownable {
    using SafeMath for uint256;

    // Whitelist of sources
    MarketSource[] public _whitelist;

    event LogSourceAdded(MarketSource source);
    event LogSourceRemoved(MarketSource source);
    event LogSourceExpired(MarketSource source);

    /**
     * @dev Calculates the volume weighted average of exchange rates and total trade volume.
     *      Expired market sources are ignored.
     * @return exchangeRate: Volume weighted average of exchange rates.
     *         volume: Total trade volume of the last reported 24 hours in Token volume.
     */
    //  SWC-107-Reentrancy: L34 - L60
    function getPriceAnd24HourVolume()
        external
        returns (uint256, uint256)
    {
        uint256 volumeWeightedSum = 0;
        uint256 volumeSum = 0;
        uint256 partialRate = 0;
        uint256 partialVolume = 0;
        bool isSourceFresh = false;

        for (uint256 i = 0; i < _whitelist.length; i++) {
            (isSourceFresh, partialRate, partialVolume) = _whitelist[i].getReport();

            if (!isSourceFresh) {
                emit LogSourceExpired(_whitelist[i]);
                continue;
            }

            volumeWeightedSum = volumeWeightedSum.add(partialRate.mul(partialVolume));
            volumeSum = volumeSum.add(partialVolume);
        }

        // No explicit fixed point normalization is done as dividing by volumeSum normalizes
        // to exchangeRate's format.
        uint256 exchangeRate = volumeWeightedSum.div(volumeSum);
        return (exchangeRate, volumeSum);
    }

    /**
     * @dev Adds a market source to the whitelist.
     * @param source Address of the MarketSource.
     */
    function addSource(MarketSource source)
        external
        onlyOwner
    {
        _whitelist.push(source);
        emit LogSourceAdded(source);
    }

    /**
     * @dev Removes the provided market source from the whitelist.
     * @param source Address of the MarketSource.
     */
    function removeSource(MarketSource source)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < _whitelist.length; i++) {
            if (_whitelist[i] == source) {
                removeSourceAtIndex(i);
                break;
            }
        }
    }

    /**
     * @dev Expunges from the whitelist any MarketSource whose associated contracts have been
     *      destructed.
     */
    function removeDestructedSources()
        external
    {
        uint256 i = 0;
        while (i < _whitelist.length) {
            if (isContractDestructed(_whitelist[i])) {
                removeSourceAtIndex(i);
            } else {
                i++;
            }
        }
    }

    /**
     * @return The number of market sources in the whitelist.
     */
    function whitelistSize()
        public
        view
        returns (uint256)
    {
        return _whitelist.length;
    }

    /**
     * @dev Checks if a contract has been destructed.
     * @param contractAddress Address of the contract.
     */
    function isContractDestructed(address contractAddress)
        private
        view
        returns (bool)
    {
        uint256 size;
        assembly { size := extcodesize(contractAddress) }
        return size == 0;
    }

   /**
    * @param index Index of the MarketSource to be removed from the whitelist.
    */
    function removeSourceAtIndex(uint256 index)
        private
    {
        emit LogSourceRemoved(_whitelist[index]);
        if (index != _whitelist.length-1) {
            _whitelist[index] = _whitelist[_whitelist.length-1];
        }
        // SWC-101-Integer Overflow and Underflow: L143
        _whitelist.length--;
    }
}
