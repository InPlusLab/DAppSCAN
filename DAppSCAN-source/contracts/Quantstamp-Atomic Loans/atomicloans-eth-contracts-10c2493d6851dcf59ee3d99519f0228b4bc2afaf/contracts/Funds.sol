//SWC-Integer Overflow and Underflow: L2-L801
import 'openzeppelin-solidity/contracts/token/ERC20/ERC20.sol';
import 'openzeppelin-solidity/contracts/math/SafeMath.sol';

import './Loans.sol';
import './ALCompound.sol';

pragma solidity ^0.5.10;

contract Funds is DSMath, ALCompound {
    Loans loans;

    uint256 public constant DEFAULT_LIQUIDATION_RATIO = 1400000000000000000000000000;   // 140% (1.4x in RAY) minimum collateralization ratio
    uint256 public constant DEFAULT_LIQUIDATION_PENALTY = 1000000000937303470807876289; // 3% (3 in RAY) liquidation penalty
    uint256 public constant DEFAULT_MIN_LOAN_AMT = 20 ether; // Min 20 WAD
    uint256 public constant DEFAULT_MAX_LOAN_AMT = 2**256-1; // Max 2**256
    uint256 public constant DEFAULT_MIN_LOAN_DUR = 6 hours;  // 6 hours
    uint256 public constant NUM_SECONDS_IN_YEAR = 365 days;

    mapping (address => bytes32[]) public secretHashes;    // User secret hashes
    mapping (address => uint256)   public secretHashIndex; // User secret hash index

    mapping (address => bytes)     public pubKeys;  // User A Coin PubKeys
    
    mapping (bytes32 => Fund)      public funds;
    mapping (address => bytes32)   public fundOwner;
    mapping (bytes32 => Bools)     public bools;
    uint256                        public fundIndex;

    uint256 public lastGlobalInterestUpdated;
    uint256 public tokenMarketLiquidity;
    uint256 public cTokenMarketLiquidity;
    uint256 public marketLiquidity;
    uint256 public totalBorrow;
    uint256 public globalInterestRateNumerator;
    uint256 public lastUtilizationRatio;
    uint256 public globalInterestRate;
    uint256 public maxUtilizationDelta;
    uint256 public utilizationInterestDivisor;
    uint256 public maxInterestRateNumerator;
    uint256 public minInterestRateNumerator;
    uint256 public interestUpdateDelay;
    uint256 public defaultArbiterFee;

    ERC20 public token;
    uint256 public decimals;
    CTokenInterface public cToken;
    bool compoundSet;

    address deployer;

    /**
     * @notice Container for Loan Fund information
     * @member lender Loan Fund Owner
     * @member minLoanAmt Minimum Loan Amount that can be requested by a 'borrower'
     * @member maxLoanAmt Maximum Loan Amount that can be requested by a 'borrower'
     * @member minLoanDur Minimum Loan Duration that can be requested by a 'borrower'
     * @member maxLoanDur Maximum Loan Duration that can be requested by a 'borrower'
     * @member interest Interest Rate of Loan Fund in RAY per second
     * @member penalty Liquidation Penalty Rate of Loan Fund in RAY per second
     * @member fee Optional Automation Fee Rate of Loan Fund in RAY per second
     * @member liquidationRatio Liquidation Ratio of Loan Fund in RAY
     * @member arbiter Optional address of Automator Arbiter
     * @member balance Amount of non-borrowed tokens in Loan Fund
     * @member cBalance Amount of non-borrowed cTokens in Loan Fund
     * @member custom Indicator that this Loan Fund is custom and does not use global settings
     * @member compoundEnabled Indicator that this Loan Fund lends non-borrowed tokens on Compound
     */
    struct Fund {
        address  lender;
        uint256  minLoanAmt;
        uint256  maxLoanAmt;
        uint256  minLoanDur;
        uint256  maxLoanDur;
        uint256  fundExpiry;
        uint256  interest;
        uint256  penalty;
        uint256  fee;
        uint256  liquidationRatio;
        address  arbiter;
        uint256  balance;
        uint256  cBalance;
    }

    struct Bools {
        bool     custom;
        bool     compoundEnabled;
    }

    event Create(bytes32 fund);

    constructor(
        ERC20   token_,
        uint256 decimals_
    ) public {
        deployer = msg.sender;
        token = token_;
        decimals = decimals_;
        utilizationInterestDivisor = 10531702972595856680093239305; // 10.53 in RAY (~10:1 ratio for % change in utilization ratio to % change in interest rate)
        maxUtilizationDelta = 95310179948351216961192521; // Global Interest Rate Numerator can change up to 9.53% in RAY (~10% change in utilization ratio = ~1% change in interest rate)
        globalInterestRateNumerator =  95310179948351216961192521; // ~10%  ( (e^(ln(1.100)/(60*60*24*365)) - 1) * (60*60*24*365) )
        maxInterestRateNumerator    = 182321557320989604265864303; // ~20%  ( (e^(ln(1.200)/(60*60*24*365)) - 1) * (60*60*24*365) )
        minInterestRateNumerator    =  24692612600038629323181834; // ~2.5% ( (e^(ln(1.025)/(60*60*24*365)) - 1) * (60*60*24*365) )
        interestUpdateDelay = 86400; // 1 DAY
        defaultArbiterFee = 1000000000236936036262880196; // 0.75% (0.75 in RAY) optional arbiter fee
        globalInterestRate = add(RAY, div(globalInterestRateNumerator, NUM_SECONDS_IN_YEAR)); // Interest rate per second

        // utilizationInterestDivisor calculation (this is aiming for utilizationInterestDivisor to allow max change from 10% APR to be 11% APR despite using compound interest)
        // 1 + (globalInterestRateNumerator + (maxUtilizationDelta * RAY) / utilizationInterestDivisor) / NUM_SECONDS_IN_YEAR = 11% interest per second
        // utilizationInterestDivisor = (maxUtilizationDelta * RAY) / ( (11% interest per second - 1)(NUM_SECONDS_IN_YEAR) - globalInterestRateNumerator )
        // utilizationInterestDivisor = ((e^(ln(1.100)/(60*60*24*365)) - 1) * (60*60*24*365) * (10^27)) / ( (( e^(ln(1.110)/(60*60*24*365)) -1 ) * ( 60*60*24*365 )) - ((e^(ln(1.100)/(60*60*24*365)) - 1) * (60*60*24*365)))
    }

    /**
     * @dev Sets Loans contract
     * @param loans_ Address of Loans contract
     */
    function setLoans(Loans loans_) public {
        require(msg.sender == deployer);
        require(address(loans) == address(0));
        loans = loans_;
        require(token.approve(address(loans_), 2**256-1));
    }

    /**
     * @dev Enables assets in loan fund that haven't been borrowed to be lent on Compound
     * @param cToken_ The address of the Compound Token
     * @param comptroller_ The address of the Compound Comptroller
     */
    function setCompound(CTokenInterface cToken_, address comptroller_) public {
        require(msg.sender == deployer);
        require(!compoundSet);
        cToken = cToken_;
        comptroller = comptroller_;
        compoundSet = true;
    }

    // NOTE: THE FOLLOWING FUNCTIONS ALLOW VARIABLES TO BE MODIFIED BY THE 
    //       DEPLOYER, SINCE THE ALGORITHM FOR CALCULATING GLOBAL INTEREST 
    //       RATE IS UNTESTED WITH A DECENTRALIZED PROTOCOL, AND MAY NEED TO
    //       BE UPDATED IN THE CASE THAT RATES DO NOT UPDATE AS INTENDED. A 
    //       FUTURE ITERATION OF THE PROTOCOL WILL REMOVE THESE FUNCTIONS. IF 
    //       YOU WISH TO OPT OUT OF GLOBAL APR YOU CAN CREATE A CUSTOM LOAN FUND
    // ======================================================================

    /**
     * @dev Sets the Utilization Interest Divisor
     */
    function setUtilizationInterestDivisor(uint256 utilizationInterestDivisor_) external {
        require(msg.sender == deployer);
        utilizationInterestDivisor = utilizationInterestDivisor_;
    }

    /**
     * @dev Sets the Max Utilization Delta
     */
    function setMaxUtilizationDelta(uint256 maxUtilizationDelta_) external {
        require(msg.sender == deployer);
        maxUtilizationDelta = maxUtilizationDelta_;
    }

    /**
     * @dev Sets the Global Interest Rate Numerator
     */
    function setGlobalInterestRateNumerator(uint256 globalInterestRateNumerator_) external {
        require(msg.sender == deployer);
        globalInterestRateNumerator = globalInterestRateNumerator_;
    }

    /**
     * @dev Sets the Global Interest Rate
     */
    function setGlobalInterestRate(uint256 globalInterestRate_) external {
        require(msg.sender == deployer);
        globalInterestRate = globalInterestRate_;
    }

    /**
     * @dev Sets the Maximum Interest Rate Numerator
     */
    function setMaxInterestRateNumerator(uint256 maxInterestRateNumerator_) external {
        require(msg.sender == deployer);
        maxInterestRateNumerator = maxInterestRateNumerator_;
    }

    /**
     * @dev Sets the Minimum Interest Rate Numerator
     */
    function setMinInterestRateNumerator(uint256 minInterestRateNumerator_) external {
        require(msg.sender == deployer);
        minInterestRateNumerator = minInterestRateNumerator_;
    }

    /**
     * @dev Sets the Interest Update Delay
     */
    function setInterestUpdateDelay(uint256 interestUpdateDelay_) external {
        require(msg.sender == deployer);
        interestUpdateDelay = interestUpdateDelay_;
    }

    /**
     * @dev Sets the Default Arbiter Fee
     */
    function setDefaultArbiterFee(uint256 defaultArbiterFee_) external {
        require(msg.sender == deployer);
        require(defaultArbiterFee_ <= 1000000000315522921573372069); // ~1%
        defaultArbiterFee = defaultArbiterFee_;
    }
    // ======================================================================

    /**
     * @notice Get the lender of a Loan Fund
     * @param fund The Id of a Loan Fund
     * @return Owner address of Loan Fund
     */
    function lender(bytes32 fund) public view returns (address) {
        return funds[fund].lender;
    }

    /**
     * @notice Get minimum loan amount able to be requested by a 'borrower'
     * @param fund The Id of a Loan Fund
     * @return The minimum amount of tokens that can be requested from a Loan Fund
     */
    function minLoanAmt(bytes32 fund) public view returns (uint256) {
        if (bools[fund].custom) { return funds[fund].minLoanAmt; }
        else                    { return div(DEFAULT_MIN_LOAN_AMT, (10 ** sub(18, decimals))); }
    }

    /**
     * @notice Get maximum loan amount able to be requested by a 'borrower'
     * @param fund The Id of a Loan Fund
     * @return The maximum amount of tokens that can be requested from a Loan Fund
     */
    function maxLoanAmt(bytes32 fund) public view returns (uint256) {
        if (bools[fund].custom) { return funds[fund].maxLoanAmt; }
        else                    { return DEFAULT_MAX_LOAN_AMT; }
    }

    /**
     * @notice Get minimum loan duration able to be requested by a 'borrower'
     * @param fund The Id of a Loan Fund
     * @return The minimum duration loan that can be requested from a Loan Fund
     */
    function minLoanDur(bytes32 fund) public view returns (uint256) {
        if (bools[fund].custom) { return funds[fund].minLoanDur; }
        else                    { return DEFAULT_MIN_LOAN_DUR; }
    }

    /**
     * @notice Get maximum loan duration able to be requested by a 'borrower'
     * @param fund The Id of a Loan Fund
     * @return The maximum duration loan that can be requested from a Loan Fund
     */
    function maxLoanDur(bytes32 fund) public view returns (uint256) {
        return funds[fund].maxLoanDur;
    }

    /**
     * @notice Get maximum loan duration able to be requested by a 'borrower'
     * @param fund The Id of a Loan Fund
     * @return The maximum duration loan that can be requested from a Loan Fund
     */
    function fundExpiry(bytes32 fund) public view returns (uint256) {
        return funds[fund].fundExpiry;
    }

    /**
     * @notice Get the interest rate for a Loan Fund
     * @param fund The Id of a Loan Fund
     * @return The interest rate per second for a Loan Fund in RAY per second
     */
    function interest(bytes32 fund) public view returns (uint256) {
        if (bools[fund].custom) { return funds[fund].interest; }
        else                    { return globalInterestRate; }
    }

    /**
     * @notice Get the liquidation penalty rate for a Loan Fund
     * @param fund The Id of a Loan Fund
     * @return The liquidation penalty rate per second for a Loan Fund in RAY per second
     */
    function penalty(bytes32 fund) public view returns (uint256) {
        if (bools[fund].custom) { return funds[fund].penalty; }
        else                    { return DEFAULT_LIQUIDATION_PENALTY; }
    }

    /**
     * @notice Get the optional automation fee for a Loan Fund
     * @param fund The Id of a Loan Fund
     * @return The optional automation fee rate of Loan Fund in RAY per second
     */
    function fee(bytes32 fund) public view returns (uint256) {
        if (bools[fund].custom) { return funds[fund].fee; }
        else                    { return defaultArbiterFee; }
    }

    /**
     * @notice Get the liquidation ratio of a Loan Fund
     * @param fund The Id of a Loan Fund
     * @return The liquidation ratio of Loan Fund in RAY
     */
    function liquidationRatio(bytes32 fund) public view returns (uint256) {
        if (bools[fund].custom) { return funds[fund].liquidationRatio; }
        else                    { return DEFAULT_LIQUIDATION_RATIO; }
    }

    /**
     * @notice Get the arbiter for a Loan Fund
     * @param fund The Id of a Loan Fund
     * @return The address of the arbiter for a Loan fund
     */
    function arbiter(bytes32 fund) public view returns (address) {
        return funds[fund].arbiter;
    }

    /**
     * @notice Get the current balance of a Loan Fund in tokens
     * @param fund The Id of a Loan Fund
     * @return The amount of tokens remaining in Loan Fund
     */
    function balance(bytes32 fund) public returns (uint256) {
        if (bools[fund].compoundEnabled) {
            return wmul(funds[fund].cBalance, cToken.exchangeRateCurrent());
        } else {
            return funds[fund].balance;
        }
    }

    function cTokenExchangeRate() public returns (uint256) {
        if (compoundSet) {
            return cToken.exchangeRateCurrent();
        } else {
            return 0;
        }
    }

    /**
     * @notice Get the custom indicator for a Loan Fund
     * @param fund The Id of a Loan Fund
     * @return The indicator of whether a Loan Fund is custom or not
     */
    function custom(bytes32 fund) public view returns (bool) {
        return bools[fund].custom;
    }

    /**
     * @notice Get the number of secretHashes provided per address
     * @param addr_ The address of the user
     * @return The length of the secretHashes array for user address
     */
    function secretHashesCount(address addr_) external view returns (uint256) {
        return secretHashes[addr_].length;
    }

    /**
     * @notice Lenders create Loan Fund using Global Protocol parameters and deposit assets
     * @param maxLoanDur_ Max Loan Duration of Loan Fund in seconds
     * @param arbiter_  Optional address of arbiter
     * @param compoundEnabled_ Indicator whether excess funds should be lent on Compound
     * @param amount_ Amount of tokens to be deposited on creation
     * @return The Id of a Loan Fund
     *
     *         Note: Only one loan fund is allowed per ethereum address.
     *               Exception is made for the deployer for testing.
     */
    function create(
        uint256  maxLoanDur_,
        uint256  fundExpiry_,
        address  arbiter_,
        bool     compoundEnabled_,
        uint256  amount_
    ) external returns (bytes32 fund) { 
        require(funds[fundOwner[msg.sender]].lender != msg.sender || msg.sender == deployer); // Only allow one loan fund per address
        require(ensureNotZero(maxLoanDur_) != 2**256-1 || ensureNotZero(fundExpiry_) != 2**256-1); // Make sure someone can't request a loan for eternity
        if (!compoundSet) { require(compoundEnabled_ == false); }
        fundIndex = add(fundIndex, 1);
        fund = bytes32(fundIndex);
        funds[fund].lender           = msg.sender;
        funds[fund].maxLoanDur       = ensureNotZero(maxLoanDur_);
        funds[fund].fundExpiry       = ensureNotZero(fundExpiry_);
        funds[fund].arbiter          = arbiter_;
        bools[fund].custom           = false;
        bools[fund].compoundEnabled  = compoundEnabled_;
        fundOwner[msg.sender]        = bytes32(fundIndex);
        if (amount_ > 0) { deposit(fund, amount_); }

        emit Create(fund);
    }

    /**
     * @notice Lenders create Loan Fund using Custom parameters and deposit assets
     * @param minLoanAmt_ Minimum amount of tokens that can be borrowed from Loan Fund
     * @param maxLoanAmt_ Maximum amount of tokens that can be borrowed from Loan Fund
     * @param minLoanDur_ Minimum length of loan that can be requested from Loan Fund in seconds
     * @param maxLoanDur_ Maximum length of loan that can be requested from Loan Fund in seconds
     * @param arbiter_  Optional address of arbiter
     * @param compoundEnabled_ Indicator whether excess funds should be lent on Compound
     * @param amount_ Amount of tokens to be deposited on creation
     * @return The Id of a Loan Fund
     *
     *         Note: Only one loan fund is allowed per ethereum address.
     *               Exception is made for the deployer for testing.
     */
    function createCustom(
        uint256  minLoanAmt_,
        uint256  maxLoanAmt_,
        uint256  minLoanDur_,
        uint256  maxLoanDur_,
        uint256  fundExpiry_,
        uint256  liquidationRatio_,
        uint256  interest_,
        uint256  penalty_,
        uint256  fee_,
        address  arbiter_,
        bool     compoundEnabled_,
        uint256  amount_
    ) external returns (bytes32 fund) {
        require(funds[fundOwner[msg.sender]].lender != msg.sender || msg.sender == deployer); // Only allow one loan fund per address
        require(ensureNotZero(maxLoanDur_) != 2**256-1 || ensureNotZero(fundExpiry_) != 2**256-1); // Make sure someone can't request a loan for eternity
        if (!compoundSet) { require(compoundEnabled_ == false); }
        fundIndex = add(fundIndex, 1);
        fund = bytes32(fundIndex);
        funds[fund].lender           = msg.sender;
        funds[fund].minLoanAmt       = minLoanAmt_;
        funds[fund].maxLoanAmt       = maxLoanAmt_;
        funds[fund].minLoanDur       = minLoanDur_;
        funds[fund].maxLoanDur       = ensureNotZero(maxLoanDur_);
        funds[fund].fundExpiry       = ensureNotZero(fundExpiry_);
        funds[fund].interest         = interest_;
        funds[fund].penalty          = penalty_;
        funds[fund].fee              = fee_;
        funds[fund].liquidationRatio = liquidationRatio_;
        funds[fund].arbiter          = arbiter_;
        bools[fund].custom           = true;
        bools[fund].compoundEnabled  = compoundEnabled_;
        fundOwner[msg.sender]        = bytes32(fundIndex);
        if (amount_ > 0) { deposit(fund, amount_); }

        emit Create(fund);
    }

    /**
     * @notice Lenders deposit tokens in Loan Fund
     * @param fund The Id of a Loan Fund
     * @param amount Amount of tokens to deposit
     *
     *        Note: Anyone can deposit tokens into a Loan Fund
     */
    function deposit(bytes32 fund, uint256 amount) public {
        require(token.transferFrom(msg.sender, address(this), amount));
        if (bools[fund].compoundEnabled) {
            mintCToken(address(token), address(cToken), amount);
            uint256 cTokenToAdd = div(mul(amount, WAD), cToken.exchangeRateCurrent());
            funds[fund].cBalance = add(funds[fund].cBalance, cTokenToAdd);
            if (!custom(fund)) { cTokenMarketLiquidity = add(cTokenMarketLiquidity, cTokenToAdd); }
        } else {
            funds[fund].balance = add(funds[fund].balance, amount);
            if (!custom(fund)) { tokenMarketLiquidity = add(tokenMarketLiquidity, amount); }
        }
        if (!custom(fund)) { calcGlobalInterest(); }
    }

    /**
     * @notice Users update Loan Fund settings
     * @param fund The Id of a Loan Fund
     * @param maxLoanDur_ Maximum length of loan that can be requested from Loan Fund in seconds
     * @param fundExpiry_ Timestamp when all funds should be removable from Loan Fund
     * @param arbiter_ The address of the arbiter for a Loan fund
     *
     *        Note: msg.sender must be the lender of the Loan Fund
     */
    function update(
        bytes32  fund,
        uint256  maxLoanDur_,
        uint256  fundExpiry_,
        address  arbiter_
    ) public {
        require(msg.sender == lender(fund));
        require(ensureNotZero(maxLoanDur_) != 2**256-1 || ensureNotZero(fundExpiry_) != 2**256-1); // Make sure someone can't request a loan for eternity
        funds[fund].maxLoanDur       = maxLoanDur_;
        funds[fund].fundExpiry       = fundExpiry_;
        funds[fund].arbiter          = arbiter_;
    }

    /**
     * @notice Users update custom Loan Fund settings
     * @param fund The Id of a Loan Fund
     * @param minLoanAmt_ Minimum amount of tokens that can be borrowed from Loan Fund
     * @param maxLoanAmt_ Maximum amount of tokens that can be borrowed from Loan Fund
     * @param minLoanDur_ Minimum length of loan that can be requested from Loan Fund in seconds
     * @param maxLoanDur_ Maximum length of loan that can be requested from Loan Fund in seconds
     * @param fundExpiry_ Timestamp when all funds should be removable from Loan Fund
     * @param interest_ The interest rate per second for a Loan Fund in RAY per second
     * @param penalty_ The liquidation penalty rate per second for a Loan Fund in RAY per second
     * @param fee_ The optional automation fee rate of Loan Fund in RAY per second
     * @param liquidationRatio_ The liquidation ratio of Loan Fund in RAY
     * @param arbiter_ The address of the arbiter for a Loan fund
     *
     *        Note: msg.sender must be the lender of the Loan Fund
     */
    function updateCustom(
        bytes32  fund,
        uint256  minLoanAmt_,
        uint256  maxLoanAmt_,
        uint256  minLoanDur_,
        uint256  maxLoanDur_,
        uint256  fundExpiry_,
        uint256  interest_,
        uint256  penalty_,
        uint256  fee_,
        uint256  liquidationRatio_,
        address  arbiter_
    ) external {
        require(bools[fund].custom);
        update(fund, maxLoanDur_, fundExpiry_, arbiter_);
        funds[fund].minLoanAmt       = minLoanAmt_;
        funds[fund].maxLoanAmt       = maxLoanAmt_;
        funds[fund].minLoanDur       = minLoanDur_;
        funds[fund].interest         = interest_;
        funds[fund].penalty          = penalty_;
        funds[fund].fee              = fee_;
        funds[fund].liquidationRatio = liquidationRatio_;
    }

    /**
     * @notice Lenders request loan from Loan Fund on behalf of Borrower
     * @param fund The Id of a Loan Fund
     * @param amount_ Amount of tokens to request
     * @param collateral_ Amount of collateral to deposit in satoshis
     * @param loanDur_ Length of loan request in seconds
     * @param secretHashes_ 4 Borrower Secret Hashes and 4 Lender Secret Hashes
     * @param pubKeyA_ Borrower Bitcoin public key to use for refunding collateral
     * @param pubKeyB_ Lender Bitcoin public key to use for refunding collateral
     *
     *        Note: Borrower client should verify params after Ethereum tx
     *              confirmation before locking Bitcoin.
     *
     */
    function request(
        bytes32             fund,
        address             borrower_,
        uint256             amount_,
        uint256             collateral_,
        uint256             loanDur_,
        uint256             requestTimestamp_,
        bytes32[8] calldata secretHashes_,
        bytes      calldata pubKeyA_,
        bytes      calldata pubKeyB_
    ) external returns (bytes32 loanIndex) {
        require(msg.sender == lender(fund));
        require(amount_    <= balance(fund));
        require(amount_    >= minLoanAmt(fund));
        require(amount_    <= maxLoanAmt(fund));
        require(loanDur_   >= minLoanDur(fund));
        require(loanDur_   <= sub(fundExpiry(fund), now) && loanDur_ <= maxLoanDur(fund));

        loanIndex = createLoan(fund, borrower_, amount_, collateral_, loanDur_, requestTimestamp_);
        loanSetSecretHashes(fund, loanIndex, secretHashes_, pubKeyA_, pubKeyB_);
        loanUpdateMarketLiquidity(fund, amount_);
        loans.fund(loanIndex);
    }

    /**
     * @notice Lenders withdraw tokens in Loan Fund
     * @param fund The Id of a Loan Fund
     * @param amount Amount of tokens to withdraw
     */
    function withdraw(bytes32 fund, uint256 amount) external {
        withdrawTo(fund, amount, msg.sender);
    }

    /**
     * @notice Lenders withdraw tokens in Loan Fund
     * @param fund The Id of a Loan Fund
     * @param amount Amount of tokens to withdraw
     * @param recipient Address that should receive the funds
     */
    function withdrawTo(bytes32 fund, uint256 amount, address recipient) public {
        require(msg.sender     == lender(fund));
        require(balance(fund)  >= amount);
        if (bools[fund].compoundEnabled) {
            uint256 cBalanceBefore = cToken.balanceOf(address(this));
            redeemUnderlying(address(cToken), amount);
            uint256 cBalanceAfter = cToken.balanceOf(address(this));
            uint256 cTokenToRemove = sub(cBalanceBefore, cBalanceAfter);
            funds[fund].cBalance = sub(funds[fund].cBalance, cTokenToRemove);
            require(token.transfer(recipient, amount));
            if (!custom(fund)) { cTokenMarketLiquidity = sub(cTokenMarketLiquidity, cTokenToRemove); }
        } else {
            funds[fund].balance = sub(funds[fund].balance, amount);
            require(token.transfer(recipient, amount));
            if (!custom(fund)) { tokenMarketLiquidity = sub(tokenMarketLiquidity, amount); }
        }
        if (!custom(fund)) { calcGlobalInterest(); }
    }

    /**
     * @notice Submit secretHashes to be used with future loans
     * @param secretHashes_ List of secretHashes
     */
    function generate(bytes32[] calldata secretHashes_) external {
        for (uint i = 0; i < secretHashes_.length; i++) {
            secretHashes[msg.sender].push(secretHashes_[i]);
        }
    }

    /**
     * @notice Set Lender or Arbiter Bitcoin Public Key
     * @param pubKey Bitcoin Public Key
     */
    function setPubKey(bytes calldata pubKey) external { // Set PubKey for Fund
        pubKeys[msg.sender] = pubKey;
    }

    /**
     * @notice Enable Compound for Loan Fund
     * @param fund The Id of a Loan Fund
     */
    function enableCompound(bytes32 fund) external {
        require(compoundSet);
        require(bools[fund].compoundEnabled == false);
        require(msg.sender == lender(fund));
        uint256 cBalanceBefore = cToken.balanceOf(address(this));
        mintCToken(address(token), address(cToken), funds[fund].balance);
        uint256 cBalanceAfter = cToken.balanceOf(address(this));
        uint256 cTokenToReturn = sub(cBalanceAfter, cBalanceBefore);
        tokenMarketLiquidity = sub(tokenMarketLiquidity, funds[fund].balance);
        cTokenMarketLiquidity = add(cTokenMarketLiquidity, cTokenToReturn);
        bools[fund].compoundEnabled = true;
        funds[fund].balance = 0;
        funds[fund].cBalance = cTokenToReturn;
    }

    /**
     * @notice Disable Compound for Loan Fund
     * @param fund The Id of a Loan Fund
     */
    function disableCompound(bytes32 fund) external {
        require(bools[fund].compoundEnabled);
        require(msg.sender == lender(fund));
        uint256 balanceBefore = token.balanceOf(address(this));
        redeemCToken(address(cToken), funds[fund].cBalance);
        uint256 balanceAfter = token.balanceOf(address(this));
        uint256 tokenToReturn = sub(balanceAfter, balanceBefore);
        tokenMarketLiquidity = add(tokenMarketLiquidity, tokenToReturn);
        cTokenMarketLiquidity = sub(cTokenMarketLiquidity, funds[fund].cBalance);
        bools[fund].compoundEnabled = false;
        funds[fund].cBalance = 0;
        funds[fund].balance = tokenToReturn;
    }

    /**
     * @notice Decrease Total Borrow by Loans contract
     * @param amount The amount of tokens to decrease totalBorrow by
     */
    function decreaseTotalBorrow(uint256 amount) external {
        require(msg.sender == address(loans));
        totalBorrow = sub(totalBorrow, amount);
    }

    /**
     * @notice Calculate and update Global Interest Rate
     * @dev Implementation returns Global Interest Rate per second in RAY
     *      
     *      Note: Only updates interest rate if interestUpdateDelay has passed since last update
     *            if utilizationRatio increases newAPR = oldAPR + (min(10%, utilizationRatio) / 10)
     *            if utilizationRatio decreases newAPR = oldAPR - (max(10%, utilizationRatio) / 10)
     *            ΔAPR should be less than or equal to 1%
     *            For every 10% change in utilization ratio, the interest rate will change a maximum of 1%
     *            i.e. newAPR = 11.5% + (10% / 10) = 12.5%
     *
     */
    function calcGlobalInterest() public {
        marketLiquidity = add(tokenMarketLiquidity, wmul(cTokenMarketLiquidity, cTokenExchangeRate()));

        if (now > (lastGlobalInterestUpdated + interestUpdateDelay)) {
            uint256 utilizationRatio;
            if (totalBorrow != 0) { utilizationRatio = rdiv(totalBorrow, add(marketLiquidity, totalBorrow)); }

            if (utilizationRatio > lastUtilizationRatio) {
                uint256 changeUtilizationRatio = sub(utilizationRatio, lastUtilizationRatio);
                globalInterestRateNumerator = min(maxInterestRateNumerator, add(globalInterestRateNumerator, rdiv(min(maxUtilizationDelta, changeUtilizationRatio), utilizationInterestDivisor)));
            } else {
                uint256 changeUtilizationRatio = sub(lastUtilizationRatio, utilizationRatio);
                globalInterestRateNumerator = max(minInterestRateNumerator, sub(globalInterestRateNumerator, rdiv(min(maxUtilizationDelta, changeUtilizationRatio), utilizationInterestDivisor)));
            }

            globalInterestRate = add(RAY, div(globalInterestRateNumerator, NUM_SECONDS_IN_YEAR));

            lastGlobalInterestUpdated = now;
            lastUtilizationRatio = utilizationRatio;
        }
    }

    /*
     * @notice Calculate compound interest for a length of time
     * @param amount The amount of tokens
     * @param rate The interest rate in seconds
     * @param loanDur The loan duration in seconds
     */
    function calcInterest(uint256 amount, uint256 rate, uint256 loanDur) public pure returns (uint256) {
        return sub(rmul(amount, rpow(rate, loanDur)), amount);
    }

    /*
     * @dev Ensure null values for fundExpiry and maxLoanDur are set to 2**256-1
     * @param value The value to be sanity checked
     */
    function ensureNotZero(uint256 value) public pure returns (uint256) {
        if (value == 0) { return 2**256-1; }
        else            { return value; }
    }

    /*
     * @dev Takes loan request parameters, creates loan, and returns loanIndex
     * @param fund The Id of a Loan Fund
     * @param amount_ Amount of tokens to request
     * @param collateral_ Amount of collateral to deposit in satoshis
     * @param loanDur_ Length of loan request in seconds     
     */
    function createLoan(
        bytes32  fund,
        address  borrower_,
        uint256  amount_,
        uint256  collateral_,
        uint256  loanDur_,
        uint256  requestTimestamp_
    ) private returns (bytes32 loanIndex) {
        loanIndex = loans.create(
            now + loanDur_,
            [ borrower_, lender(fund), funds[fund].arbiter],
            [ amount_, calcInterest(amount_, interest(fund), loanDur_), calcInterest(amount_, penalty(fund), loanDur_), calcInterest(amount_, fee(fund), loanDur_), collateral_, liquidationRatio(fund), requestTimestamp_],
            fund
        );
    }

    /*
     * @dev Takes loan request Bitcoin parameters, sets loan Public Keys and Secret Hashes
     * @param fund The Id of the Loan Fund
     * @param loan The Id of the Loan
     * @param secretHashes_ 4 Borrower Secret Hashes and 4 Lender Secret Hashes
     * @param pubKeyA_ Borrower Bitcoin public key to use for refunding collateral
     * @param pubKeyB_ Lender Bitcoin public key to use for refunding collateral
     */
    function loanSetSecretHashes(
        bytes32           fund,
        bytes32           loan,
        bytes32[8] memory secretHashes_,
        bytes      memory pubKeyA_,
        bytes      memory pubKeyB_
    ) private {
        loans.setSecretHashes(
            loan,
            [ secretHashes_[0], secretHashes_[1], secretHashes_[2], secretHashes_[3] ],
            [ secretHashes_[4], secretHashes_[5], secretHashes_[6], secretHashes_[7] ],
            getSecretHashesForLoan(arbiter(fund)),
            pubKeyA_,
            pubKeyB_,
            pubKeys[arbiter(fund)]
        );
    }

    /*
     * @dev Updates market liquidity based on amount of tokens being requested to borrow
     * @param fund Loan Id of the Loan Fund
     * @param amount The amount of tokens that are being requested
     */
    function loanUpdateMarketLiquidity(bytes32 fund, uint256 amount) private {
        if (bools[fund].compoundEnabled) {
            uint256 cBalanceBefore = cToken.balanceOf(address(this));
            redeemUnderlying(address(cToken), amount);
            uint256 cBalanceAfter = cToken.balanceOf(address(this));
            uint256 cTokenToRemove = sub(cBalanceBefore, cBalanceAfter);
            funds[fund].cBalance = sub(funds[fund].cBalance, cTokenToRemove);
            if (!custom(fund)) { cTokenMarketLiquidity = sub(cTokenMarketLiquidity, cTokenToRemove); }
        } else {
            funds[fund].balance = sub(funds[fund].balance, amount);
            if (!custom(fund)) { tokenMarketLiquidity = sub(tokenMarketLiquidity, amount); }
        }
        if (!custom(fund)) {
            totalBorrow = add(totalBorrow, amount);
            calcGlobalInterest();
        }
    }

    /*
     * @dev Get the next 4 secret hashes required for loan
     * @param addr Address of Lender or Arbiter
     */
    function getSecretHashesForLoan(address addr) private returns (bytes32[4] memory) {
        secretHashIndex[addr] = add(secretHashIndex[addr], 4);
        return [
            secretHashes[addr][sub(secretHashIndex[addr], 4)],
            secretHashes[addr][sub(secretHashIndex[addr], 3)],
            secretHashes[addr][sub(secretHashIndex[addr], 2)],
            secretHashes[addr][sub(secretHashIndex[addr], 1)]
        ];
    }
}
