pragma solidity 0.4.24;


contract OraclizeI {
    address public cbAddress;
    function setProofType(byte _proofType) external;
    function query(uint _timestamp, string _datasource, string _arg) external payable returns (bytes32 _id);
    function getPrice(string _datasource) public returns (uint _dsprice);
}


contract OraclizeAddrResolverI {
    function getAddress() public returns (address _addr);
}


contract UsingOraclize {
    byte constant proofType_Ledger = 0x30;
    byte constant proofType_Android = 0x40;
    byte constant proofStorage_IPFS = 0x01;
    uint8 constant networkID_auto = 0;
    uint8 constant networkID_mainnet = 1;
    uint8 constant networkID_testnet = 2;

    OraclizeAddrResolverI OAR;

    OraclizeI oraclize;

    modifier oraclizeAPI {
        if ((address(OAR) == 0)||(getCodeSize(address(OAR)) == 0))
            oraclize_setNetwork(networkID_auto);

        if (address(oraclize) != OAR.getAddress())
            oraclize = OraclizeI(OAR.getAddress());

        _;
    }

    function oraclize_setNetwork(uint8 networkID) internal returns(bool){
        return oraclize_setNetwork();
        networkID; // silence the warning and remain backwards compatible
    }

    function oraclize_setNetwork() internal returns(bool){
        if (getCodeSize(0x1d3B2638a7cC9f2CB3D298A3DA7a90B67E5506ed) > 0){ //mainnet
            OAR = OraclizeAddrResolverI(0x1d3B2638a7cC9f2CB3D298A3DA7a90B67E5506ed);
            oraclize_setNetworkName("eth_mainnet");
            return true;
        }
        if (getCodeSize(0xB7A07BcF2Ba2f2703b24C0691b5278999C59AC7e) > 0){ //kovan testnet
            OAR = OraclizeAddrResolverI(0xB7A07BcF2Ba2f2703b24C0691b5278999C59AC7e);
            oraclize_setNetworkName("eth_kovan");
            return true;
        }
        if (getCodeSize(0x51efaF4c8B3C9AfBD5aB9F4bbC82784Ab6ef8fAA)>0){ //browser-solidity
            OAR = OraclizeAddrResolverI(0x51efaF4c8B3C9AfBD5aB9F4bbC82784Ab6ef8fAA);
            return true;
        }
        return false;
    }

    function oraclize_getPrice(string datasource) oraclizeAPI internal returns (uint){
        return oraclize.getPrice(datasource);
    }

    function oraclize_query(string datasource, string arg) oraclizeAPI internal returns (bytes32 id){
        uint price = oraclize.getPrice(datasource);
        if (price > 1 ether + tx.gasprice*200000) return 0; // unexpectedly high price
        return oraclize.query.value(price)(0, datasource, arg);
    }

    function oraclize_query(uint timestamp, string datasource, string arg) oraclizeAPI internal returns (bytes32 id){
        uint price = oraclize.getPrice(datasource);
        if (price > 1 ether + tx.gasprice*200000) return 0; // unexpectedly high price
        return oraclize.query.value(price)(timestamp, datasource, arg);
    }

    function oraclize_cbAddress() internal oraclizeAPI returns (address){
        return oraclize.cbAddress();
    }

    function oraclize_setProof(byte proofP) internal oraclizeAPI  {
        return oraclize.setProofType(proofP);
    }

    function getCodeSize(address _addr) internal view returns(uint _size) {
        assembly {
            _size := extcodesize(_addr)
        }
    }

    // parseInt(parseFloat*10^_b)
    function parseInt(string _a, uint _b) internal pure returns (uint) {
        bytes memory bresult = bytes(_a);
        uint mint = 0;
        bool decimals = false;
        for (uint i=0; i < bresult.length; i++) {
            if ((bresult[i] >= 48)&&(bresult[i] <= 57)) {
                if (decimals) {
                    if (_b == 0) break;
                    else _b--;
                }
                mint *= 10;
                mint += uint(bresult[i]) - 48;
            } else if (bresult[i] == 46) decimals = true;
        }
        if (_b > 0) mint *= 10**_b;
        return mint;
    }

    string oraclize_network_name;

    function oraclize_setNetworkName(string _network_name) internal {
        oraclize_network_name = _network_name;
    }

}


