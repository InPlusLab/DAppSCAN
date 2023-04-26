pragma solidity 0.7.4;
pragma experimental ABIEncoderV2;
//Core contract on Mainnet: 0x7a72b2C51670a3D77d4205C2DB90F6ddb09E4303

interface Oracle {
  function getTotalValueLockedInternalByToken(address tokenAddress, address tier2Address) external view returns (uint256);
  function getTotalValueLockedAggregated(uint256 optionIndex) external view returns (uint256);
  function getStakableTokens() view external  returns (address[] memory, string[] memory);
  function getAPR ( address tier2Address, address tokenAddress ) external view returns ( uint256 );
  function getAmountStakedByUser(address tokenAddress, address userAddress, address tier2Address) external view returns(uint256);
  function getUserCurrentReward(address userAddress, address tokenAddress, address tier2FarmAddress) view external returns(uint256);
  function getTokenPrice(address tokenAddress) view external returns(uint256);
  function getUserWalletBalance(address userAddress, address tokenAddress) external view returns (uint256);
}
interface Tier1Staking {
  function deposit ( string memory tier2ContractName, address tokenAddress, uint256 amount, address onBehalfOf ) external payable returns ( bool );
  function withdraw ( string memory tier2ContractName, address tokenAddress, uint256 amount, address onBehalfOf ) external payable returns ( bool );
}

interface Converter {
  function unwrap ( address sourceToken, address destinationToken, uint256 amount ) external payable returns ( uint256 );
  function wrap ( address sourceToken, address[] memory destinationTokens, uint256 amount ) external payable returns ( address, uint256 );
}
interface ERC20 {
    function totalSupply() external view returns(uint supply);

    function balanceOf(address _owner) external view returns(uint balance);

    function transfer(address _to, uint _value) external returns(bool success);

    function transferFrom(address _from, address _to, uint _value) external returns(bool success);

    function approve(address _spender, uint _value) external returns(bool success);

    function allowance(address _owner, address _spender) external view returns(uint remaining);

    function decimals() external view returns(uint digits);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
    function deposit() external payable;

    function withdraw(uint256 wad) external;
}


