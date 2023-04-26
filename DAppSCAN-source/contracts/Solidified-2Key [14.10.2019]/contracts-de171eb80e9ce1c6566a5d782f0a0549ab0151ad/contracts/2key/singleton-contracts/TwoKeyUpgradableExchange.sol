pragma solidity ^0.4.24;

import "../../openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";

import "../interfaces/ITwoKeyExchangeRateContract.sol";
import "../interfaces/ITwoKeyCampaignValidator.sol";
import "../interfaces/IKyberNetworkProxy.sol";
import "../interfaces/storage-contracts/ITwoKeyUpgradableExchangeStorage.sol";
import "../interfaces/IERC20.sol";

import "../libraries/SafeMath.sol";
import "../libraries/GetCode.sol";
import "../libraries/SafeERC20.sol";
import "../upgradability/Upgradeable.sol";
import "./ITwoKeySingletonUtils.sol";


contract TwoKeyUpgradableExchange is Upgradeable, ITwoKeySingletonUtils {

    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    bool initialized;

    ITwoKeyUpgradableExchangeStorage public PROXY_STORAGE_CONTRACT;


    /**
     * @notice Event will be fired every time someone buys tokens
     */
    event TokenSell(
        address indexed purchaser,
        address indexed beneficiary,
        uint256 value,
        uint256 amount
    );


    /**
     * Event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param receiver is who got the tokens
     * @param weiReceived is how weis paid for purchase
     * @param tokensBought is the amount of tokens purchased
     * @param rate is the global variable rate on the contract
     */
    event TokenPurchase(
        address indexed purchaser,
        address indexed receiver,
        uint256 weiReceived,
        uint256 tokensBought,
        uint256 rate
    );


    /**
     * @notice This event will be fired every time a withdraw is executed
     */
    event WithdrawExecuted(
        address caller,
        address beneficiary,
        uint stableCoinsReserveBefore,
        uint stableCoinsReserveAfter,
        uint etherBalanceBefore,
        uint etherBalanceAfter,
        uint stableCoinsToWithdraw,
        uint twoKeyAmount
    );


    /**
     * @notice Constructor of the contract
     */
    function setInitialParams(
        ERC20 _token,
        address _daiAddress,
        address _kyberNetworkProxy,
        address _twoKeySingletonesRegistry,
        address _proxyStorageContract
    )
    external
    {
        require(initialized == false);

        TWO_KEY_SINGLETON_REGISTRY = _twoKeySingletonesRegistry;
        PROXY_STORAGE_CONTRACT = ITwoKeyUpgradableExchangeStorage(_proxyStorageContract);

        setUint(("buyRate2key"),95);// When anyone send 2key to contract, 2key in exchange will be calculated on it's buy rate
        setUint(("sellRate2key"),100);// When anyone send Ether to contract, 2key in exchange will be calculated on it's sell rate
        setUint(("weiRaised"),0);
        setUint("transactionCounter",0);

        setAddress(("TWO_KEY_TOKEN"),address(_token));
        setAddress(("DAI"), _daiAddress);
        setAddress(("ETH_TOKEN_ADDRESS"), 0xeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee);
        setAddress(("KYBER_NETWORK_PROXY"), _kyberNetworkProxy);

        initialized = true;
    }

    /**
     * @notice Modifier which will validate if contract is allowed to buy tokens
     */
    modifier onlyValidatedContracts {
        address twoKeyCampaignValidator = getAddressFromTwoKeySingletonRegistry("TwoKeyCampaignValidator");
        require(ITwoKeyCampaignValidator(twoKeyCampaignValidator).isCampaignValidated(msg.sender) == true);
        _;
    }


    /**
     * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met. Use `super` in contracts that inherit from Crowdsale to extend their validations.
     * @param _beneficiary Address performing the token purchase
     * @param _weiAmount Value in wei involved in the purchase
     */
    function _preValidatePurchase(
        address _beneficiary,
        uint256 _weiAmount
    )
    private
    {
        require(_beneficiary != address(0),'beneficiary address can not be 0' );
        require(_weiAmount != 0, 'wei amount can not be 0');
    }


    /**
     * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends its tokens.
     * @param _beneficiary Address performing the token purchase
     * @param _tokenAmount Number of tokens to be emitted
     */
    function _deliverTokens(
        address _beneficiary,
        uint256 _tokenAmount
    )
    internal
    {
        //Take the address of token from storage
        address tokenAddress = getAddress("TWO_KEY_TOKEN");

        ERC20(tokenAddress).safeTransfer(_beneficiary, _tokenAmount);
    }


    /**
     * @dev Executed when a purchase has been validated and is ready to be executed. Not necessarily emits/sends tokens.
     * @param _beneficiary Address receiving the tokens
     * @param _tokenAmount Number of tokens to be purchased
     */
    function _processPurchase(
        address _beneficiary,
        uint256 _tokenAmount
    )
    internal
    {
        _deliverTokens(_beneficiary, _tokenAmount);
    }


    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param _weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */
    function _getTokenAmountToBeSold(
        uint256 _weiAmount
    )
    public
    view
    returns (uint256)
    {
        address twoKeyExchangeRateContract = getAddressFromTwoKeySingletonRegistry("TwoKeyExchangeRateContract");

        uint rate = ITwoKeyExchangeRateContract(twoKeyExchangeRateContract).getBaseToTargetRate("USD");
        return (_weiAmount*rate).mul(1000).div(getUint("sellRate2key")).div(10**18);
    }


    /**
     * @notice Function to calculate how many stable coins we can get for specific amount of 2keys
     * @dev This is happening in case we're receiving (buying) 2key
     * @param _2keyAmount is the amount of 2keys sent to the contract
     */
    function _getUSDStableCoinAmountFrom2keyUnits(
        uint256 _2keyAmount
    )
    public
    view
    returns (uint256)
    {
        // Take the address of TwoKeyExchangeRateContract
        address twoKeyExchangeRateContract = getAddressFromTwoKeySingletonRegistry("TwoKeyExchangeRateContract");

        // This is the case when we buy 2keys in exchange for stable coins
        uint rate = ITwoKeyExchangeRateContract(twoKeyExchangeRateContract).getBaseToTargetRate("USD-DAI"); // 1.01
        uint lowestAcceptedRate = 96;
        require(rate >= lowestAcceptedRate.mul(10**18).div(100)); // Require that lowest accepted rate is greater than 0.95

        uint buyRate2key = getUint("buyRate2key");

        uint dollarWeiWorthTokens = _2keyAmount.mul(buyRate2key).div(1000);  // 100*95/1000 = 9.5
        uint amountOfDAIs = dollarWeiWorthTokens.mul(rate).div(10**18);      // 9.5 * 1.01 =vOK

        return amountOfDAIs;
    }


    /**
     * @dev Determines how ETH is stored/forwarded on purchases.
     */
    function _forwardFunds(
        address _twoKeyAdmin
    )
    internal
    {
        _twoKeyAdmin.transfer(msg.value);
    }


    /**
     * @notice Function to buyTokens
     * @param _beneficiary to get
     * @return amount of tokens bought
     */
    function buyTokens(
        address _beneficiary
    )
    public
    payable
    onlyValidatedContracts
    returns (uint)
    {
        uint256 weiAmount = msg.value;
        _preValidatePurchase(_beneficiary, weiAmount);

        // calculate token amount to be created
        uint256 tokens = _getTokenAmountToBeSold(weiAmount);

        // update state
        uint weiRaised = getUint("weiRaised").add(weiAmount);
        setUint("weiRaised",weiRaised);
        setUint("transactionCounter",getUint("transactionCounter")+1);

        _processPurchase(_beneficiary, tokens);


        emit TokenPurchase(
            msg.sender,
            _beneficiary,
            weiAmount,
            tokens,
            getUint("sellRate2key")
        );

        return tokens;
    }


    /**
     * @notice Function to get expected rate from Kyber contract
     * @param amountEthWei is the amount we'd like to exchange
     * @return if the value is 0 that means we can't
     */
    function getKyberExpectedRate(
        uint amountEthWei
    )
    public
    view
    returns (uint)
    {
        address kyberProxyContract = getAddress("KYBER_NETWORK_PROXY");
        IKyberNetworkProxy proxyContract = IKyberNetworkProxy(kyberProxyContract);

        ERC20 eth = ERC20(getAddress("ETH_TOKEN_ADDRESS"));
        ERC20 dai = ERC20(getAddress("DAI"));

        uint minConversionRate;
        (minConversionRate,) = proxyContract.getExpectedRate(eth, dai, amountEthWei);

        return minConversionRate;
    }


    /**
     * @notice Function to start hedging some ether amount
     * @param amountToBeHedged is the amount we'd like to hedge
     * @dev only maintainer can call this function
     */
    function startHedging(
        uint amountToBeHedged,
        uint approvedMinConversionRate
    )
    public
    onlyMaintainer
    {
        ERC20 dai = ERC20(getAddress("DAI"));

        address kyberProxyContract = getAddress("KYBER_NETWORK_PROXY");
        IKyberNetworkProxy proxyContract = IKyberNetworkProxy(kyberProxyContract);

        uint minConversionRate = getKyberExpectedRate(amountToBeHedged);
        require(minConversionRate >= approvedMinConversionRate.mul(95).div(100)); //Means our rate can be at most same as their rate, because they're giving the best rate
        uint stableCoinUnits = proxyContract.swapEtherToToken.value(amountToBeHedged)(dai,minConversionRate);
    }

    /**
     * @notice Function which will be called by 2key campaigns if user wants to withdraw his earnings in stableCoins
     * @param _twoKeyUnits is the amount of 2key tokens which will be taken from campaign
     * @param _beneficiary is the user who will receive the tokens
     */
    function buyStableCoinWith2key(
        uint _twoKeyUnits,
        address _beneficiary
    )
    external
    onlyValidatedContracts
    returns (uint)
    {
        ERC20 dai = ERC20(getAddress("DAI"));
        ERC20 token = ERC20(getAddress("TWO_KEY_TOKEN"));

        uint stableCoinUnits = _getUSDStableCoinAmountFrom2keyUnits(_twoKeyUnits);
        uint etherBalanceOnContractBefore = this.balance;
        uint stableCoinsOnContractBefore = dai.balanceOf(address(this));
        token.transferFrom(msg.sender, address(this), _twoKeyUnits);

        uint stableCoinsAfter = stableCoinsOnContractBefore - stableCoinUnits;

        dai.transfer(_beneficiary, stableCoinUnits);

        emitEventWithdrawExecuted(
            _beneficiary,
            stableCoinsOnContractBefore,
            stableCoinsAfter,
            etherBalanceOnContractBefore,
            stableCoinUnits,
            _twoKeyUnits
        );
    }

    function emitEventWithdrawExecuted(
        address _beneficiary,
        uint _stableCoinsOnContractBefore,
        uint _stableCoinsAfter,
        uint _etherBalanceOnContractBefore,
        uint _stableCoinUnits,
        uint twoKeyUnits
    )
    internal
    {
        emit WithdrawExecuted(
            msg.sender,
            _beneficiary,
            _stableCoinsOnContractBefore,
            _stableCoinsAfter,
            _etherBalanceOnContractBefore,
            this.balance,
            _stableCoinUnits,
            twoKeyUnits
        );
    }

    function buyRate2key() public view returns (uint) {
        return getUint("buyRate2key");
    }

    function sellRate2key() public view returns (uint) {
        return getUint("sellRate2key");
    }

    function transactionCounter() public view returns (uint) {
        return getUint("transactionCounter");
    }

    function weiRaised() public view returns (uint) {
        return getUint("weiRaised");
    }

    // Internal wrapper methods
    function getUint(string key) internal view returns (uint) {
        return PROXY_STORAGE_CONTRACT.getUint(keccak256(key));
    }

    // Internal wrapper methods
    function setUint(string key, uint value) internal {
        PROXY_STORAGE_CONTRACT.setUint(keccak256(key), value);
    }


    // Internal wrapper methods
    function getAddress(string key) internal view returns (address) {
        return PROXY_STORAGE_CONTRACT.getAddress(keccak256(key));
    }

    // Internal wrapper methods
    function setAddress(string key, address value) internal {
        PROXY_STORAGE_CONTRACT.setAddress(keccak256(key), value);
    }

    function updateUint(
        string key,
        uint value
    )
    public
    onlyMaintainer
    {
        setUint(key, value);
    }

    /**
     * @notice Fallback function to handle incoming ether
     */
    function ()
    public
    payable
    {

    }

}