/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

    /**
    * @dev Multiplies two numbers, throws on overflow.
    */
    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        // Gas optimization: this is cheaper than asserting 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        c = a * b;
        assert(c / a == b);
        return c;
    }

    /**
    * @dev Integer division of two numbers, truncating the quotient.
    */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return a / b;
    }

    /**
    * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
    */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    /**
    * @dev Adds two numbers, throws on overflow.
    */
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }

    function pow(uint256 a, uint256 power) internal pure returns (uint256 result) {
        assert(a >= 0);
        result = 1;
        for (uint256 i = 0; i < power; i++){
            result *= a;
            assert(result >= a);
        }
    }
}


/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address public owner;
    address public pendingOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

   /**
   * @dev Throws if called by any account other than the owner.
   */
    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    /**
    * @dev Modifier throws if called by any account other than the pendingOwner.
    */
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner);
        _;
    }

    constructor() public {
        owner = msg.sender;
    }

    /**
    * @dev Allows the current owner to set the pendingOwner address.
    * @param newOwner The address to transfer ownership to.
    */
    function transferOwnership(address newOwner) public onlyOwner {
        pendingOwner = newOwner;
    }

    /**
    * @dev Allows the pendingOwner address to finalize the transfer.
    */
    function claimOwnership() public onlyPendingOwner {
        emit OwnershipTransferred(owner, pendingOwner);
        owner = pendingOwner;
        pendingOwner = address(0);
    }
}


/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = false;

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(paused);
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() public onlyOwner whenNotPaused {
        paused = true;
        emit Pause();
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() public onlyOwner whenPaused {
        paused = false;
        emit Unpause();
    }
}


/**
 * @title ERC20Basic
 * @dev Simpler version of ERC20 interface
 * See https://github.com/ethereum/EIPs/issues/179
 */
contract ERC20Basic {
    function totalSupply() public view returns (uint256);
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
}


/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {

    uint256 public decimals;

    function allowance(address owner, address spender)
        public view returns (uint256);

    function transferFrom(address from, address to, uint256 value)
        public returns (bool);

    function approve(address spender, uint256 value) public returns (bool);

    function mint(
        address _to,
        uint256 _amountusingOraclize
    )
        public
        returns (bool);

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}


/**
 * @title Whitelist
 * @dev The Whitelist contract has a whitelist of addresses, and provides basic authorization control functions.
 * @dev This simplifies the implementation of "user permissions".
 */
contract Whitelist is Ownable {
    mapping(address => bool) public whitelist;

    event WhitelistedAddressAdded(address addr);
    event WhitelistedAddressRemoved(address addr);

    /**
     * @dev Throws if called by any account that's not whitelisted.
     */
    modifier onlyWhitelisted() {
        require(whitelist[msg.sender]);
        _;
    }

    /**
     * @dev add an address to the whitelist
     * @param addr address
     * @return true if the address was added to the whitelist, false if the address was already in the whitelist
     */
    function addAddressToWhitelist(address addr) public onlyOwner returns(bool success) {
        if (!whitelist[addr]) {
            whitelist[addr] = true;
            emit WhitelistedAddressAdded(addr);
            success = true;
        }
    }

    /**
     * @dev add addresses to the whitelist
     * @param addrs addresses
     * @return true if at least one address was added to the whitelist,
     * false if all addresses were already in the whitelist
     */
    function addAddressesToWhitelist(address[] addrs) public onlyOwner returns(bool success) {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addAddressToWhitelist(addrs[i])) {
                success = true;
            }
        }
    }

    /**
     * @dev remove an address from the whitelist
     * @param addr address
     * @return true if the address was removed from the whitelist,
     * false if the address wasn't in the whitelist in the first place
     */
    function removeAddressFromWhitelist(address addr) public onlyOwner returns(bool success) {
        if (whitelist[addr]) {
            whitelist[addr] = false;
            emit WhitelistedAddressRemoved(addr);
            success = true;
        }
    }

    /**
     * @dev remove addresses from the whitelist
     * @param addrs addresses
     * @return true if at least one address was removed from the whitelist,
     * false if all addresses weren't in the whitelist in the first place
     */
    function removeAddressesFromWhitelist(address[] addrs) public onlyOwner returns(bool success) {
        for (uint256 i = 0; i < addrs.length; i++) {
            if (removeAddressFromWhitelist(addrs[i])) {
                success = true;
            }
        }
    }

}


