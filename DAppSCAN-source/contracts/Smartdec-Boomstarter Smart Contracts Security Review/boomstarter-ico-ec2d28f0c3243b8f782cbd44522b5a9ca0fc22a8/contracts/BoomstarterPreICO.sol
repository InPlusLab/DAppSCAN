pragma solidity 0.4.23;

import './IBoomstarterToken.sol';
import './EthPriceDependent.sol';
import 'zeppelin-solidity/contracts/ReentrancyGuard.sol';
import 'zeppelin-solidity/contracts/math/SafeMath.sol';
import 'mixbytes-solidity/contracts/security/ArgumentsChecker.sol';

/// @title Boomstarter pre-sale contract
contract BoomstarterPreICO is ArgumentsChecker, ReentrancyGuard, EthPriceDependent {
    using SafeMath for uint256;

    event FundTransfer(address backer, uint amount, bool isContribution);

    /// @dev checks that owners didn't finish the sale yet
    modifier onlyIfSaleIsActive() {
        require(m_active == true);
        _;
    }

    /**
     *  @dev checks that finish date is not reached yet
     *       (and potentially start date, but not needed for presale)
     *       AND also that the limits for the sale are not met
     *       AND that current price is non-zero (updated)
     */
    modifier checkLimitsAndDates() {
        require((c_dateTo >= getTime()) &&
                (m_currentTokensSold < c_maximumTokensSold) &&
                (m_ETHPriceInCents > 0));
        _;
    }

    /**
     * @dev constructor, payable to fund oraclize calls
     * @param _owners Addresses to do administrative actions
     * @param _token Address of token being sold in this presale
     * @param _beneficiary Address of the wallet, receiving all the collected ether
     * @param _updateInterval time between oraclize price updates in seconds
     * @param _production False if you use testrpc, true if mainnet and most testnets
     */
    function BoomstarterPreICO(
        address[] _owners,
        address _token,
        address _beneficiary,
        uint _updateInterval,
        bool _production
    )
        public
        payable
        EthPriceDependent(_owners, 2, _production)
        validAddress(_token)
        validAddress(_beneficiary)
    {
        m_token = IBoomstarterToken(_token);
        m_beneficiary = _beneficiary;
        m_active = true;
        // different update interval
        m_ETHPriceUpdateInterval = _updateInterval;
    }


    // PUBLIC interface: payments

    // fallback function as a shortcut
    function() public payable {
        require(0 == msg.data.length);
        buy();  // only internal call here!
    }

    // @notice preICO participation
    function buy()
        public
        payable
        nonReentrant
        onlyIfSaleIsActive
        checkLimitsAndDates
    {
        // don't allow to buy anything if price change was too long ago
        // effectively enforcing a sale pause
        require( !priceExpired() );
        address investor = msg.sender;
        uint256 payment = msg.value;
        require((payment.mul(m_ETHPriceInCents)).div(1 ether) >= c_MinInvestmentInCents);

        /**
         * calculate amount based on ETH/USD rate
         * for example 2e17 * 36900 / 60 = 123 * 1e18
         * 0.2 eth buys 123 tokens if Ether price is $369 and token price is 60 cents
         */
        uint tokenAmount;
        // price of the batch of token bought
        uint centsPerToken = c_centsPerToken;

        // amount that can be bought depending on the price
        tokenAmount = payment.mul(m_ETHPriceInCents).div(centsPerToken);

        // number of tokens available before the cap is reached
        uint maxTokensAllowed = c_maximumTokensSold.sub(m_currentTokensSold);

        // if amount of tokens we can buy is more than the amount available
        if (tokenAmount > maxTokensAllowed) {
            // price of 1 full token in ether-wei
            // example 60 * 1e18 / 36900 = 0.162 * 1e18 = 0.162 eth
            uint ethPerToken = centsPerToken.mul(1 ether).div(m_ETHPriceInCents);
            // change amount to maximum allowed
            tokenAmount = maxTokensAllowed;
            // how much exactly to charge
            payment = ethPerToken.mul(tokenAmount).div(1 ether);
        }

        // calculating a 20% bonus if the price of bought tokens is more than $30k
        if (payment.mul(m_ETHPriceInCents).div(1 ether) >= 3000000) {
            tokenAmount = tokenAmount.add(tokenAmount.div(5));
        }

        m_currentTokensSold = m_currentTokensSold.add(tokenAmount);

        // send ether to external wallet
        m_beneficiary.transfer(payment);

        m_token.transfer(investor, tokenAmount);

        uint change = msg.value.sub(payment);
        if (change > 0)
            investor.transfer(change);

        FundTransfer(investor, payment, true);
    }


    /**
     * @notice stop accepting ether, transfer remaining tokens to the next sale and
     *         give new sale permissions to transfer frozen funds and revoke own ones
     *         Can be called anytime, even before the set finish date
     */
    function finishSale()
        external
        onlyIfSaleIsActive
        onlymanyowners(keccak256(msg.data))
    {
        // next sale should be set using setNextSale
        require( m_nextSale != address(0) );
        // cannot accept ether anymore
        m_active = false;
        // send remaining oraclize ether to the next sale - we don't need oraclize anymore
        EthPriceDependent next = EthPriceDependent(m_nextSale);
        next.topUp.value(this.balance)();
        // transfer all remaining tokens to the next sale account
        m_token.transfer(m_nextSale, m_token.balanceOf(this));
        // mark next sale as a valid sale account, unmark self as valid sale account
        m_token.switchToNextSale(m_nextSale);
    }

    /**
     * @notice set address of a sale that will be next one after the current sale is finished
     * @param _sale address of the sale contract
     */
    function setNextSale(address _sale)
        external
        validAddress(_sale)
        onlymanyowners(keccak256(msg.data))
    {
        m_nextSale = _sale;
    }


    // FIELDS

    /// @notice minimum investment in cents
    uint public c_MinInvestmentInCents = 10000; // $100

    /// @dev contract responsible for token accounting
    IBoomstarterToken public m_token;

    /// @dev address receiving all the ether, no intentions to refund
    address public m_beneficiary;

    /// @dev next sale to receive remaining tokens after this one finishes
    address public m_nextSale;

    /// @dev active sale can accept ether, inactive - cannot
    bool public m_active;

    /**
     *  @dev unix timestamp that sets preICO finish date, which means that after that date
     *       you cannot buy anything, but finish can happen before, if owners decide to do so
     */
    uint public c_dateTo = 1532563200; // 26-Jul-18 00:00:00 UTC

    /// @dev current amount of tokens sold
    uint public m_currentTokensSold = 0;
    /// @dev limit of tokens to be sold during presale
    uint public c_maximumTokensSold = uint(5000000) * uint(10) ** uint(18); // 5 million tokens

    /// @notice usd price of BoomstarterToken in cents 
    uint public c_centsPerToken = 60; // $0.6
}
