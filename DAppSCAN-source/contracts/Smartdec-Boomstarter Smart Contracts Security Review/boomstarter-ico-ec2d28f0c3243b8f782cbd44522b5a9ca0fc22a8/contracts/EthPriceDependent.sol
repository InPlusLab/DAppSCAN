pragma solidity 0.4.23;

import "./oraclize/usingOraclize.sol";
import "zeppelin-solidity/contracts/math/SafeMath.sol";
import "mixbytes-solidity/contracts/ownership/multiowned.sol";

contract EthPriceDependent is usingOraclize, multiowned {

    using SafeMath for uint256;

    event NewOraclizeQuery(string description);
    event NewETHPrice(uint price);
    event ETHPriceOutOfBounds(uint price);

    /// @notice Constructor
    /// @param _initialOwners set owners, which can control bounds and things
    ///        described in the actual sale contract, inherited from this one
    /// @param _consensus Number of votes enough to make a decision
    /// @param _production True if on mainnet and testnet
    function EthPriceDependent(address[] _initialOwners,  uint _consensus, bool _production)
        public
        multiowned(_initialOwners, _consensus)
    {
        oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
        if (!_production) {
            // Use it when testing with testrpc and etherium bridge. Don't forget to change address
            OAR = OraclizeAddrResolverI(0x6f485C8BF6fc43eA212E93BBF8ce046C7f1cb475);
        } else {
            // Don't call this while testing as it's too long and gets in the way
            updateETHPriceInCents();
        }
    }

    /// @notice Send oraclize query.
    /// if price is received successfully - update scheduled automatically,
    /// if at any point the contract runs out of ether - updating stops and further
    /// updating will require running this function again.
    /// if price is out of bounds - updating attempts continue
    function updateETHPriceInCents() public payable {
        // prohibit running multiple instances of update
        // however don't throw any error, because it's called from __callback as well
        // and we need to let it update the price anyway, otherwise there is an attack possibility
        if ( !updateRequestExpired() ) {
            NewOraclizeQuery("Oraclize request fail. Previous one still pending");
        } else if (oraclize_getPrice("URL") > this.balance) {
            NewOraclizeQuery("Oraclize request fail. Not enough ether");
        } else {
            oraclize_query(
                m_ETHPriceUpdateInterval,
                "URL",
                "json(https://api.coinmarketcap.com/v1/ticker/ethereum/?convert=USD).0.price_usd",
                m_callbackGas
            );
            m_ETHPriceLastUpdateRequest = getTime();
            NewOraclizeQuery("Oraclize query was sent");
        }
    }

    /// @notice Called on ETH price update by Oraclize
    function __callback(bytes32 myid, string result, bytes proof) public {
        require(msg.sender == oraclize_cbAddress());

        uint newPrice = parseInt(result).mul(100);

        if (newPrice >= m_ETHPriceLowerBound && newPrice <= m_ETHPriceUpperBound) {
            m_ETHPriceInCents = newPrice;
            m_ETHPriceLastUpdate = getTime();
            NewETHPrice(m_ETHPriceInCents);
        } else {
            ETHPriceOutOfBounds(newPrice);
        }
        // continue updating anyway (if current price was out of bounds, the price might recover in the next cycle)
        updateETHPriceInCents();
    }

    /// @notice set the limit of ETH in cents, oraclize data greater than this is not accepted
    /// @param _price Price in US cents
    function setETHPriceUpperBound(uint _price)
        external
        onlymanyowners(keccak256(msg.data))
    {
        m_ETHPriceUpperBound = _price;
    }

    /// @notice set the limit of ETH in cents, oraclize data smaller than this is not accepted
    /// @param _price Price in US cents
    function setETHPriceLowerBound(uint _price)
        external
        onlymanyowners(keccak256(msg.data))
    {
        m_ETHPriceLowerBound = _price;
    }

    /// @notice set the price of ETH in cents, called in case we don't get oraclize data
    ///         for more than double the update interval
    /// @param _price Price in US cents
    function setETHPriceManually(uint _price)
        external
        onlymanyowners(keccak256(msg.data))
    {
        // allow for owners to change the price anytime if update is not running
        // but if it is, then only in case the price has expired
        require( priceExpired() || updateRequestExpired() );
        m_ETHPriceInCents = _price;
        m_ETHPriceLastUpdate = getTime();
        NewETHPrice(m_ETHPriceInCents);
    }

    /// @notice add more ether to use in oraclize queries
    function topUp() external payable {
    }

    /// @dev change gas price for oraclize calls,
    ///      should be a compromise between speed and price according to market
    /// @param _gasPrice gas price in wei
    function setOraclizeGasPrice(uint _gasPrice)
        external
        onlymanyowners(keccak256(msg.data))
    {
        oraclize_setCustomGasPrice(_gasPrice);
    }

    /// @dev change gas limit for oraclize callback
    ///      note: should be changed only in case of emergency
    /// @param _callbackGas amount of gas
    function setOraclizeGasLimit(uint _callbackGas)
        external
        onlymanyowners(keccak256(msg.data))
    {
        m_callbackGas = _callbackGas;
    }

    /// @dev Check that double the update interval has passed
    ///      since last successful price update
    function priceExpired() public view returns (bool) {
        return (getTime() > m_ETHPriceLastUpdate + 2 * m_ETHPriceUpdateInterval);
    }

    /// @dev Check that price update was requested
    ///      more than 1 update interval ago
    ///      NOTE: m_leeway seconds added to offset possible timestamp inaccuracy
    function updateRequestExpired() public view returns (bool) {
        return ( (getTime() + m_leeway) >= (m_ETHPriceLastUpdateRequest + m_ETHPriceUpdateInterval) );
    }

    /// @dev to be overridden in tests
    function getTime() internal view returns (uint) {
        return now;
    }

    // FIELDS

    /// @notice usd price of ETH in cents, retrieved using oraclize
    uint public m_ETHPriceInCents = 0;
    /// @notice unix timestamp of last update
    uint public m_ETHPriceLastUpdate;
    /// @notice unix timestamp of last update request,
    ///         don't allow requesting more than once per update interval
    uint public m_ETHPriceLastUpdateRequest;

    /// @notice lower bound of the ETH price in cents
    uint public m_ETHPriceLowerBound = 100;
    /// @notice upper bound of the ETH price in cents
    uint public m_ETHPriceUpperBound = 100000000;

    /// @dev Update ETH price in cents every 12 hours
    uint public m_ETHPriceUpdateInterval = 60*60*1;

    /// @dev offset time inaccuracy when checking update expiration date
    uint public m_leeway = 900; // 15 minutes is the limit for miners

    /// @dev set just enough gas because the rest is not refunded
    uint public m_callbackGas = 200000;
}
