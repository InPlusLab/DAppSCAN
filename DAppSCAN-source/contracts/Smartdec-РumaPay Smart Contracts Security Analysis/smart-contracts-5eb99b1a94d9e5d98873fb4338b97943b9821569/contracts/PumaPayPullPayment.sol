pragma solidity 0.5.8;

import "./ownership/PayableOwnable.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
// SWC-135-Code With No Effects: L7
import "openzeppelin-solidity/contracts/token/ERC20/ERC20Mintable.sol";

/// @title PumaPay Pull Payment - Contract that facilitates our pull payment protocol
/// @author PumaPay Dev Team - <developers@pumapay.io>
contract PumaPayPullPayment is PayableOwnable {

    using SafeMath for uint256;

    /// ===============================================================================================================
    ///                                      Events
    /// ===============================================================================================================

    event LogExecutorAdded(address executor);
    event LogExecutorRemoved(address executor);
    event LogSetConversionRate(string currency, uint256 conversionRate);

    event LogPaymentRegistered(
        address customerAddress,
        bytes32 paymentID,
        bytes32 businessID,
        string uniqueReferenceID
    );
    event LogPaymentCancelled(
        address customerAddress,
        bytes32 paymentID,
        bytes32 businessID,
        string uniqueReferenceID
    );
    event LogPullPaymentExecuted(
        address customerAddress,
        bytes32 paymentID,
        bytes32 businessID,
        string uniqueReferenceID
    );

    /// ===============================================================================================================
    ///                                      Constants
    /// ===============================================================================================================

    uint256 constant private DECIMAL_FIXER = 10 ** 10;              /// 1e^10 - This transforms the Rate from decimals to uint256
    uint256 constant private FIAT_TO_CENT_FIXER = 100;              /// Fiat currencies have 100 cents in 1 basic monetary unit.
    uint256 constant private OVERFLOW_LIMITER_NUMBER = 10 ** 20;    /// 1e^20 - Prevent numeric overflows

    uint256 constant private ONE_ETHER = 1 ether;                               /// PumaPay token has 18 decimals - same as one ETHER
    uint256 constant private FUNDING_AMOUNT = 1 ether;                          /// Amount to transfer to owner/executor
    uint256 constant private MINIMUM_AMOUNT_OF_ETH_FOR_OPERATORS = 0.15 ether; /// min amount of ETH for owner/executor

    /// ===============================================================================================================
    ///                                      Members
    /// ===============================================================================================================

    IERC20 public token;

    mapping(string => uint256) private conversionRates;
    mapping(address => bool) public executors;
    mapping(address => mapping(address => PullPayment)) public pullPayments;

    struct PullPayment {
        bytes32 paymentID;                      /// ID of the payment
        bytes32 businessID;                     /// ID of the business
        string uniqueReferenceID;               /// unique reference ID the business is adding on the pull payment
        string currency;                        /// 3-letter abbr i.e. 'EUR' / 'USD' etc.
        uint256 initialPaymentAmountInCents;    /// initial payment amount in fiat in cents
        uint256 fiatAmountInCents;              /// payment amount in fiat in cents
        uint256 frequency;                      /// how often merchant can pull - in seconds
        uint256 numberOfPayments;               /// amount of pull payments merchant can make
        uint256 startTimestamp;                 /// when subscription starts - in seconds
        uint256 nextPaymentTimestamp;           /// timestamp of next payment
        uint256 lastPaymentTimestamp;           /// timestamp of last payment
        uint256 cancelTimestamp;                /// timestamp the payment was cancelled
        address treasuryAddress;                /// address which pma tokens will be transfer to on execution
    }

    /// ===============================================================================================================
    ///                                      Modifiers
    /// ===============================================================================================================
    modifier isExecutor() {
        require(executors[msg.sender], "msg.sender not an executor");
        _;
    }

    modifier executorExists(address _executor) {
        require(executors[_executor], "Executor does not exists.");
        _;
    }

    modifier executorDoesNotExists(address _executor) {
        require(!executors[_executor], "Executor already exists.");
        _;
    }

    modifier paymentExists(address _customer, address _pullPaymentExecutor) {
        require(doesPaymentExist(_customer, _pullPaymentExecutor), "Pull Payment does not exists");
        _;
    }

    modifier paymentNotCancelled(address _customer, address _pullPaymentExecutor) {
        require(pullPayments[_customer][_pullPaymentExecutor].cancelTimestamp == 0, "Pull Payment is cancelled.");
        _;
    }

    modifier isValidPullPaymentExecutionRequest(address _customer, address _pullPaymentExecutor, bytes32 _paymentID) {
        require(
            (pullPayments[_customer][_pullPaymentExecutor].initialPaymentAmountInCents > 0 ||
        (now >= pullPayments[_customer][_pullPaymentExecutor].startTimestamp &&
        now >= pullPayments[_customer][_pullPaymentExecutor].nextPaymentTimestamp)
            ), "Invalid pull payment execution request - Time of execution is invalid."
        );
        require(pullPayments[_customer][_pullPaymentExecutor].numberOfPayments > 0,
            "Invalid pull payment execution request - Number of payments is zero.");

        require((pullPayments[_customer][_pullPaymentExecutor].cancelTimestamp == 0 ||
        pullPayments[_customer][_pullPaymentExecutor].cancelTimestamp > pullPayments[_customer][_pullPaymentExecutor].nextPaymentTimestamp),
            "Invalid pull payment execution request - Pull payment is cancelled");
        require(keccak256(
            abi.encodePacked(pullPayments[_customer][_pullPaymentExecutor].paymentID)
        ) == keccak256(abi.encodePacked(_paymentID)),
            "Invalid pull payment execution request - Payment ID not matching.");
        _;
    }

    modifier isValidDeletionRequest(bytes32 _paymentID, address _customer, address _pullPaymentExecutor) {
        require(_customer != address(0), "Invalid deletion request - Client address is ZERO_ADDRESS.");
        require(_pullPaymentExecutor != address(0), "Invalid deletion request - Beneficiary address is ZERO_ADDRESS.");
        require(_paymentID.length != 0, "Invalid deletion request - Payment ID is empty.");
        _;
    }

    modifier isValidAddress(address _address) {
        require(_address != address(0), "Invalid address - ZERO_ADDRESS provided");
        _;
    }

    modifier validConversionRate(string memory _currency) {
        require(bytes(_currency).length != 0, "Invalid conversion rate - Currency is empty.");
        require(conversionRates[_currency] > 0, "Invalid conversion rate - Must be higher than zero.");
        _;
    }

    modifier validAmount(uint256 _fiatAmountInCents) {
        require(_fiatAmountInCents > 0, "Invalid amount - Must be higher than zero");
        _;
    }

    /// ===============================================================================================================
    ///                                      Constructor
    /// ===============================================================================================================

    /// @dev Contract constructor - sets the token address that the contract facilitates.
    /// @param _token Token Address.
    constructor (address _token)
    public {
        require(_token != address(0), "Invalid address for token - ZERO_ADDRESS provided");
        token = IERC20(_token);
    }

    // @notice Will receive any eth sent to the contract
    function() external payable {
    }

    /// ===============================================================================================================
    ///                                      Public Functions - Owner Only
    /// ===============================================================================================================

    /// @dev Adds a new executor. - can be executed only by the onwer.
    /// When adding a new executor 1 ETH is tranferred to allow the executor to pay for gas.
    /// The balance of the owner is also checked and if funding is needed 1 ETH is transferred.
    /// @param _executor - address of the executor which cannot be zero address.

    function addExecutor(address payable _executor)
    public
    onlyOwner
    isValidAddress(_executor)
    executorDoesNotExists(_executor)
    {
        _executor.transfer(FUNDING_AMOUNT);
        executors[_executor] = true;

        if (isFundingNeeded(owner())) {
            owner().transfer(FUNDING_AMOUNT);
        }

        emit LogExecutorAdded(_executor);
    }

    /// @dev Removes a new executor. - can be executed only by the onwer.
    /// The balance of the owner is checked and if funding is needed 1 ETH is transferred.
    /// @param _executor - address of the executor which cannot be zero address.
    function removeExecutor(address payable _executor)
    public
    onlyOwner
    isValidAddress(_executor)
    executorExists(_executor)
    {
        executors[_executor] = false;
        if (isFundingNeeded(owner())) {
            owner().transfer(FUNDING_AMOUNT);
        }
        emit LogExecutorRemoved(_executor);
    }

    /// @dev Sets the exchange rate for a currency. - can be executed only by the onwer.
    /// Emits 'LogSetConversionRate' with the currency and the updated rate.
    /// The balance of the owner is checked and if funding is needed 1 ETH is transferred.
    /// @param _currency - address of the executor which cannot be zero address
    /// @param _rate - address of the executor which cannot be zero address
    function setRate(string memory _currency, uint256 _rate)
    public
    onlyOwner
    returns (bool) {
        conversionRates[_currency] = _rate;
        emit LogSetConversionRate(_currency, _rate);

        if (isFundingNeeded(owner())) {
            owner().transfer(FUNDING_AMOUNT);
        }

        return true;
    }

    /// ===============================================================================================================
    ///                                      Public Functions - Executors Only
    /// ===============================================================================================================

    /// @dev Registers a new pull payment to the PumaPay Pull Payment Contract - The registration can be executed only
    /// by one of the executors of the PumaPay Pull Payment Contract
    /// and the PumaPay Pull Payment Contract checks that the pull payment has been singed by the customer of the account.
    /// The balance of the executor (msg.sender) is checked and if funding is needed 1 ETH is transferred.
    /// Emits 'LogPaymentRegistered' with customer address, beneficiary address and paymentID.
    /// @param v - recovery ID of the ETH signature. - https://github.com/ethereum/EIPs/issues/155
    /// @param r - R output of ECDSA signature.
    /// @param s - S output of ECDSA signature.
    /// @param _ids - array with the IDs for the payment ([0] paymentID, [1] businessID).
    /// @param _addresses - all the relevant addresses for the payment.
    /// @param _currency - currency of the payment / 3-letter abbr i.e. 'EUR'.
    /// @param _uniqueReferenceID - unique reference ID is the id that the business uses within their system.
    /// @param _fiatAmountInCents - payment amount in fiat in cents.
    /// @param _frequency - how often merchant can pull - in seconds.
    /// @param _numberOfPayments - amount of pull payments merchant can make
    /// @param _startTimestamp - when subscription starts - in seconds.
    function registerPullPayment(
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32[2] memory _ids, // [0] paymentID, [1] businessID
        address[3] memory _addresses, // [0] customer, [1] pull payment executor, [2] treasury wallet
        string memory _currency,
        string memory _uniqueReferenceID,
        uint256 _initialPaymentAmountInCents,
        uint256 _fiatAmountInCents,
        uint256 _frequency,
        uint256 _numberOfPayments,
        uint256 _startTimestamp
    )
    public
    isExecutor()
    {
        require(_ids[0].length > 0, "Payment ID is empty.");
        require(_ids[1].length > 0, "Business ID is empty.");
        require(bytes(_currency).length > 0, "Currency is empty.");
        require(bytes(_uniqueReferenceID).length > 0, "Unique Reference ID is empty.");
        require(_addresses[0] != address(0), "Customer Address is ZERO_ADDRESS.");
        require(_addresses[1] != address(0), "Beneficiary Address is ZERO_ADDRESS.");
        require(_addresses[2] != address(0), "Treasury Address is ZERO_ADDRESS.");
        require(_fiatAmountInCents > 0, "Payment amount in fiat is zero.");
        require(_frequency > 0, "Payment frequency is zero.");
        require(_frequency < OVERFLOW_LIMITER_NUMBER, "Payment frequency is higher thant the overflow limit.");
        require(_numberOfPayments > 0, "Payment number of payments is zero.");
        require(_numberOfPayments < OVERFLOW_LIMITER_NUMBER, "Payment number of payments is higher thant the overflow limit.");
        require(_startTimestamp > 0, "Payment start time is zero.");
        require(_startTimestamp < OVERFLOW_LIMITER_NUMBER, "Payment start time is higher thant the overflow limit.");

        pullPayments[_addresses[0]][_addresses[1]].currency = _currency;
        pullPayments[_addresses[0]][_addresses[1]].initialPaymentAmountInCents = _initialPaymentAmountInCents;
        pullPayments[_addresses[0]][_addresses[1]].fiatAmountInCents = _fiatAmountInCents;
        pullPayments[_addresses[0]][_addresses[1]].frequency = _frequency;
        pullPayments[_addresses[0]][_addresses[1]].startTimestamp = _startTimestamp;
        pullPayments[_addresses[0]][_addresses[1]].numberOfPayments = _numberOfPayments;
        pullPayments[_addresses[0]][_addresses[1]].paymentID = _ids[0];
        pullPayments[_addresses[0]][_addresses[1]].businessID = _ids[1];
        pullPayments[_addresses[0]][_addresses[1]].uniqueReferenceID = _uniqueReferenceID;
        pullPayments[_addresses[0]][_addresses[1]].treasuryAddress = _addresses[2];

        require(isValidRegistration(
                v,
                r,
                s,
                _addresses[0],
                _addresses[1],
                pullPayments[_addresses[0]][_addresses[1]]),
            "Invalid pull payment registration - ECRECOVER_FAILED"
        );

        pullPayments[_addresses[0]][_addresses[1]].nextPaymentTimestamp = _startTimestamp;
        pullPayments[_addresses[0]][_addresses[1]].lastPaymentTimestamp = 0;
        pullPayments[_addresses[0]][_addresses[1]].cancelTimestamp = 0;

        if (isFundingNeeded(msg.sender)) {
            msg.sender.transfer(FUNDING_AMOUNT);
        }

        emit LogPaymentRegistered(_addresses[0], _ids[0], _ids[1], _uniqueReferenceID);
    }

    /// @dev Deletes a pull payment for a beneficiary - The deletion needs can be executed only by one of the
    /// executors of the PumaPay Pull Payment Contract
    /// and the PumaPay Pull Payment Contract checks that the beneficiary and the paymentID have
    /// been singed by the customer of the account.
    /// This method sets the cancellation of the pull payment in the pull payments array for this beneficiary specified.
    /// The balance of the executor (msg.sender) is checked and if funding is needed 1 ETH is transferred.
    /// Emits 'LogPaymentCancelled' with beneficiary address and paymentID.
    /// @param v - recovery ID of the ETH signature. - https://github.com/ethereum/EIPs/issues/155
    /// @param r - R output of ECDSA signature.
    /// @param s - S output of ECDSA signature.
    /// @param _paymentID - ID of the payment.
    /// @param _customer - customer address that is linked to this pull payment.
    /// @param _pullPaymentExecutor - address that is allowed to execute this pull payment.
    function deletePullPayment(
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32 _paymentID,
        address _customer,
        address _pullPaymentExecutor
    )
    public
    isExecutor()
    paymentExists(_customer, _pullPaymentExecutor)
    paymentNotCancelled(_customer, _pullPaymentExecutor)
    isValidDeletionRequest(_paymentID, _customer, _pullPaymentExecutor)
    {
        require(isValidDeletion(v, r, s, _paymentID, _customer, _pullPaymentExecutor), "Invalid deletion - ECRECOVER_FAILED.");

        pullPayments[_customer][_pullPaymentExecutor].cancelTimestamp = now;

        if (isFundingNeeded(msg.sender)) {
            msg.sender.transfer(FUNDING_AMOUNT);
        }

        emit LogPaymentCancelled(
            _customer,
            _paymentID,
            pullPayments[_customer][_pullPaymentExecutor].businessID,
            pullPayments[_customer][_pullPaymentExecutor].uniqueReferenceID
        );
    }

    /// ===============================================================================================================
    ///                                      Public Functions
    /// ===============================================================================================================

    /// @dev Executes a pull payment for the msg.sender - The pull payment should exist and the payment request
    /// should be valid in terms of when it can be executed.
    /// Emits 'LogPullPaymentExecuted' with customer address, msg.sender as the beneficiary address and the paymentID.
    /// Use Case 1: Single/Recurring Fixed Pull Payment (initialPaymentAmountInCents == 0 )
    /// ------------------------------------------------
    /// We calculate the amount in PMA using the rate for the currency specified in the pull payment
    /// and the 'fiatAmountInCents' and we transfer from the customer account the amount in PMA.
    /// After execution we set the last payment timestamp to NOW, the next payment timestamp is incremented by
    /// the frequency and the number of payments is decreased by 1.
    /// Use Case 2: Recurring Fixed Pull Payment with initial fee (initialPaymentAmountInCents > 0)
    /// ------------------------------------------------------------------------------------------------
    /// We calculate the amount in PMA using the rate for the currency specified in the pull payment
    /// and the 'initialPaymentAmountInCents' and we transfer from the customer account the amount in PMA.
    /// After execution we set the last payment timestamp to NOW and the 'initialPaymentAmountInCents to ZERO.
    /// @param _customer - address of the customer from which the msg.sender requires to pull funds.
    /// @param _paymentID - ID of the payment.
    function executePullPayment(address _customer, bytes32 _paymentID)
    public
    paymentExists(_customer, msg.sender)
    isValidPullPaymentExecutionRequest(_customer, msg.sender, _paymentID)
    {
        uint256 amountInPMA;

        if (pullPayments[_customer][msg.sender].initialPaymentAmountInCents > 0) {
            amountInPMA = calculatePMAFromFiat(
                pullPayments[_customer][msg.sender].initialPaymentAmountInCents,
                pullPayments[_customer][msg.sender].currency
            );
            pullPayments[_customer][msg.sender].initialPaymentAmountInCents = 0;
        } else {
            amountInPMA = calculatePMAFromFiat(
                pullPayments[_customer][msg.sender].fiatAmountInCents,
                pullPayments[_customer][msg.sender].currency
            );

            pullPayments[_customer][msg.sender].nextPaymentTimestamp =
            pullPayments[_customer][msg.sender].nextPaymentTimestamp + pullPayments[_customer][msg.sender].frequency;
            pullPayments[_customer][msg.sender].numberOfPayments = pullPayments[_customer][msg.sender].numberOfPayments - 1;
        }

        pullPayments[_customer][msg.sender].lastPaymentTimestamp = now;
        token.transferFrom(
            _customer,
            pullPayments[_customer][msg.sender].treasuryAddress,
            amountInPMA
        );

        emit LogPullPaymentExecuted(
            _customer,
            pullPayments[_customer][msg.sender].paymentID,
            pullPayments[_customer][msg.sender].businessID,
            pullPayments[_customer][msg.sender].uniqueReferenceID
        );
    }

    function getRate(string memory _currency) public view returns (uint256) {
        return conversionRates[_currency];
    }

    /// ===============================================================================================================
    ///                                      Internal Functions
    /// ===============================================================================================================

    /// @dev Calculates the PMA Rate for the fiat currency specified - The rate is set every 10 minutes by our PMA server
    /// for the currencies specified in the smart contract.
    /// @param _fiatAmountInCents - payment amount in fiat CENTS so that is always integer
    /// @param _currency - currency in which the payment needs to take place
    /// RATE CALCULATION EXAMPLE
    /// ------------------------
    /// RATE ==> 1 PMA = 0.01 USD$
    /// 1 USD$ = 1/0.01 PMA = 100 PMA
    /// Start the calculation from one ether - PMA Token has 18 decimals
    /// Multiply by the DECIMAL_FIXER (1e+10) to fix the multiplication of the rate
    /// Multiply with the fiat amount in cents
    /// Divide by the Rate of PMA to Fiat in cents
    /// Divide by the FIAT_TO_CENT_FIXER to fix the _fiatAmountInCents
    function calculatePMAFromFiat(uint256 _fiatAmountInCents, string memory _currency)
    internal
    view
    validConversionRate(_currency)
    validAmount(_fiatAmountInCents)
    returns (uint256) {
        return ONE_ETHER.mul(DECIMAL_FIXER).mul(_fiatAmountInCents).div(conversionRates[_currency]).div(FIAT_TO_CENT_FIXER);
    }

    /// @dev Checks if a registration request is valid by comparing the v, r, s params
    /// and the hashed params with the customer address.
    /// @param v - recovery ID of the ETH signature. - https://github.com/ethereum/EIPs/issues/155
    /// @param r - R output of ECDSA signature.
    /// @param s - S output of ECDSA signature.
    /// @param _customer - customer address that is linked to this pull payment.
    /// @param _pullPaymentExecutor - address that is allowed to execute this pull payment.
    /// @param _pullPayment - pull payment to be validated.
    /// @return bool - if the v, r, s params with the hashed params match the customer address
    function isValidRegistration(
        uint8 v,
        bytes32 r,
        bytes32 s,
        address _customer,
        address _pullPaymentExecutor,
        PullPayment memory _pullPayment
    )
    internal
    pure
    returns (bool)
    {
        return ecrecover(
            keccak256(
                abi.encodePacked(
                    _pullPaymentExecutor,
                    _pullPayment.paymentID,
                    _pullPayment.businessID,
                    _pullPayment.uniqueReferenceID,
                    _pullPayment.treasuryAddress,
                    _pullPayment.currency,
                    _pullPayment.initialPaymentAmountInCents,
                    _pullPayment.fiatAmountInCents,
                    _pullPayment.frequency,
                    _pullPayment.numberOfPayments,
                    _pullPayment.startTimestamp
                )
            ),
            v, r, s) == _customer;
    }

    /// @dev Checks if a deletion request is valid by comparing the v, r, s params
    /// and the hashed params with the customer address.
    /// @param v - recovery ID of the ETH signature. - https://github.com/ethereum/EIPs/issues/155
    /// @param r - R output of ECDSA signature.
    /// @param s - S output of ECDSA signature.
    /// @param _paymentID - ID of the payment.
    /// @param _customer - customer address that is linked to this pull payment.
    /// @param _pullPaymentExecutor - address that is allowed to execute this pull payment.
    /// @return bool - if the v, r, s params with the hashed params match the customer address
    function isValidDeletion(
        uint8 v,
        bytes32 r,
        bytes32 s,
        bytes32 _paymentID,
        address _customer,
        address _pullPaymentExecutor
    )
    internal
    view
    returns (bool)
    {
        return ecrecover(
            keccak256(
                abi.encodePacked(
                    _paymentID,
                    _pullPaymentExecutor
                )
            ), v, r, s) == _customer
        && keccak256(
            abi.encodePacked(pullPayments[_customer][_pullPaymentExecutor].paymentID)
        ) == keccak256(abi.encodePacked(_paymentID)
        );
    }

    /// @dev Checks if a payment for a beneficiary of a customer exists.
    /// @param _customer - customer address that is linked to this pull payment.
    /// @param _pullPaymentExecutor - address to execute a pull payment.
    /// @return bool - whether the beneficiary for this customer has a pull payment to execute.
    function doesPaymentExist(address _customer, address _pullPaymentExecutor)
    internal
    view
    returns (bool) {
        return (
        bytes(pullPayments[_customer][_pullPaymentExecutor].currency).length > 0 &&
        pullPayments[_customer][_pullPaymentExecutor].fiatAmountInCents > 0 &&
        pullPayments[_customer][_pullPaymentExecutor].frequency > 0 &&
        pullPayments[_customer][_pullPaymentExecutor].startTimestamp > 0 &&
        pullPayments[_customer][_pullPaymentExecutor].numberOfPayments > 0 &&
        pullPayments[_customer][_pullPaymentExecutor].nextPaymentTimestamp > 0
        );
    }

    /// @dev Checks if the address of an owner/executor needs to be funded.
    /// The minimum amount the owner/executors should always have is 0.001 ETH
    /// @param _address - address of owner/executors that the balance is checked against.
    /// @return bool - whether the address needs more ETH.
    function isFundingNeeded(address _address)
    private
    view
    returns (bool) {
        return address(_address).balance <= MINIMUM_AMOUNT_OF_ETH_FOR_OPERATORS;
    }
}
