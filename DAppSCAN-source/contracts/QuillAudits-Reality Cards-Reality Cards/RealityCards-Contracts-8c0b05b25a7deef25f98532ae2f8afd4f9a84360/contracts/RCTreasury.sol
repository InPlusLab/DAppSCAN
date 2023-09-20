pragma solidity 0.5.13;

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "hardhat/console.sol";
import './lib/NativeMetaTransaction.sol';

/// @title Reality Cards Treasury
/// @author Andrew Stanger
/// @notice If you have found a bug, please contact andrew@realitycards.io- no hack pls!!
contract RCTreasury is Ownable, NativeMetaTransaction {

    using SafeMath for uint256;

    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    /// @dev address of the Factory so only the Factory can add new markets
    address public factoryAddress;
    /// @dev so only markets can use certain functions
    mapping (address => bool) public isMarket;
    /// @dev the deposit balance of each user
    mapping (address => uint256) public deposits;
    /// @dev sum of all deposits 
    uint256 public totalDeposits;
    /// @dev the rental payments made in each market
    mapping (address => uint256) public marketPot;
    /// @dev sum of all market pots 
    uint256 public totalMarketPots;
    /// @dev sum of prices of all Cards a user is renting
    mapping (address => uint256) public userTotalRentals;
    /// @dev when a user most recently rented (to prevent users withdrawing within minRentalTime)
    mapping (address => uint256) public lastRentalTime;

     ///// GOVERNANCE VARIABLES /////
    /// @dev only parameters that need to be are here, the rest are in the Factory
    /// @dev minimum rental duration (1 day divisor: i.e. 24 = 1 hour, 48 = 30 mins)
    uint256 public minRentalDivisor;
    /// @dev max deposit balance, to minimise funds at risk
    uint256 public maxContractBalance;

    ///// SAFETY /////
    /// @dev if true, cannot deposit, withdraw or rent any cards across all events
    bool public globalPause;
    /// @dev if true, cannot rent any cards for specific market
    mapping (address => bool) public marketPaused;

    ///// UBER OWNER /////
    /// @dev high level owner who can change the factory address
    address public uberOwner;

    ////////////////////////////////////
    //////// EVENTS ////////////////////
    ////////////////////////////////////

    event LogDepositIncreased(address indexed sentBy, uint256 indexed daiDeposited);
    event LogDepositWithdrawal(address indexed returnedTo, uint256 indexed daiWithdrawn);
    event LogAdjustDeposit(address indexed user, uint256 indexed amount, bool increase);
    event LogHotPotatoPayment(address from, address to, uint256 amount);

    ////////////////////////////////////
    //////// CONSTRUCTOR ///////////////
    ////////////////////////////////////

    constructor() public {
        // initialise MetaTransactions
        _initializeEIP712("RealityCardsTreasury","1");

        // at initiation, uberOwner and owner will be the same
        uberOwner = msg.sender;

        // initialise adjustable parameters
        setMinRental(24*6); // ten mins
        setMaxContractBalance(1000000 ether); // 1m
    }

    ////////////////////////////////////
    /////////// MODIFIERS //////////////
    ////////////////////////////////////

    modifier balancedBooks {
        _;
        // using >= not == because forced Ether send via selfdestruct will not trigger a deposit via the fallback
        // SWC-101-Integer Overflow and Underflow: L85
        assert(address(this).balance >= totalDeposits + totalMarketPots);
    }

    modifier onlyMarkets {
        require(isMarket[msg.sender], "Not authorised");
        _;
    }

    ////////////////////////////////////
    //////////// ADD MARKETS ///////////
    ////////////////////////////////////

    /// @dev so only markets can move funds from deposits to marketPots and vice versa
    function addMarket(address _newMarket) external returns(bool) {
        require(msg.sender == factoryAddress, "Not factory");
        isMarket[_newMarket] = true;
        return true;
    }

    ////////////////////////////////////
    /////// GOVERNANCE- OWNER //////////
    ////////////////////////////////////
    /// @dev all functions should be onlyOwner
    // min rental event emitted by market. Nothing else need be emitted.

    /// CALLED WITHIN CONSTRUCTOR (public)

    /// @notice minimum rental duration (1 day divisor: i.e. 24 = 1 hour, 48 = 30 mins)
    function setMinRental(uint256 _newDivisor) public onlyOwner {
        minRentalDivisor = _newDivisor;
    }

    /// @dev max deposit balance, to minimise funds at risk
    function setMaxContractBalance(uint256 _newBalanceLimit) public onlyOwner {
        maxContractBalance = _newBalanceLimit;
    }

    /// NOT CALLED WITHIN CONSTRUCTOR (external)

    /// @dev if true, cannot deposit, withdraw or rent any cards
    function setGlobalPause() external onlyOwner {
        globalPause = globalPause ? false : true;
    }

    /// @dev if true, cannot rent any cards for specific market
    function setPauseMarket(address _market) external onlyOwner {
        marketPaused[_market] = marketPaused[_market] ? false : true;
    }

    ////////////////////////////////////
    ////// GOVERNANCE- UBER OWNER //////
    ////////////////////////////////////
    //// ******** DANGER ZONE ******** ////
    /// @dev uber owner required for upgrades
    /// @dev deploying and setting a new factory is effectively an upgrade
    /// @dev this is seperated so owner so can be set to multisig, or burn address to relinquish upgrade ability
    /// @dev ... while maintaining governance over other governanace functions

    function setFactoryAddress(address _newFactory) external {
        require(msg.sender == uberOwner, "Extremely Verboten");
        factoryAddress = _newFactory;
    }

    function changeUberOwner(address _newUberOwner) external {
        require(msg.sender == uberOwner, "Extremely Verboten");
        uberOwner = _newUberOwner;
    }

    ////////////////////////////////////
    /// DEPOSIT & WITHDRAW FUNCTIONS ///
    ////////////////////////////////////

    /// @dev it is passed the user instead of using msg.sender because might be called
    /// @dev ... via contract (fallback, newRental) or dai->xdai bot
    function deposit(address _user) public payable balancedBooks returns(bool) {
        require(!globalPause, "Deposits are disabled");
        require(msg.value > 0, "Must deposit something");
        require(address(this).balance <= maxContractBalance, "Limit hit");

        deposits[_user] = deposits[_user].add(msg.value);
        totalDeposits = totalDeposits.add(msg.value);
        emit LogDepositIncreased(_user, msg.value);
        emit LogAdjustDeposit(_user, msg.value, true);
        return true;
    }

    /// @dev this is the only function where funds leave the contract
    function withdrawDeposit(uint256 _dai) external balancedBooks  {
        require(!globalPause, "Withdrawals are disabled");
        require(deposits[msgSender()] > 0, "Nothing to withdraw");
        require(now.sub(lastRentalTime[msgSender()]) > uint256(1 days).div(minRentalDivisor), "Too soon");

        if (_dai > deposits[msgSender()]) {
            _dai = deposits[msgSender()];
        }
        deposits[msgSender()] = deposits[msgSender()].sub(_dai);
        totalDeposits = totalDeposits.sub(_dai);
        address _thisAddressNotPayable = msgSender();
        address payable _recipient = address(uint160(_thisAddressNotPayable));
        (bool _success, ) = _recipient.call.value(_dai)("");
        require(_success, "Transfer failed");
        emit LogDepositWithdrawal(msgSender(), _dai);
        emit LogAdjustDeposit(msgSender(), _dai, false);
    }

    ////////////////////////////////////
    //////    MARKET CALLABLE     //////
    ////////////////////////////////////
    /// only markets can call these functions

    /// @dev a rental payment is equivalent to moving to market pot from user's deposit, called by _collectRent in the market
    function payRent(address _user, uint256 _dai) external balancedBooks onlyMarkets returns(bool) {
        require(!globalPause, "Rentals are disabled");
        require(!marketPaused[msg.sender], "Rentals are disabled");
        assert(deposits[_user] >= _dai); // assert because should have been reduced to user's deposit already
        deposits[_user] = deposits[_user].sub(_dai);
        marketPot[msg.sender] = marketPot[msg.sender].add(_dai);
        totalMarketPots = totalMarketPots.add(_dai);
        totalDeposits = totalDeposits.sub(_dai);
        emit LogAdjustDeposit(_user, _dai, false);
        return true;
    }

    /// @dev a payout is equivalent to moving from market pot to user's deposit (the opposite of payRent)
    function payout(address _user, uint256 _dai) external balancedBooks onlyMarkets returns(bool) {
        assert(marketPot[msg.sender] >= _dai); 
        deposits[_user] = deposits[_user].add(_dai);
        marketPot[msg.sender] = marketPot[msg.sender].sub(_dai);
        totalMarketPots = totalMarketPots.sub(_dai);
        totalDeposits = totalDeposits.add(_dai);
        emit LogAdjustDeposit(_user, _dai, true);
        return true;
    }

    /// @notice ability to add liqudity to the pot without being able to win (called by market sponsor function). 
    function sponsor() external payable balancedBooks onlyMarkets returns(bool) {
        marketPot[msg.sender] = marketPot[msg.sender].add(msg.value);
        totalMarketPots = totalMarketPots.add(msg.value);
        return true;
    }

    /// @dev new owner pays current owner for hot potato mode
    function processHarbergerPayment(address _newOwner, address _currentOwner, uint256 _requiredPayment) external balancedBooks onlyMarkets returns(bool) {
        require(deposits[_newOwner] >= _requiredPayment, "Insufficient deposit");
        deposits[_newOwner] = deposits[_newOwner].sub(_requiredPayment);
        deposits[_currentOwner] = deposits[_currentOwner].add(_requiredPayment);
        emit LogAdjustDeposit(_newOwner, _requiredPayment, false);
        emit LogAdjustDeposit(_currentOwner, _requiredPayment, true);
        emit LogHotPotatoPayment(_newOwner, _currentOwner, _requiredPayment);
        return true;
    }

    /// @dev tracks when the user last rented- so they cannot rent and immediately withdraw, thus bypassing minimum rental duration
    function updateLastRentalTime(address _user) external onlyMarkets returns(bool) {
        lastRentalTime[_user] = now;
        return true;
    }

    /// @dev tracks the total rental payments across all Cards, to enforce minimum rental duration
    function updateTotalRental(address _user, uint256 _newPrice, bool _add) external onlyMarkets returns(bool) {
        if (_add) {
            userTotalRentals[_user] = userTotalRentals[_user].add(_newPrice);
        } else {
            userTotalRentals[_user] = userTotalRentals[_user].sub(_newPrice);
        }
        return true;
    }

    ////////////////////////////////////
    //////////    FALLBACK     /////////
    ////////////////////////////////////
 
    /// @dev sending ether/xdai direct is equal to a deposit
    function() external payable {
        assert(deposit(msgSender()));
    }

}
