// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./ILogicContract.sol";
import "./AggregatorV3Interface.sol";


contract StorageV0 is Initializable, OwnableUpgradeable,PausableUpgradeable{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    
    struct DepositStruct{
        mapping(address=>uint256) amount;
        mapping(address=>int256) tokenTime;
        uint256 iterate;
        uint256 balanceBLID;
        mapping(address=>uint256) depositIterate;
    }

    struct EarnBLID{
        uint256 allBLID;
        uint256 timestamp;
        uint256 usd;
        uint256 tdt;
        mapping(address=>uint256) rates;
    }

    //events
    event Deposit(address depositor, address token, uint256 amount);
    event Withdraw(address depositor, address token, uint256 amount);
    event UpdateTokenBalance(uint256 balance, address token);
    event TakeToken(address token, uint256 amount);
    event ReturnToken(address token, uint256 amount);
    event AddEarn(uint256 amount);
    event UpdateBLIDBalance(uint256 balance);
    event InterestFee(address depositor, uint256 amount);
    
    function initialize (address _logicContract) public initializer{
        __Ownable_init();
        __Pausable_init();
        logicContract=_logicContract;
    }

    //variable
    mapping(uint256=>EarnBLID) earnBLID;
    uint256 countEarns;
    uint256 countTokens;
    mapping(uint256=>address) tokens;
    mapping(address =>uint256) tokenBalance;
    mapping(address=>address) oracles;
    mapping(address=>bool) tokensAdd;
    mapping(address=>DepositStruct) deposits;
    mapping(address=>uint256) tokenDeposited;
    mapping(address=>int256) tokenTime;
    uint256 reserveBLID;
    address logicContract;
    address BLID;
    
    //modifiers
    modifier isUsedToken(address _token){
        require(tokensAdd[_token], "E1");
        _;
    }
    modifier isLogicContract( address account){
        require(logicContract==account, "E2");
        _;
    }
    
    //user function
    function deposit(uint256 amount, address token)
    isUsedToken(token) whenNotPaused external
    {
        require(amount>0, "E3");
        uint8 decimals = AggregatorV3Interface(token).decimals();
        IERC20Upgradeable(token).safeTransferFrom(msg.sender,address(this), amount);
        if(deposits[msg.sender].tokenTime[address(0)] == 0){
            deposits[msg.sender].iterate=countEarns;
            deposits[msg.sender].depositIterate[token] = countEarns;
            deposits[msg.sender].amount[token] += amount*10**(18-decimals);
            deposits[msg.sender].tokenTime[address(0)] = 1;
            deposits[msg.sender].tokenTime[token] += int(block.timestamp*( amount*10**(18-decimals)));

        }else{
            interestFee();
            if(deposits[msg.sender].depositIterate[token] == countEarns){
                deposits[msg.sender].tokenTime[token] += int(block.timestamp*( amount*10**(18-decimals)));
                deposits[msg.sender].amount[token] += amount*10**(18-decimals);
            }else{
                deposits[msg.sender].tokenTime[token] = int(deposits[msg.sender].amount[token]*earnBLID[countEarns-1].timestamp+block.timestamp*(amount*10**(18-decimals)));
                deposits[msg.sender].amount[token] += amount*10**(18-decimals);
                deposits[msg.sender].depositIterate[token] = countEarns;
            }
        }

        tokenTime[token] += int(block.timestamp*(amount*10**(18-decimals)));
        tokenBalance[token] += amount*10**(18-decimals);
        tokenDeposited[token] += amount*10**(18-decimals);
        emit UpdateTokenBalance(tokenBalance[token], token);
        emit Deposit(msg.sender, token, amount*10**(18-decimals));
    }

    function withdraw(uint256 amount, address token)
    isUsedToken(token) whenNotPaused external
    {
        uint8 decimals =AggregatorV3Interface(token).decimals();
        require(deposits[msg.sender].amount[token] >= amount*10**(18-decimals)&&amount>0, "E4");
        if(amount*10**(18-decimals)> tokenBalance[token]){
            LogicContract(logicContract).returnToken(amount ,token);
            interestFee();
            IERC20Upgradeable(token).safeTransferFrom(logicContract,msg.sender,amount);
            IERC20Upgradeable(token).safeTransfer(msg.sender,amount);
            tokenDeposited[token]-= amount*10**(18-decimals);
            tokenTime[token]-=int(block.timestamp*( amount*10**(18-decimals)));

            emit UpdateTokenBalance(tokenBalance[token],token);
            emit Withdraw(msg.sender, token, amount*10**(18-decimals));
        }else{
            interestFee();
            IERC20Upgradeable(token).safeTransfer(msg.sender,amount);
            tokenTime[token]-=int(block.timestamp*( amount*10**(18-decimals)));

            tokenBalance[token]-=amount*10**(18-decimals);
            tokenDeposited[token]-= amount*10**(18-decimals);
            emit UpdateTokenBalance(tokenBalance[token],token);
            emit Withdraw(msg.sender, token, amount*10**(18-decimals));
        }
         if(deposits[msg.sender].depositIterate[token]==countEarns){
            deposits[msg.sender].tokenTime[token]-=int(block.timestamp*( amount*10**(18-decimals)));
            deposits[msg.sender].amount[token] -=  amount*10**(18-decimals);
        }else{
            deposits[msg.sender].tokenTime[token]= int(deposits[msg.sender].amount[token]*earnBLID[countEarns-1].timestamp)-int(block.timestamp*( amount*10**(18-decimals)));
            deposits[msg.sender].amount[token] -=  amount*10**(18-decimals);
            deposits[msg.sender].depositIterate[token]=countEarns;
        }
    }

    function interestFee()
    public
    {
        uint256 balanceUser = balanceEarnBLID(msg.sender);
        require(reserveBLID>=balanceUser, "E5");
        IERC20Upgradeable(BLID).safeTransfer(msg.sender,balanceUser);
        deposits[msg.sender].balanceBLID=balanceUser;
        deposits[msg.sender].iterate=countEarns;
        unchecked{
            deposits[msg.sender].balanceBLID = 0;
            reserveBLID -= balanceUser;
        }
        emit UpdateBLIDBalance(reserveBLID);
        emit InterestFee(msg.sender,balanceUser);
    }

    //owner functions
    function setBLID(address _blid)
    onlyOwner external
    {
        BLID=_blid;
    }
    function pause()
    onlyOwner external
    {
        _pause();
    }
       
    function unpause()
    onlyOwner external
    {
        _unpause();
    }

    function addToken(address _token, address _oracles) 
    onlyOwner external
    {
        require(_token!=address(0)&&_oracles!=address(0));
        require(!tokensAdd[_token], "E6");
        oracles[_token] = _oracles;
        tokens[countTokens++] = _token;
        tokensAdd[_token] = true;
    }
    
    function setLogic(address _logic)
    onlyOwner external
    {
        logicContract = _logic;
    }
    
    // logicContract function

    function takeToken(uint amount, address token) 
    isLogicContract(msg.sender) isUsedToken(token) external
    {
        uint8 decimals =AggregatorV3Interface(token).decimals();
        IERC20Upgradeable(token).safeTransfer(msg.sender,amount);
        tokenBalance[token] = tokenBalance[token]-( amount*10**(18-decimals));
        emit UpdateTokenBalance(tokenBalance[token],token);
        emit TakeToken(token, amount*10**(18-decimals));
    }

    function returnToken(uint amount, address token)
    isLogicContract(msg.sender) isUsedToken(token) external
    {
        uint8 decimals =AggregatorV3Interface(token).decimals();
        IERC20Upgradeable(token).safeTransferFrom(logicContract,address(this), amount);
        tokenBalance[token] = tokenBalance[token]+( amount*10**(18-decimals));
        emit UpdateTokenBalance(tokenBalance[token], token);
        emit ReturnToken(token, amount*10**(18-decimals));
    }
    
 function addEarn(uint256 amount)
    isLogicContract(msg.sender) external
    {
        IERC20Upgradeable(BLID).safeTransferFrom(msg.sender, address(this), amount);
        reserveBLID += amount;
        int256 _dollarTime = 0;
        for(uint256 i =0 ; i < countTokens;i++){
            earnBLID[countEarns].rates[tokens[i]] = (uint256(AggregatorV3Interface(oracles[tokens[i]]).latestAnswer())*10**(18-AggregatorV3Interface(oracles[tokens[i]]).decimals()));
            earnBLID[countEarns].usd += tokenDeposited[tokens[i]]*earnBLID[countEarns].rates[tokens[i]];
           _dollarTime += tokenTime[tokens[i]]*int(earnBLID[countEarns].rates[tokens[i]])/int(1 ether);
        }
        require(_dollarTime!=0);
        earnBLID[countEarns].allBLID = amount;
        earnBLID[countEarns].timestamp = block.timestamp;
        earnBLID[countEarns].tdt = uint((int(((block.timestamp)*earnBLID[countEarns].usd)/(1 ether))-_dollarTime));
        for(uint256 i =0; i < countTokens; i++){
            tokenTime[tokens[i]] = int(tokenDeposited[tokens[i]]*block.timestamp);
        }
        earnBLID[countEarns].usd/=(1 ether);
        countEarns++;
        emit AddEarn(amount);
        emit UpdateBLIDBalance(reserveBLID);
    }

    // external function
    function _upBalance(address account)
    public
    {
        for(uint256 i = deposits[account].iterate; i<countEarns; i++){
            for(uint256 j = 0; j<countTokens; j++){
                if(i==deposits[account].depositIterate[tokens[j]]){
                    deposits[account].balanceBLID += earnBLID[i].allBLID*uint((int((deposits[account].amount[tokens[j]]*earnBLID[i].rates[tokens[j]])*earnBLID[i].timestamp)-(deposits[account].tokenTime[tokens[j]]*int(earnBLID[i].rates[tokens[j]]))))/earnBLID[i].tdt/(1 ether);
                }
                else{
                    
                    deposits[account].balanceBLID += earnBLID[i].allBLID*(earnBLID[i].timestamp-earnBLID[i-1].timestamp)*deposits[account].amount[tokens[j]]*earnBLID[i].rates[tokens[j]]/earnBLID[i].tdt/(1 ether);
                    
                }
            }
        }
        deposits[account].iterate = countEarns;
    }

    function _upBalanceByItarate(address account, uint256 iterate)
    public
    {
        require(countEarns - deposits[account].iterate>=iterate, "E7");
        for(uint256 i = deposits[account].iterate; i<iterate+deposits[account].iterate; i++){
            for(uint256 j =0; j<countTokens; j++){
                if(i==deposits[account].depositIterate[tokens[j]]){
                    deposits[account].balanceBLID += earnBLID[i].allBLID*uint((int((deposits[account].amount[tokens[j]]*earnBLID[i].rates[tokens[j]])*earnBLID[i].timestamp)-(deposits[account].tokenTime[tokens[j]]*int(earnBLID[i].rates[tokens[j]]))))/earnBLID[i].tdt/(1 ether);
                }
                else{
                    
                    deposits[account].balanceBLID += earnBLID[i].allBLID*(earnBLID[i].timestamp-earnBLID[i-1].timestamp)*deposits[account].amount[tokens[j]]*earnBLID[i].rates[tokens[j]]/earnBLID[i].tdt/(1 ether);
                    
                }
            }
        }
        deposits[account].iterate += iterate;
    }

    function balanceEarnBLID(address account) view public returns(uint256)
    {
        if( deposits[account].tokenTime[address(0)]==0||countEarns==0){
            return 0;
        }
        uint256 sum = 0;
        for(uint256 i = deposits[account].iterate;i<countEarns;i++){
             for(uint256 j =0; j<countTokens; j++){
                if(i==deposits[account].depositIterate[tokens[j]]){
                    sum += earnBLID[i].allBLID*uint((int((deposits[account].amount[tokens[j]]*earnBLID[i].rates[tokens[j]])*earnBLID[i].timestamp)-(deposits[account].tokenTime[tokens[j]]*int(earnBLID[i].rates[tokens[j]]))))/earnBLID[i].tdt/(1 ether);
                }
                else{
                    
                    sum += earnBLID[i].allBLID*(earnBLID[i].timestamp-earnBLID[i-1].timestamp)*deposits[account].amount[tokens[j]]*earnBLID[i].rates[tokens[j]]/earnBLID[i].tdt/(1 ether);
                    
                }
            }
        }
        return sum+deposits[account].balanceBLID;
    }
    function balanceOf(address account) view public returns (uint256) {
        uint256 sum = 0;
        for(uint256 j = 0; j<countTokens; j++){
            sum += (deposits[account].amount[tokens[j]]*uint256(AggregatorV3Interface(oracles[tokens[j]]).latestAnswer())*10**(18-AggregatorV3Interface(oracles[tokens[j]]).decimals())/(1 ether));
        }
        return sum;
    }
    function getBLIDReserve() view public returns (uint256) {
        return reserveBLID;
    }
    function getTotalDeposit() view public returns (uint256) {
       uint256 sum = 0;
        for(uint256 j = 0; j<countTokens; j++){
            sum += (tokenDeposited[tokens[j]]*uint256(AggregatorV3Interface(oracles[tokens[j]]).latestAnswer())*10**(18-AggregatorV3Interface(oracles[tokens[j]]).decimals()))/(1 ether);
        }
        return sum;
    }
    function getTokenBalance(address token) view public returns (uint256) {
        return tokenBalance[token];
    }
    function getTokenDeposit(address account, address token) view public returns (uint256) {
        return deposits[account].amount[token];
    }
    function _isUsedToken(address _token) view public returns (bool) {
        return tokensAdd[_token];
    }
    function getCountEarns() view public returns(uint){
        return countEarns;
    }
    function getEarnsByID(uint id) view public returns(uint,uint,uint){
        return (earnBLID[id].allBLID, earnBLID[id].timestamp, earnBLID[id].usd);
    }
    function getTokenDeposited(address token) view public returns (uint256) {
        return tokenDeposited[token];
    }
}
