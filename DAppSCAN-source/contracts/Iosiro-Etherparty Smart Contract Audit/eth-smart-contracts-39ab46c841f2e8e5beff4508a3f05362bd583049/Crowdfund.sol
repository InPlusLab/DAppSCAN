pragma solidity 0.4.24;

import "./library/SafeMath.sol";
import "./library/CanReclaimToken.sol";
import "./library/NonZero.sol";
import "./Token.sol";


contract Crowdfund is NonZero, CanReclaimToken {

    using SafeMath for uint;

    /////////////////////// VARIABLE INITIALIZATION ///////////////////////

    // Amount of wei currently raised
    uint256 public weiRaised = 0;
    // Timestamp of when the crowdfund starts
    uint256 public startsAt;
    // Timestamp of when the crowdfund ends
    uint256 public endsAt;
    // Instance of the Token contract
    Token public token;
    // Whether the crowdfund is Activated (scheduled to start) state
    bool public isActivated = false;
    // Flag keeping track of crowdsale status. Ensures closeCrowdfund() can only be called once and kill() only after closing the crowdfund
    bool public crowdfundFinalized = false;


    // Our own vars
    // Address of a secure wallet to send ETH/SBTC crowdfund contributions to
    address public wallet;
    // Address to forward the tokens to at the end of the Crowdfund (can be 0x0 for burning tokens)
    address public forwardTokensTo;
    // Total length of the crowdfund
    uint256 public crowdfundLength;
    // If they want to whitelist crowdfund contributors
    bool public withWhitelist;


    // This struct keeps the rates of tokens per epoch
    struct Rate {
        uint256 price;
        uint256 amountOfDays;
    }

    // Array of token rates for each epoch
    Rate[] public rates;

    mapping (address => bool) public whitelist;


    /////////////////////// EVENTS ///////////////////////

    // Emmitted upon purchasing tokens
    event TokenPurchase(address indexed purchaser, uint256 value, uint256 amount);

    /////////////////////// MODIFIERS ///////////////////////
//SWC-116-Block values as a proxy for time:L61、68、76、162、173、180
    // Ensure the crowdfund is ongoing
    modifier duringCrowdfund() {
        require(now >= startsAt && now <= endsAt, "time must be greater than start but less than end");
        _;
    }

    // Ensure actions can only happen after crowdfund ends
    modifier onlyAfterCrowdfund() {
        require(endsAt > 0, "crowdfund end time must be greater than 0");
        require(now > endsAt || getCrowdFundAllocation() == 0, "current time must be greater than 0 or there must be 0 tokens left");
        _;
    }



    // Ensure actions can only happen before the crowdfund
    modifier onlyBeforeCrowdfund() {
        require(now <= startsAt, "time must be less than or equal to start time");
        _;
    }

    // Modifier that looks if this is whitelisted
    modifier isWhitelisted(address _beneficiary) {
        if (withWhitelist == true) {
            require(whitelist[_beneficiary], "address must be whitelisted");
        }
        _;
    }

    /////////////////////// CROWDFUND FUNCTIONS ///////////////////////

    /**
     * @dev Constructor
     * @param _owner The address of the contract owner
     * @param _epochs Array of the length of epoch per specific token price (in days)
     * @param _prices Array of the prices for each price epoch
     * @param _wallet Wallet address where ETH/SBTC will be transferred into
     * @param _forwardTokensTo Address to forward the tokens to
     * @param _totalDays Length of the crowdfund in days
     * @param _totalSupply Total Supply of the token
     * @param _allocAddresses Array of allocation addresses
     * @param _allocBalances Array of allocation balances
     * @param _timelocks Array of timelocks for all the allocations
     */
    constructor(
        address _owner,
        uint256[] memory _epochs,
        uint256[] memory _prices,
        address _wallet,
        address _forwardTokensTo,
        uint256 _totalDays,
        uint256 _totalSupply,
        bool _withWhitelist,
        address[] memory _allocAddresses,
        uint256[] memory _allocBalances,
        uint256[] memory _timelocks
        ) public {

        // Change the owner to the owner address.
        owner = _owner;
        // If the user wants a whitelist or not
        withWhitelist = _withWhitelist;
        // Wallet where ETH/SBTC will be forwarded to
        wallet = _wallet;
        // Address where leftover tokens will be forwarded to
        forwardTokensTo = _forwardTokensTo; 
        // Crowdfund length is in seconds
        crowdfundLength = _totalDays.mul(1 days);

        // Ensure the prices per epoch passed in are the same length and limit the size of the array
        require(_epochs.length == _prices.length && _prices.length <= 10, "array lengths must be equal and at most 10 elements");

        // Keep track of the amount of days -- this will determine which epoch we are in
        uint256 totalAmountOfDays = 0;
        // Push all of them to the rates array
        for (uint8 i = 0; i < _epochs.length; i++) {
            totalAmountOfDays = totalAmountOfDays.add(_epochs[i]);
            rates.push(Rate(_prices[i], totalAmountOfDays));
            // So here we will have [rate(100, 7), rate(50, 14)]
            // Meaning that for the first week, the rate is 100, then then after 7 days, it becomes 50
        }
        // Ensure that the total amount of days is the expected amount
        assert(totalAmountOfDays == _totalDays);

        // Create the token contract
        token = new Token(owner, _totalSupply, _allocAddresses, _allocBalances, _timelocks); // Create new Token

    }

    /**
     * @dev Called by the owner or the contract to schedule the crowdfund
     * @param _startDate The start date Timestamp
     */
    function scheduleCrowdfund(uint256 _startDate) external onlyOwner returns(bool) {
        // Crowdfund cannot be already activated
        require(isActivated == false);
        startsAt = _startDate;
        // Change the start time on the token contract too, as the vesting period changes
        if (!token.changeCrowdfundStartTime(startsAt)) {
            revert();
        }
        endsAt = startsAt.add(crowdfundLength);
        isActivated = true;
        assert(startsAt >= now && endsAt > startsAt);
        return true;
    }

    /**
     * @dev Called by the owner of the contract to reschedule the start of the crowdfund
     * @param _startDate The start date timestamp
     *
     */
    function reScheduleCrowdfund(uint256 _startDate) external onlyOwner returns(bool) {
        // We require this function to only be called 4 hours before the crowfund starts and the crowdfund has been scheduled
        require(now < startsAt.sub(4 hours) && isActivated == true, "must be 4 hours less than start and must be activated");
        startsAt = _startDate;
        // Change the start time on the token contract too, as the vesting period changes
        if (!token.changeCrowdfundStartTime(startsAt)) {
            revert();
        }
        endsAt = startsAt.add(crowdfundLength);
        assert(startsAt >= now && endsAt > startsAt);
        return true;
    }

    /**
     * @dev Change the main contribution wallet
     * @param _wallet The new contribution wallet address
     */
    function changeWalletAddress(address _wallet) external onlyOwner nonZeroAddress(_wallet) {
        wallet = _wallet;
    }

    /**
     * @dev Change the token forward address. This can be the 0 address.
     * @param _forwardTokensTo The new contribution wallet address
     */
    function changeForwardAddress(address _forwardTokensTo) external onlyOwner {
        forwardTokensTo = _forwardTokensTo;
    }

    /**
     * @dev Buys tokens at the current rate
     * @param _to The address the bought tokens are sent to
     */
    function buyTokens(address _to) public payable duringCrowdfund nonZeroAddress(_to) nonZeroValue isWhitelisted(msg.sender)  {
        uint256 weiAmount = msg.value;
        // Get the total rate of tokens
        uint256 tokens = weiAmount.mul(getRate());
        weiRaised = weiRaised.add(weiAmount);
        // Transfer out the ETH to our wallet
        wallet.transfer(weiAmount);
        // Here the msg.sender is the crowdfund, so we take tokens from the crowdfund allocation
        if (!token.moveAllocation(_to, tokens)) {
            revert("failed to move allocation");
        }
        emit TokenPurchase(_to, weiAmount, tokens);
    }

    /**
     * @dev Closes the crowdfund only after the crowdfund ends and by the owner
     * @return bool True if closed successfully else false
     */
    function closeCrowdfund() external onlyAfterCrowdfund onlyOwner returns (bool success) {
        require(crowdfundFinalized == false, "crowdfund must not be finalized");
        uint256 amount = getCrowdFundAllocation();
        if (amount > 0) {
            // Transfer all of the tokens out to the final address (if burning, send to 0x0)
            if (!token.moveAllocation(forwardTokensTo, amount)) {
                revert("failed to move allocation");
            }
        }
        // Unlock the tokens
        if (!token.unlockTokens()) {
            revert("failed to move allocation");
        }
        crowdfundFinalized = true;
        return true;
    }

    /**
     * @dev Sends presale tokens to any contributors when called by the owner can only be done before the crowdfund
     * @param _batchOfAddresses An array of presale contributor addresses
     * @param _amountOfTokens An array of tokens bought synchronized with the index value of _batchOfAddresses
     * @return bool True if successful else false
     */
    function deliverPresaleTokens(
        address[] _batchOfAddresses,
        uint256[] _amountOfTokens) 
        external 
        onlyBeforeCrowdfund 
        onlyOwner returns (bool success) {
        require(_batchOfAddresses.length == _amountOfTokens.length, "array lengths must be equal");
        for (uint256 i = 0; i < _batchOfAddresses.length; i++) {
            if (!token.moveAllocation(_batchOfAddresses[i], _amountOfTokens[i])) {
                revert("failed to move allocation");
            }
        }
        return true;
    }
    /**
     * @dev Called by the owner to kill the contact once the crowdfund is finished and there are no tokens left
     */
    function kill() external onlyOwner {
        uint256 amount = getCrowdFundAllocation();
        require(crowdfundFinalized == true && amount == 0, "crowdfund must be finalized and there must be 0 tokens remaining");
        // Send any ETH to the owner
        selfdestruct(owner);
    }

    /**
    * @dev Adds single address to whitelist.
    * @param _beneficiary Address to be added to the whitelist
    */
    function addToWhitelist(address _beneficiary) external onlyOwner {
        whitelist[_beneficiary] = true;
    }

    /**
    * @dev Adds list of addresses to whitelist.
    * @param _beneficiaries Addresses to be added to the whitelist
    *
    */
    function addManyToWhitelist(address[] _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            whitelist[_beneficiaries[i]] = true;
        }
    }

    /**
    * @dev Removes list of addresses to whitelist
    * @param _beneficiaries Addresses to be removed from the whitelist
    */
    function removeManyFromWhitelist(address[] _beneficiaries) external onlyOwner {
        for (uint256 i = 0; i < _beneficiaries.length; i++) {
            whitelist[_beneficiaries[i]] = false;
        }
    }

    /**
    * @dev Removes single address from whitelist.
    * @param _beneficiary Address to be removed to the whitelist
    */
    function removeFromWhitelist(address _beneficiary) external onlyOwner {
        whitelist[_beneficiary] = false;
    }

    /**
     * @dev Allows for users to send ETH to buy tokens
     */
    function () external payable {
        buyTokens(msg.sender);
    }

    /////////////////////// CONSTANT FUNCTIONS ///////////////////////

    /**
     * @dev Returns token rate depending on the current time
     * @return uint The price of the token rate per 1 ETH
     */
    function getRate() public view returns (uint) { // This one is dynamic, would have multiple rounds
        // Calculate the amount of days passed (division truncates)
        uint256 daysPassed = (now.sub(startsAt)).div(1 days);
        // Safe for loop -- rates is limited to 10 elements, the index never goes above 9, below 0
        for (uint8 i = 0; i < rates.length; i++) {
            // if the days passed since the start is below the amountOfdays we use that rate
            if (daysPassed < rates[i].amountOfDays) {
                return rates[i].price;
            }
        }
        // If we reach here, means this is after the crowdfund ended
        return 0;
    }

    /**
     * @dev Returns the crowdfund's token allocation
     * @return The number of tokens this contract has allocated
     */
    function getCrowdFundAllocation() public view returns (uint256 allocation) {
        (allocation, ) = token.allocations(this);
    }

}
 