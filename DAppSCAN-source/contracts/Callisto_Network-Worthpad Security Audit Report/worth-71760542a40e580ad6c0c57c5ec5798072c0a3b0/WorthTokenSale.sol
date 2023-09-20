import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

/* Token Interface */
interface Token {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
}

/* WORTH Token Sale Contract */
contract WorthTokenSale is ReentrancyGuard, Context, Ownable {

    using SafeMath for uint256;

    address public tokenAddr;
    address public usdtAddr;
    address public busdAddr;
    
    uint256 public tokenPriceUsd; 
    uint256 public tokenDecimal = 18;
    uint256 public totalTransaction;
    uint256 public totalHardCap;
    uint256 public minContribution;
    uint256 public maxContribution;
    uint256 public hardCap;

    //Keep track of whether contract is up or not
    bool public contractUp;
      
    //Keep track of whether the sale has ended or not
    bool public saleEnded;
    
    //Event to trigger Sale stop
    event SaleStopped(address _owner, uint256 time);

    event TokensTransferred(address beneficiary, uint256 amount);
    event TokensDeposited(address indexed beneficiary, uint256 amount);
    event UsdDeposited(address indexed beneficiary, uint256 amount);
    event HardCapUpdated(uint256 value);
    event TokenPriceUpdated(uint256 value);
    event MinMaxUpdated(uint256 min, uint256 max);
    event TokenAddressUpdated(address value);
    event TokenWithdrawn(address beneficiary,uint256 value);
    event CryptoWithdrawn(address beneficiary,uint256 value);
    event SaleEnded(address _owner, uint256 time);
    
    mapping(address => uint256) public balances;
    mapping(address => bool) public whitelisted;
    mapping(address => uint256) public allocation;
    mapping(address => uint256) public tokenExchanged;

    bool public whitelist = true;
    uint256 public claimDate;

    //modifiers    
    modifier _contractUp(){
        require(contractUp,"Token Sale hasn't started");
        _;
    }
  
     modifier nonZeroAddress(address _to) {
        require(_to != address(0),"Token Address should not be address 0");
        _;
    }
    
    modifier _saleEnded() {
        require(saleEnded, "Token Sale hasn't ended yet");
        _;
    }
    
    modifier _saleNotEnded() {
        require(!saleEnded, "Token Sale has ended");
        _;
    }

    /* Constructor Arguments : */
    /* 1. WorthToken token contract Address */
    /* 2. Min Contribution (in USD) */
    /* 3. Max Contribution (in USD) */
    /* 4. Hard Cap (in USD) */
    /* 5. Claim Date (in UNIX Timestamp) */
    /* 6. USDT token address */
    /* 7. BUSD token address */
    /* 8. Token ICO Price (in USD) */
    constructor(address _tokenAddr, uint256 _minContribution,
                uint256 _maxContribution,uint256 _hardCap,
                uint256 _claimDate, address _usdtAddr,
                address _busdAddr, uint256 _tokenPriceUsd) nonZeroAddress(_tokenAddr) nonZeroAddress(_usdtAddr) nonZeroAddress(_busdAddr){
        tokenAddr = _tokenAddr;
        minContribution = _minContribution.mul(10 ** uint256(tokenDecimal));
        maxContribution = _maxContribution.mul(10 ** uint256(tokenDecimal));
        hardCap = _hardCap.mul(10 ** uint256(tokenDecimal));
        claimDate = _claimDate;
        usdtAddr = _usdtAddr;
        busdAddr = _busdAddr;
        tokenPriceUsd = _tokenPriceUsd.mul(10 ** uint256(tokenDecimal));
    }

    /* Function     : This function is used to Whitelist address for Sale */
    /* Parameters   : Array Address of all users */
    /* External Function */
    function whitelistAddress(address[] memory _recipients, uint256[] memory _allocation) external onlyOwner returns (bool) {
        require(!contractUp, "Changes are not allowed during Token Sale");
        for (uint256 i = 0; i < _recipients.length; i++) {
            whitelisted[_recipients[i]] = true;
            allocation[_recipients[i]] = _allocation[i];
        }
        return true;
    } 
    
    /* Function     : This function is used to deposit tokens for liquidity manually */
    /* Parameters   : Total amount needed to be added as liquidity */
    /* External Function */    
    function depositTokens(uint256  _amount) external returns (bool) {
        require(_amount <= Token(tokenAddr).balanceOf(msg.sender),"Token Balance of user is less");
        require(Token(tokenAddr).transferFrom(msg.sender,address(this), _amount));
        emit TokensDeposited(msg.sender, _amount);
        return true;
    }

    /* Function     : This function is used to claim token brought */
    /* Parameters   : -- */
    /* External Function */
    function claimToken() external nonReentrant _saleEnded() returns (bool) {
        address userAdd = msg.sender;
        uint256 amountToClaim = tokenExchanged[userAdd];
        require(block.timestamp>claimDate,"Cannot Claim Now");
        require(amountToClaim>0,"There is no amount to claim");
        require(amountToClaim <= Token(tokenAddr).balanceOf(address(this)),"Token Balance of contract is less");
        tokenExchanged[userAdd] = 0;
        require(Token(tokenAddr).transfer(userAdd, amountToClaim),"Transfer Failed");
        emit TokensTransferred(userAdd, amountToClaim);
        return true;
    }
    
    /* This function will accept funds directly sent to the address */
    receive() payable external {
    }

    /* Function     : This function is used to buy WORTH tokens using USDT */
    /* Parameters   : Total amount of WORTH token to buy */
    /* External Function */
    function exchangeUSDTForToken(uint256 _amount) external nonReentrant _contractUp() _saleNotEnded() {
        require(Token(usdtAddr).transferFrom(msg.sender,address(this), _amount));
        uint256 amount = _amount;
        address userAdd = msg.sender;
        uint256 tokenAmount = 0;
        balances[msg.sender] = balances[msg.sender].add(_amount);
        
        if(whitelist){
            require(whitelisted[userAdd],"User is not Whitelisted");
            require(balances[msg.sender]<=allocation[msg.sender],"User max allocation limit reached");
        }
        require(totalHardCap < hardCap, "USD Hardcap Reached");
        require(balances[msg.sender] >= minContribution && balances[msg.sender] <= maxContribution,"Contribution should satisfy min max case");
        totalTransaction = totalTransaction.add(1);
        totalHardCap = totalHardCap.add(amount);
        tokenAmount = amount.mul(10 ** uint256(tokenDecimal)).div(tokenPriceUsd);
        tokenExchanged[userAdd] += tokenAmount;
        
        emit UsdDeposited(msg.sender,_amount);
    }

    /* Function     : This function is used to buy WORTH tokens using BUSD */
    /* Parameters   : Total amount of WORTH token to buy */
    /* External Function */
    function exchangeBUSDForToken(uint256 _amount) external nonReentrant _contractUp() _saleNotEnded() {
        require(Token(busdAddr).transferFrom(msg.sender,address(this), _amount));
        uint256 amount = _amount;
        address userAdd = msg.sender;
        uint256 tokenAmount = 0;
        balances[msg.sender] = balances[msg.sender].add(_amount);
        
        if(whitelist){
            require(whitelisted[userAdd],"User is not Whitelisted");
            require(balances[msg.sender]<=allocation[msg.sender],"User max allocation limit reached");
        }
        require(totalHardCap < hardCap, "USD Hardcap Reached");
        require(balances[msg.sender] >= minContribution && balances[msg.sender] <= maxContribution,"Contribution should satisfy min max case");
        totalTransaction = totalTransaction.add(1);
        totalHardCap = totalHardCap.add(amount);
        tokenAmount = amount.mul(10 ** uint256(tokenDecimal)).div(tokenPriceUsd);
        tokenExchanged[userAdd] += tokenAmount;
        
        emit UsdDeposited(msg.sender,_amount);
    }

    
    /* ONLY OWNER FUNCTIONS */

    /**
    *     @dev Check if sale contract is powered up
    */
    function powerUpContract() external onlyOwner {
        // Contract should not be powered up previously
        require(!contractUp);
        //activate the sale process
        contractUp = true;
    }

    //for Emergency/Hard stop of the sale
    function emergencyStop() external onlyOwner _contractUp() _saleNotEnded() {
        saleEnded = true;    
        emit SaleStopped(msg.sender, block.timestamp);
    }
    
    /**
    *     @dev End the Sale
    */
    function endSale() external onlyOwner _contractUp() _saleNotEnded() {
        //End the sale process
        saleEnded = true;
        emit SaleEnded(msg.sender, block.timestamp);
    }

    /* Function     : Updates Whitelisting feature ON/OFF */
    /* Parameters   : -- */
    /* Only Owner Function */
    function toggleWhitelistStatus() external onlyOwner returns (bool success)  {
        require(!contractUp, "Changes are not allowed during Token Sale");
        if (whitelist) {
            whitelist = false;
        } else {
            whitelist = true;
        }
        return whitelist;     
    }

    /* Function     : Update Token Price */
    /* Parameters   : New token Price (in USD) */
    /* Only Owner Function */    
    function updateTokenPrice(uint256 newTokenValue) external onlyOwner {
        require(!contractUp, "Changes are not allowed during Token Sale");
        tokenPriceUsd = newTokenValue.mul(10 ** uint256(tokenDecimal));
        emit TokenPriceUpdated(newTokenValue);
    }

    /* Function     : Update Hard cap of sale (in USD) */
    /* Parameters   : New Hard cap (in USD) */
    /* Only Owner Function */
    function updateHardCap(uint256 newHardcapValue) external onlyOwner {
        require(!contractUp, "Changes are not allowed during Token Sale");
        hardCap = newHardcapValue.mul(10 ** uint256(tokenDecimal));
        emit HardCapUpdated(newHardcapValue);
    }

    /* Function     : Update Min Max Buy Limits (in USD) */
    /* Parameters 1 : Min Token */
    /* Parameters 2 : Max Token */
    /* Only Owner Function */
    function updateTokenContribution(uint256 min, uint256 max) external onlyOwner {
        require(!contractUp, "Changes are not allowed during Token Sale");
        minContribution = min.mul(10 ** uint256(tokenDecimal));
        maxContribution = max.mul(10 ** uint256(tokenDecimal));
        emit MinMaxUpdated(min,max);
    }
    
    /* Function     : Updates the token address */
    /* Parameters   : New Token Address */
    /* Only Owner Function */
    function updateTokenAddress(address newTokenAddr) external nonZeroAddress(newTokenAddr) onlyOwner {
        require(!contractUp, "Changes are not allowed during Token Sale");
        tokenAddr = newTokenAddr;
        emit TokenAddressUpdated(newTokenAddr);
    }

    /* Function     : Withdraw Tokens remaining after the sale */
    /* Parameters 1 : Address where token should be sent */
    /* Parameters 2 : Token Address */
    /* Only Owner Function */
    // SWC-105-Unprotected Ether Withdrawal: L279 - L282
    function withdrawTokens(address beneficiary, address _tokenAddr) external nonZeroAddress(beneficiary) onlyOwner _contractUp() _saleEnded() {
        require(Token(_tokenAddr).transfer(beneficiary, Token(_tokenAddr).balanceOf(address(this))));
        emit TokenWithdrawn(_tokenAddr, Token(_tokenAddr).balanceOf(address(this)));
    }

    /* Function     : Withdraws Funds after sale */
    /* Parameters   : Address where Funds should be sent */
    /* Only Owner Function */
    function withdrawCrypto(address payable beneficiary) external nonZeroAddress(beneficiary) onlyOwner _contractUp() _saleEnded() {
        require(address(this).balance>0,"No Crypto inside contract");
        (bool success, ) = beneficiary.call{value:address(this).balance}("");
        require(success, "Transfer failed.");
        emit CryptoWithdrawn(beneficiary, address(this).balance);
    }
    
    /* ONLY OWNER FUNCTION ENDS HERE */

    /* VIEW FUNCTIONS */

    /* Function     : Returns Token Balance inside contract */
    /* Parameters   : -- */
    /* Public View Function */
    function getTokenBalance(address _tokenAddr) public view nonZeroAddress(_tokenAddr) returns (uint256){
        return Token(_tokenAddr).balanceOf(address(this));
    }

    /* Function     : Returns Crypto Balance inside contract */
    /* Parameters   : -- */
    /* Public View Function */
    function getCryptoBalance() public view returns (uint256){
        return address(this).balance;
    }
}
