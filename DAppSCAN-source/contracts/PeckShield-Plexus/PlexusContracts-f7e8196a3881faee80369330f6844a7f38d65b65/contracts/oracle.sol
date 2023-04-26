/**
 *Submitted for verification at Etherscan.io on 2020-12-11
*/

// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;
pragma experimental ABIEncoderV2;


interface ERC20 {
    function balanceOf(address _owner) external view returns(uint balance);
    function allowance(address _owner, address _spender) external view returns(uint remaining);
    function decimals() external view returns(uint digits);
}

interface externalPlatformContract{
    function getAPR(address _farmAddress, address _tokenAddress) external view returns(uint apy);
    function getStakedPoolBalanceByUser(address _owner, address tokenAddress) external view returns(uint256);
    function commission() external view returns(uint256);
    function totalAmountStaked(address tokenAddress) external view returns(uint256);
    function depositBalances(address userAddress, address tokenAddress) external view returns(uint256);

}

interface IUniswapV2RouterLite {

    function getAmountsOut(uint amountIn, address[] memory  path) external view returns (uint[] memory amounts);

}

interface Reward{

  function addTokenToWhitelist ( address newTokenAddress ) external returns ( bool );
  function calculateRewards ( uint256 timestampStart, uint256 timestampEnd, uint256 principalAmount, uint256 apr ) external view returns ( uint256 );
  function depositBalances ( address, address, uint256 ) external view returns ( uint256 );
  function depositBalancesDelegated ( address, address, uint256 ) external view returns ( uint256 );
  function lpTokensInRewardsReserve (  ) external view returns ( uint256 );
  function owner (  ) external view returns ( address );
  function removeTokenFromWhitelist ( address tokenAddress ) external returns ( bool );
  function stake ( uint256 amount, address tokenAddress, address onBehalfOf ) external returns ( bool );
  function stakeDelegated ( uint256 amount, address tokenAddress, address onBehalfOf ) external returns ( bool );
  function stakingLPTokensAddress (  ) external view returns ( address );
  function stakingTokenWhitelist ( address ) external view returns ( bool );
  function stakingTokensAddress (  ) external view returns ( address );
  function tokenAPRs ( address ) external view returns ( uint256 );
  function tokenDeposits ( address, address ) external view returns ( uint256 );
  function tokenDepositsDelegated ( address, address ) external view returns ( uint256 );
  function tokensInRewardsReserve (  ) external view returns ( uint256 );
  function unstakeAndClaim ( address onBehalfOf, address tokenAddress, address recipient ) external returns ( uint256 );
  function unstakeAndClaimDelegated ( address onBehalfOf, address tokenAddress, address recipient ) external returns ( uint256 );
  function updateAPR ( uint256 newAPR, address stakedToken ) external returns ( bool );
  function updateLPStakingTokenAddress ( address newAddress ) external returns ( bool );
  function updateStakingTokenAddress ( address newAddress ) external returns ( bool );


}

interface TVLOracle{
    function getTotalValueLockedInternalByToken(address tokenAddress, address tier2Address) external view returns (uint256);
    function getTotalValueLockedAggregated(uint256 optionIndex) external view returns (uint256);
}




library SafeMath {
  function mul(uint256 a, uint256 b) internal view returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal view returns (uint256) {
    assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }



  function sub(uint256 a, uint256 b) internal view returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal view returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }

}