contract PriceChecker is UsingOraclize {

    uint256 public priceETHUSD; //price in cents
    uint256 public centsInDollar = 100;
    uint256 public lastPriceUpdate; //timestamp of the last price updating
    uint256 public minUpdatePeriod = 3300; // min timestamp for update in sec

    event NewOraclizeQuery(string description);
    event PriceUpdated(uint256 price);

    constructor() public {
        oraclize_setProof(proofType_Android | proofStorage_IPFS);
        _update(0);
    }

    /**
     * @dev Reverts if the timestamp of the last price updating
     * @dev is older than one hour two minutes.
     */
    modifier onlyActualPrice {
        require(lastPriceUpdate > now - 3720);
        _;
    }

    /**
    * @dev Receives the response from oraclize.
    */
    function __callback(bytes32 myid, string result, bytes proof) public {
        require((lastPriceUpdate + minUpdatePeriod) < now);
        require(msg.sender == oraclize_cbAddress());

        priceETHUSD = parseInt(result, 2);
        lastPriceUpdate = now;

        emit PriceUpdated(priceETHUSD);

        _update(3600);
        return;

        proof; myid; //to silence the compiler warning
    }
    
    /**
     * @dev Cyclic query to update ETHUSD price. Period is one hour.
     */
    function _update(uint256 _timeout) internal {
        if (oraclize_getPrice("URL") > address(this).balance) {
            emit NewOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
        } else {
            emit NewOraclizeQuery("Oraclize query was sent, standing by for the answer..");
            oraclize_query(_timeout, "URL", "json(https://api.coinmarketcap.com/v1/ticker/ethereum/).0.price_usd");
        }
    }
}


/**
 * @title BeamCrowdsale
 * @dev BeamCrowdsale is a contract for managing a token crowdsale,
 * allowing investors to purchase tokens with ether. This contract implements
 * such functionality.
 * The external interface represents the basic interface for purchasing tokens, and conform
 * the base architecture for crowdsales. They are *not* intended to be modified / overriden.
 * The internal interface conforms the surface of crowdsales.
 */