contract Core{

    //globals
    address public oracleAddress;
    address public converterAddress;
    address public stakingAddress;
    Oracle oracle;
    Tier1Staking staking;
    Converter converter;
    address public ETH_TOKEN_PLACEHOLDER_ADDRESS  = address(0x0);
    address payable public owner;
    address public WETH_TOKEN_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    ERC20 wethToken = ERC20(WETH_TOKEN_ADDRESS);
    uint256 approvalAmount = 1000000000000000000000000000000;

    //Reeentrancy
     uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;



    modifier onlyOwner {
           require(
               msg.sender == owner,
               "Only owner can call this function."
           );
           _;
   }
   modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }


  constructor() public payable {
        owner= msg.sender;
        setConverterAddress(0x1d17F9007282F9388bc9037688ADE4344b2cC49B);
        _status = _NOT_ENTERED;
  }

  fallback() external payable {
      //for the converter to unwrap ETH when delegate calling. The contract has to be able to accept ETH for this reason. The emergency withdrawal call is to pick any change up for these conversions.
  }

  function setOracleAddress(address theAddress) public onlyOwner returns(bool){
    oracleAddress = theAddress;
    oracle = Oracle(theAddress);
    return true;
  }

  function setStakingAddress(address theAddress) public onlyOwner returns(bool){
    stakingAddress = theAddress;
    staking = Tier1Staking(theAddress);
    return true;
  }
  function setConverterAddress(address theAddress) public onlyOwner returns(bool){
    converterAddress = theAddress;
    converter = Converter(theAddress);
    return true;
  }


  function changeOwner(address payable newOwner) onlyOwner public returns (bool){
    owner = newOwner;
    return true;
  }

   function deposit(string memory tier2ContractName, address tokenAddress, uint256 amount) nonReentrant() payable public returns (bool){

        ERC20 token;
       if(tokenAddress==ETH_TOKEN_PLACEHOLDER_ADDRESS){
                wethToken.deposit{value:msg.value}();
                tokenAddress=WETH_TOKEN_ADDRESS;
                token = ERC20(tokenAddress);
        }
        else{
            token = ERC20(tokenAddress);
            token.transferFrom(msg.sender, address(this), amount);
        }
       token.approve(stakingAddress, approvalAmount);
       bool result = staking.deposit(tier2ContractName, tokenAddress, amount, msg.sender);
       require(result, "There was an issue in core with your deposit request. Please see logs");
        return result;

   }

   function withdraw(string memory tier2ContractName, address tokenAddress, uint256 amount) nonReentrant() payable public returns(bool){
      bool result = staking.withdraw(tier2ContractName, tokenAddress, amount, msg.sender);
        require(result, "There was an issue in core with your withdrawal request. Please see logs");
        return result;
    }

    function convert(address sourceToken, address[] memory destinationTokens, uint256 amount) public payable returns(address, uint256){

        if(sourceToken != ETH_TOKEN_PLACEHOLDER_ADDRESS){
            ERC20 token = ERC20(sourceToken);
            require(token.transferFrom(msg.sender, address(this), amount), "You must approve this contract or have enough tokens to do this conversion");
        }

        ( address destinationTokenAddress, uint256 _amount) = converter.wrap{value:msg.value}(sourceToken, destinationTokens, amount);

        ERC20 token = ERC20(destinationTokenAddress);
        token.transfer(msg.sender, _amount);
        return (destinationTokenAddress, _amount);

    }

    //deconverting is mostly for LP tokens back to another token, as these cant be simply swapped on uniswap
   function deconvert(address sourceToken, address destinationToken, uint256 amount) public payable returns(uint256){
       uint256 _amount = converter.unwrap{value:msg.value}(sourceToken, destinationToken, amount);
       ERC20 token = ERC20(destinationToken);
        token.transfer(msg.sender, _amount);
       return _amount;
    }

    function getStakableTokens() view public  returns (address[] memory, string[] memory){

        (address [] memory stakableAddresses, string [] memory stakableTokenNames) = oracle.getStakableTokens();
        return (stakableAddresses, stakableTokenNames);

    }



   function getAPR(address tier2Address, address tokenAddress) public view returns(uint256){

     uint256 result = oracle.getAPR(tier2Address, tokenAddress);
     return result;
   }

   function getTotalValueLockedAggregated(uint256 optionIndex) public view returns (uint256){
      uint256 result = oracle.getTotalValueLockedAggregated(optionIndex);
      return result;
   }

   function getTotalValueLockedInternalByToken(address tokenAddress, address tier2Address) public view returns (uint256){
      uint256 result = oracle.getTotalValueLockedInternalByToken( tokenAddress, tier2Address);
      return result;
   }

   function getAmountStakedByUser(address tokenAddress, address userAddress, address tier2Address) public view returns(uint256){
        uint256 result = oracle.getAmountStakedByUser(tokenAddress, userAddress,  tier2Address);
        return result;
   }

   function getUserCurrentReward(address userAddress, address tokenAddress, address tier2FarmAddress) view public returns(uint256){
        return oracle.getUserCurrentReward( userAddress,  tokenAddress, tier2FarmAddress);
   }

   function getTokenPrice(address tokenAddress) view public returns(uint256){
        uint256 result = oracle.getTokenPrice(tokenAddress);
        return result;
   }

    function getUserWalletBalance(address userAddress, address tokenAddress) public view returns (uint256){
        uint256 result = oracle.getUserWalletBalance( userAddress, tokenAddress);
        return result;

    }

    function updateWETHAddress(address newAddress) onlyOwner public returns(bool){
        WETH_TOKEN_ADDRESS = newAddress;
        wethToken= ERC20(newAddress);
    }

    function adminEmergencyWithdrawAccidentallyDepositedTokens(address token, uint amount, address payable destination) public onlyOwner returns(bool) {

         if (address(token) == ETH_TOKEN_PLACEHOLDER_ADDRESS) {
             destination.transfer(amount);
         }
         else {
             ERC20 tokenToken = ERC20(token);
             require(tokenToken.transfer(destination, amount));
         }

         return true;
     }


}