contract Oracle{

  using SafeMath
    for uint256;


  address payable public owner;
  address burnaddress  = address(0x0);
  mapping (string => address) farmDirectoryByName;
  mapping (address => mapping(address =>uint256)) farmManuallyEnteredAPYs;
  mapping (address => mapping (address  => address )) farmOracleObtainedAPYs;
  string [] public farmTokenPlusFarmNames;
  address [] public farmAddresses;
  address [] public farmTokens;
  address uniswapAddress = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
  IUniswapV2RouterLite uniswap = IUniswapV2RouterLite(uniswapAddress);
  address usdcCoinAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address rewardAddress;
  Reward reward;
  address tvlOracleAddress;
  TVLOracle tvlOracle;
  //core contract adress that users interact with
  address public coreAddress;
  mapping (string  => address) public platformDirectory;


  modifier onlyOwner {
         require(
             msg.sender == owner,
             "Only owner can call this function."
         );
         _;
 }


  constructor() public payable {
        owner= msg.sender;
  }


    function getTotalValueLockedInternalByToken(address tokenAddress, address tier2Address) external view returns (uint256){
        uint256 result = tvlOracle.getTotalValueLockedInternalByToken(tokenAddress, tier2Address);
        return result;
    }

    function getTotalValueLockedAggregated(uint256 optionIndex) external view returns (uint256){
      uint256 result = tvlOracle.getTotalValueLockedAggregated(optionIndex);
      return result;
    }

    function getStakableTokens() view external  returns (address[] memory, string[] memory){
      address[] memory stakableAddrs = farmAddresses;
      string[] memory stakableNames = farmTokenPlusFarmNames;
      return (stakableAddrs, stakableNames);
    }

    function getAPR(address farmAddress, address farmToken)public view returns(uint256){
      uint obtainedAPY = farmManuallyEnteredAPYs[farmAddress][farmToken];

      if(obtainedAPY ==0){
        externalPlatformContract exContract = externalPlatformContract(farmOracleObtainedAPYs[farmAddress][farmToken]);
        try exContract.getAPR(farmAddress, farmToken) returns (uint apy) {
          return apy;
        }
        catch (bytes memory ) {
          return (0);
        }

      }

      else{
        return obtainedAPY;
      }
    }

    function getAmountStakedByUser(address tokenAddress, address userAddress, address tier2Address) external view returns(uint256){
      externalPlatformContract exContract = externalPlatformContract(tier2Address);
      return exContract.getStakedPoolBalanceByUser(userAddress, tokenAddress);
    }

    function getUserCurrentReward(address userAddress, address tokenAddress, address tier2FarmAddress) view external returns(uint256){
        uint256 userStartTime = reward.depositBalancesDelegated(userAddress, tokenAddress,0);

        uint256 principalAmount = reward.depositBalancesDelegated(userAddress, tokenAddress,1);
        uint256 apr = reward.tokenAPRs(tokenAddress);
        uint256 result = reward.calculateRewards( userStartTime, block.timestamp,  principalAmount, apr);
        return result;
    }

    function getTokenPrice(address tokenAddress, uint256 amount) view external returns(uint256){
      address [] memory addresses = new address[](2);
      addresses[0] = tokenAddress;
      addresses[1] = usdcCoinAddress;
      uint256 [] memory amounts = getUniswapPrice(addresses, amount );
      uint256 resultingTokens = amounts[1];
      return resultingTokens;
    }

    function getUserWalletBalance(address userAddress, address tokenAddress) external view returns (uint256){
      ERC20 token = ERC20(tokenAddress);
      return token.balanceOf(userAddress);
    }


    function getAddress(string memory component) public view returns (address){
          return platformDirectory[component];
    }





//BELOW is other (admin and otherwise)

    function updateTVLAddress(address theAddress) onlyOwner public returns(bool){
    tvlOracleAddress = theAddress;
    tvlOracle = TVLOracle(theAddress);
    updateDirectory("TVLORACLE", theAddress);
    return true;
  }

  function updatePriceOracleAddress(address theAddress) onlyOwner public returns(bool){
    uniswapAddress = theAddress;
    uniswap = IUniswapV2RouterLite(theAddress);
    updateDirectory("UNISWAP", theAddress);
    return true;
  }

  function updateUSD(address theAddress) onlyOwner public returns(bool){
    usdcCoinAddress = theAddress;
    updateDirectory("USD", theAddress);
    return true;
  }

  function updateRewardAddress(address theAddress) onlyOwner public returns(bool){
    rewardAddress = theAddress;
    reward = Reward(theAddress);
    updateDirectory("REWARDS", theAddress);
    return true;
  }

  function updateCoreAddress(address theAddress) onlyOwner public returns(bool){
    coreAddress = theAddress;
    updateDirectory("CORE", theAddress);
    return true;
  }

  function updateDirectory(string memory name, address theAddress) onlyOwner public returns(bool){
    platformDirectory[name] = theAddress;
    return true;
  }






  function setPlatformContract(string memory name, address farmAddress, address farmToken, address platformAddress) public onlyOwner returns(bool){
    farmTokenPlusFarmNames.push(name);
    farmAddresses.push(farmAddress);
    farmTokens.push(farmToken);

    farmOracleObtainedAPYs[farmAddress][farmToken] = platformAddress;
    farmDirectoryByName[name] = platformAddress;

    return true;

  }


  function calculateCommission(uint256 amount, uint256 commission) view public returns(uint256){
    uint256 commissionForDAO = (amount.mul(1000).mul(commission)).div(10000000);
    return commissionForDAO;
  }


  function getCommissionByContract(address platformContract) public view returns (uint256){
    externalPlatformContract exContract = externalPlatformContract(platformContract);
    return exContract.commission();

  }


  function getTotalStakedByContract(address platformContract, address tokenAddress) public view returns (uint256){
    externalPlatformContract exContract = externalPlatformContract(platformContract);
    return exContract.totalAmountStaked(tokenAddress);

  }

  function getAmountCurrentlyDepositedByContract(address platformContract, address tokenAddress, address userAddress) public view returns (uint256){

    externalPlatformContract exContract = externalPlatformContract(platformContract);
    return exContract.depositBalances(userAddress, tokenAddress);

  }

  function replaceAllStakableDirectory (string [] memory theNames, address[] memory theFarmAddresses, address[] memory theFarmTokens) onlyOwner public returns (bool){
    farmTokenPlusFarmNames = theNames;
    farmAddresses = theFarmAddresses;
    farmTokens = theFarmTokens;
    return true;

  }

  function getAmountCurrentlyFarmStakedByContract(address platformContract, address tokenAddress, address userAddress) public view returns (uint256){

    externalPlatformContract exContract = externalPlatformContract(platformContract);
    return exContract.getStakedPoolBalanceByUser(userAddress, tokenAddress);
  }

  function getUserTokenBalance(address userAddress, address tokenAddress) public view returns (uint256){
    ERC20 token = ERC20(tokenAddress);
    return token.balanceOf(userAddress);

  }
  function getUniswapPrice(address  [] memory theAddresses, uint amount) internal view returns (uint256[] memory amounts1){
        uint256 [] memory amounts = uniswap.getAmountsOut(amount,theAddresses );

        return amounts;

    }




}