contract BeamCrowdsale is Whitelist, PriceChecker, Pausable {
    using SafeMath for uint256;

    // Investors to invested amount
    mapping(address => uint256) public funds;

    // The token being sold
    ERC20 public token;

    // Address where funds are collected
    address public wallet;

    // Amount of wei raised
    uint256 public weiRaised;

    // the percent of discount for seed round
    uint256 public discountSeed = 20;

    // the percent of discount for private round
    uint256 public discountPrivate = 15;

    // the percent of discount for public round
    uint256 public discountPublic = 10;

    // Decimals of the using token
    uint256 public decimals;

    // Amount of bonuses
    uint256 public bonuses;

    // Whether the public round is active
    bool public publicRound;

    // Whether the seed round has finished
    bool public seedFinished;

    // Whether the crowdsale has finished
    bool public crowdsaleFinished;

    // Whether the soft cap has reached
    bool public softCapReached;

    // Increasing of the token price in units with each token emission
    uint256 public increasing = 10 ** 9;

    // Amount of tokens for seed round
    uint256 public tokensForSeed = 100 * 10 ** 6 * 10 ** 18;

    // Soft cap in USD units
    uint256 public softCap = 2 * 10 ** 6 * 10 ** 18;

    // Amount of USD raised in units
    uint256 public usdRaised;

    uint256 public unitsToInt = 10 ** 18;

    /**
     * Event for token purchase logging
     * @param purchaser who paid and got for the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokenPurchase(
        address indexed purchaser,
        uint256 value,
        uint256 amount
    );

    /**
     * Event for logging of the seed round finish
     */
    event SeedRoundFinished();

    /**
     * Event for logging of the private round finish
     */
    event PrivateRoundFinished();

    /**
     * Event for logging of the private round start
     */
    event StartPrivateRound();

    /**
     * Event for logging of the public round start
     */
    event StartPublicRound();

    /**
     * Event for logging of the public round finish
     */
    event PublicRoundFinished();

    /**
     * Event for logging of the crowdsale finish
     * @param weiRaised Amount of wei raised during the crowdsale
     * @param usdRaised Amount of usd raised during the crowdsale (in units)
     */
    event CrowdsaleFinished(uint256 weiRaised, uint256 usdRaised);

    /**
     * Event for logging of reaching the soft cap
     */
    event SoftCapReached();

    /**
    * @dev Reverts if crowdsale has finished.
    */
    modifier onlyWhileOpen {
        require(!crowdsaleFinished);
        _;
    }

    /**
     * @param _wallet Address where collected funds will be forwarded to
     * @param _token Address of the token being sold
     */
    constructor(address _wallet, ERC20 _token) public {
        require(_wallet != address(0));
        require(_token != address(0));

        wallet = _wallet;
        token = _token;
        decimals = token.decimals();
    }

    // -----------------------------------------
    // Crowdsale external interface
    // -----------------------------------------

    /**
     * @dev fallback function
     */
    function () external
        payable
        onlyActualPrice
        onlyWhileOpen
        onlyWhitelisted
        whenNotPaused
    {
        buyTokens();
    }

    /**
     * @dev Allows owner to send ETH to the contarct for paying fees or refund.
     */
    function payToContract() external payable onlyOwner {}

    /**
     * @dev Allows owner to withdraw ETH from the contract balance.
     */
    function withdrawFunds(address _beneficiary, uint256 _weiAmount)
        external
        onlyOwner
    {
        require(address(this).balance > _weiAmount);
        _beneficiary.transfer(_weiAmount);
    }

    /**
     * @dev Alows owner to finish the crowdsale
     */
    function finishCrowdsale() external onlyOwner onlyWhileOpen {
        crowdsaleFinished = true;

        uint256 _soldAmount = token.totalSupply().sub(bonuses);

        token.mint(address(this), _soldAmount);

        emit TokenPurchase(address(this), 0, _soldAmount);

        emit CrowdsaleFinished(weiRaised, usdRaised);
    }
    
    /**
     * @dev Overriden inherited method to prevent calling from third persons
     */
    function update(uint256 _timeout) external payable onlyOwner {
        _update(_timeout);
    }

    /**
     * @dev Transfers fund to contributor if the crowdsale fails
     */
    function claimFunds() external {
        require(crowdsaleFinished);
        require(!softCapReached);
        require(funds[msg.sender] > 0);
        require(address(this).balance >= funds[msg.sender]);
        uint256 toSend = funds[msg.sender];
        delete funds[msg.sender];
        msg.sender.transfer(toSend);
    }

    /**
     * @dev Allows owner to transfer BEAM tokens
     * @dev from the crowdsale smart contract balance
     */
    function transferTokens(
        address _beneficiary,
        uint256 _tokenAmount
    )
        external
        onlyOwner
    {
        require(token.balanceOf(address(this)) >= _tokenAmount);
        token.transfer(_beneficiary, _tokenAmount);
    }

    /**
     * @dev Allows owner to add raising fund manually
     * @param _beneficiary Address performing the token purchase
     * @param _usdUnits Value in USD units involved in the purchase
     */
    function buyForFiat(address _beneficiary, uint256 _usdUnits)
        external
        onlyOwner
        onlyWhileOpen
        onlyActualPrice
    {
        uint256 _weiAmount = _usdUnits.mul(centsInDollar).div(priceETHUSD);
        
        _preValidatePurchase(_beneficiary, _weiAmount);

        // calculate token amount to be created
        uint256 tokens = _getTokenAmount(_weiAmount);

        // update state
        weiRaised = weiRaised.add(_weiAmount);

        _processPurchase(_beneficiary, tokens);
        emit TokenPurchase(
            _beneficiary,
            _weiAmount,
            tokens
        );

        _postValidatePurchase();
    }

    /**
     * @dev Mints bonuses by admin
     * @param _beneficiary Address performing the token purchase
     * @param _tokenUnits Amount of the tokens to mint
     */
    function mintBonus(address _beneficiary, uint256 _tokenUnits)
        external
        onlyOwner
        onlyWhileOpen
    {

        _processPurchase(_beneficiary, _tokenUnits);
        emit TokenPurchase(_beneficiary, 0, _tokenUnits);

        bonuses = bonuses.add(_tokenUnits);

        _postValidatePurchase();
    }

    /**
     * @dev Allows owner to finish the seed round
     */
    function finishSeedRound() external onlyOwner onlyWhileOpen {
        require(!seedFinished);
        seedFinished = true;
        emit SeedRoundFinished();
        emit StartPrivateRound();
    }

    /**
     * @dev Allows owner to change the discount for seed round
     */
    function setDiscountSeed(uint256 _discountSeed) external onlyOwner onlyWhileOpen {
        discountSeed = _discountSeed;
    }

    /**
     * @dev Allows owner to change the discount for private round
     */
    function setDiscountPrivate(uint256 _discountPrivate) external onlyOwner onlyWhileOpen {
        discountPrivate = _discountPrivate;
    }

    /**
     * @dev Allows owner to change the discount for public round
     */
    function setDiscountPublic(uint256 _discountPublic) external onlyOwner onlyWhileOpen {
        discountPublic = _discountPublic;
    }

    /**
     * @dev Allows owner to start or renew public round
     * @dev Function accesable only after the end of the seed round
     * @dev If _enable is true, private round ends and public round starts
     * @dev If _enable is false, public round ends and private round starts
     * @param _enable Whether the public round is open
     */
    function setPublicRound(bool _enable) external onlyOwner onlyWhileOpen {
        require(seedFinished);
        publicRound = _enable;
        if (_enable) {
            emit PrivateRoundFinished();
            emit StartPublicRound();
        } else {
            emit PublicRoundFinished();
            emit StartPrivateRound();
        }
    }

    /**
     * @dev low level token purchase
     */
    function buyTokens()
        public
        payable
        onlyWhileOpen
        onlyWhitelisted
        whenNotPaused
        onlyActualPrice
    {
        address _beneficiary = msg.sender;

        uint256 _weiAmount = msg.value;
        _preValidatePurchase(_beneficiary, _weiAmount);

        // calculate token amount to be created
        uint256 tokens = _getTokenAmount(_weiAmount);
        
        _weiAmount = _weiAmount.sub(_applyDiscount(_weiAmount));

        funds[_beneficiary] = funds[_beneficiary].add(_weiAmount);

        // update state
        weiRaised = weiRaised.add(_weiAmount);

        _processPurchase(_beneficiary, tokens);
        emit TokenPurchase(_beneficiary, _weiAmount, tokens);

        _forwardFunds(_weiAmount);

        _postValidatePurchase();
    }

    /**
     * @return Actual token price in USD units
     */
    function tokenPrice() public view returns(uint256) {
        uint256 _supplyInt = token.totalSupply().div(10 ** decimals);
        return uint256(10 ** 18).add(_supplyInt.mul(increasing));
    }

    // -----------------------------------------
    // Internal interface (extensible)
    // -----------------------------------------

    /**
     * @dev Validation of an incoming purchase. Use require statements
     * @dev to revert state when conditions are not met.
     * @param _beneficiary Address performing the token purchase
     * @param _weiAmount Value in wei involved in the purchase
     */
    function _preValidatePurchase(
        address _beneficiary,
        uint256 _weiAmount
    )
        internal
        pure
    {
        require(_beneficiary != address(0));
        require(_weiAmount != 0);
    }

    /**
     * @return The square root of 'x'
     */
    function sqrt(uint256 x) internal pure returns (uint256) {
        uint256 z = (x.add(1)).div(2);
        uint256 y = x;
        while (z < y) {
            y = z;
            z = ((x.div(z)).add(z)).div(2);
        }
        return y;
    }

    /**
     * @return The amount of tokens (without decimals) for specified _usdUnits accounting the price increasing
     */
    function tokenIntAmount(uint256 _startPrice, uint256 _usdUnits)
        internal
        view
        returns(uint256)
    {
        uint256 sqrtVal = sqrt(((_startPrice.mul(2).sub(increasing)).pow(2)).add(_usdUnits.mul(8).mul(increasing)));

        return (increasing.add(sqrtVal).sub(_startPrice.mul(2))).div(increasing.mul(2));
    }

    /**
     * @dev Calculates the remainder USD amount.
     * @param _startPrice Address performing the token purchase
     * @param _usdUnits Value involved in the purchase
     * @param _tokenIntAmount Value of tokens without decimals
     * @return Number of USD units to process purchase
     */
    function _remainderAmount(
        uint256 _startPrice,
        uint256 _usdUnits,
        uint256 _tokenIntAmount
    )
        internal
        view
        returns(uint256)
    {
        uint256 _summ = (_startPrice.mul(2).add(increasing.mul(_tokenIntAmount.sub(1))).mul(_tokenIntAmount)).div(2);
        return _usdUnits.sub(_summ);
    }

    /**
     * @dev Validation of an executed purchase. Observes state.
     */
    function _postValidatePurchase() internal {
        if (!seedFinished) _checkSeed();
        if (!softCapReached) _checkSoftCap();
    }

    /**
     * @dev Source of tokens. The way in which the crowdsale ultimately gets and sends its tokens.
     * @param _beneficiary Address performing the token purchase
     * @param _tokenAmount Number of tokens to be emitted
     */
    function _deliverTokens(
        address _beneficiary,
        uint256 _tokenAmount
    )
        internal
    {
        token.mint(_beneficiary, _tokenAmount);
    }

    /**
     * @dev Executed when a purchase has been validated and is ready to be executed.
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
     * @dev The way in which ether is converted to tokens.
     * @param _weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     */
    function _getTokenAmount(uint256 _weiAmount)
        internal returns (uint256)
    {
        uint256 _usdUnits = _weiAmount.mul(priceETHUSD).div(centsInDollar);

        usdRaised = usdRaised.add(_usdUnits);

        uint256 _tokenPrice = tokenPrice();
        uint256 _tokenIntAmount = tokenIntAmount(_tokenPrice, _usdUnits);
        uint256 _tokenUnitAmount = _tokenIntAmount.mul(10 ** decimals);
        uint256 _newPrice = tokenPrice().add(_tokenIntAmount.mul(increasing));
        
        uint256 _usdRemainder;
        
        if (_tokenIntAmount == 0)
            _usdRemainder = _usdUnits;
        else
            _usdRemainder = _remainderAmount(_tokenPrice, _usdUnits, _tokenIntAmount);
            
        _tokenUnitAmount = _tokenUnitAmount.add(_usdRemainder.mul(10 ** decimals).div(_newPrice));
        return _tokenUnitAmount;
    }

    /**
     * @dev Checks the amount of sold tokens to finish seed round.
     */
    function _checkSeed() internal {
        if (token.totalSupply() >= tokensForSeed) {
            seedFinished = true;
            emit SeedRoundFinished();
            emit StartPrivateRound();
        }
    }

    /**
     * @dev Checks the USD raised to hit the sodt cap.
     */
    function _checkSoftCap() internal {
        if (usdRaised >= softCap) {
            softCapReached = true;
            emit SoftCapReached();
        }
    }

    /**
     * @dev Applys the reward according to bonus system.
     * @param _weiAmount Value in wei to applying bonus system
     */
    function _applyDiscount(uint256 _weiAmount) internal returns (uint256) {
        address _payer = msg.sender;
        uint256 _refundAmount;
        
        if (!seedFinished) {
            _refundAmount = _weiAmount.mul(discountSeed).div(100);
        } else if (!publicRound) {
            _refundAmount = _weiAmount.mul(discountPrivate).div(100);
        } else {
            _refundAmount = _weiAmount.mul(discountPublic).div(100);
        }
        _payer.transfer(_refundAmount);
        return _refundAmount;
    }

    /**
     * @dev Determines how ETH is stored/forwarded on purchases.
     */
    function _forwardFunds(uint256 _weiAmount) internal {
        wallet.transfer(_weiAmount);
    }
}
