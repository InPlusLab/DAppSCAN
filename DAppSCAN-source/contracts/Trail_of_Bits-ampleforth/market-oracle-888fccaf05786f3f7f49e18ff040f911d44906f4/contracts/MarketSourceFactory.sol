pragma solidity 0.4.24;

import "./MarketSource.sol";


/**
 * @title Market Source Factory
 */
contract MarketSourceFactory {
    event LogSourceCreated(address owner, MarketSource source);

    /**
     * @param name A human readable identifier for the source.
     * @param reportExpirationTimeSec The number of seconds after which the market data is deemed expired.
     * @return The address of the created MarketSource contract.
     */
    function createSource(string name, uint64 reportExpirationTimeSec)
        public
        returns (MarketSource)
    {
        MarketSource source = new MarketSource(name, reportExpirationTimeSec);
        source.transferOwnership(msg.sender);
        emit LogSourceCreated(msg.sender, source);
        return source;
    }
}
