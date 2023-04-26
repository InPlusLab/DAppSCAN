// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.8.0;
//https://etherscan.io/address/0x2ae7b37ab144b5f8c803546b83e81ad297d8c2c4#code

interface ERC20 {
    function totalSupply() external view returns(uint supply);

    function balanceOf(address _owner) external view returns(uint balance);

    function transfer(address _to, uint _value) external returns(bool success);

    function transferFrom(address _from, address _to, uint _value) external returns(bool success);

    function approve(address _spender, uint _value) external returns(bool success);

    function allowance(address _owner, address _spender) external view returns(uint remaining);

    function decimals() external view returns(uint digits);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
}

interface externalPlatformContract{
    function getAPR(address _farmAddress, address _tokenAddress) external view returns(uint apy);
    function getStakedPoolBalanceByUser(address _owner, address tokenAddress) external view returns(uint256);
    function commission() external view returns(uint256);
    function totalAmountStaked(address tokenAddress) external view returns(uint256);
    function depositBalances(address userAddress, address tokenAddress) external view returns(uint256);

}
interface Oracle {
  function getAddress(string memory) view external returns (address);

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





contract TokenRewards{

  using SafeMath
    for uint256;

  address public stakingTokensAddress;
  address public stakingLPTokensAddress;

  uint256 public tokensInRewardsReserve = 0;
  uint256 public lpTokensInRewardsReserve  = 0;

  //(100% APR = 100000), .01% APR = 10)
  mapping (address => uint256) public tokenAPRs;

  mapping (address => bool) public stakingTokenWhitelist;

  mapping (address => mapping(address => uint256[])) public depositBalances;
  mapping (address => mapping(address => uint256)) public tokenDeposits;


   mapping (address => mapping(address => uint256[])) public depositBalancesDelegated;
  mapping (address => mapping(address => uint256)) public tokenDepositsDelegated;
  address ETH_TOKEN_ADDRESS  = address(0x0);

  Oracle oracle;
    address oracleAddress;


  address payable public owner;


  modifier onlyOwner {
         require(
             msg.sender == owner,
             "Only owner can call this function."
         );
         _;
 }

 modifier onlyTier1 {
        require(
            msg.sender == oracle.getAddress("TIER1"),
            "Only oracles TIER1 can call this function."
        );
        _;
}


  constructor() public payable {
        owner= msg.sender;

  }

  function updateOracleAddress(address newOracleAddress ) public onlyOwner returns (bool){
    oracleAddress= newOracleAddress;
    oracle = Oracle(newOracleAddress);
    return true;

  }


  function updateStakingTokenAddress(address newAddress) public onlyOwner returns(bool){
    stakingTokensAddress = newAddress;
    return true;
  }

  function updateLPStakingTokenAddress(address newAddress) public  onlyOwner returns(bool){
    stakingLPTokensAddress= newAddress;
    return true;
  }

  function addTokenToWhitelist(address newTokenAddress) public onlyOwner returns(bool){
    stakingTokenWhitelist[newTokenAddress] =true;
    return true;
  }

  function removeTokenFromWhitelist(address tokenAddress) public onlyOwner returns(bool){
    stakingTokenWhitelist[tokenAddress] =false;
    return true;
  }




  //APR should have be in this format (uint representing decimals): (100% APR = 100000), .01% APR = 10)
  function updateAPR(uint256 newAPR, address stakedToken) public onlyOwner returns(bool){

    tokenAPRs[stakedToken] = newAPR;

    return true;
  }


  function stake(uint256 amount, address tokenAddress, address onBehalfOf) public returns(bool){

      require(stakingTokenWhitelist[tokenAddress] ==true, "The token you are staking is not whitelisted to earn rewards");

      ERC20 token = ERC20(tokenAddress);

      require(token.transferFrom(msg.sender, address(this), amount), "The msg.sender does not have enough tokens or has not approved token transfers from this address");

      bool redepositing=false;

      if(tokenDeposits[onBehalfOf][tokenAddress] !=0){

        //uint256 originalUserBalance = depositBalances[onBehalfOf];
        //uint256 amountAfterRewards = unstakeAndClaim(onBehalfOf, address(this));
        redepositing = true;

      }

      if(redepositing == true){
        depositBalances[onBehalfOf][tokenAddress] = [block.timestamp, (tokenDeposits[onBehalfOf][tokenAddress].add(amount))] ;
        tokenDeposits[onBehalfOf][tokenAddress]= tokenDeposits[onBehalfOf][tokenAddress].add(amount);
      }

      else{
        depositBalances[onBehalfOf][tokenAddress] = [block.timestamp, amount];
        tokenDeposits[onBehalfOf][tokenAddress]= amount;
      }

      return true;

  }


  function stakeDelegated(uint256 amount, address tokenAddress, address onBehalfOf) public onlyTier1 returns(bool){

      require(stakingTokenWhitelist[tokenAddress] ==true, "The token you are staking is not whitelisted to earn rewards");

      ERC20 token = ERC20(tokenAddress);

      bool redepositing=false;

      if(tokenDepositsDelegated[onBehalfOf][tokenAddress] !=0){

        //uint256 originalUserBalance = depositBalances[onBehalfOf];
        //uint256 amountAfterRewards = unstakeAndClaim(onBehalfOf, address(this));
        redepositing = true;

      }

      if(redepositing == true){
        depositBalancesDelegated[onBehalfOf][tokenAddress] = [block.timestamp, (tokenDepositsDelegated[onBehalfOf][tokenAddress].add(amount))] ;
        tokenDepositsDelegated[onBehalfOf][tokenAddress]= tokenDepositsDelegated[onBehalfOf][tokenAddress].add(amount);
      }

      else{
        depositBalancesDelegated[onBehalfOf][tokenAddress] = [block.timestamp, amount];
        tokenDepositsDelegated[onBehalfOf][tokenAddress]= amount;
      }

      return true;

  }


  //when standalone, this is called. It's brother (delegated version that does not deal with transfers is called in other instances)
  function unstakeAndClaim(address onBehalfOf, address tokenAddress, address recipient) public returns (uint256){

    require(stakingTokenWhitelist[tokenAddress] ==true, "The token you are staking is not whitelisted");

    require(tokenDeposits[onBehalfOf][tokenAddress] > 0, "This user address does not have a staked balance for the token");

    uint256 rewards = calculateRewards(depositBalances[onBehalfOf][tokenAddress][0], block.timestamp, tokenDeposits[onBehalfOf][tokenAddress], tokenAPRs[tokenAddress]);
    uint256 principalPlusRewards = tokenDeposits[onBehalfOf][tokenAddress].add(rewards);

    ERC20 principalToken = ERC20(tokenAddress);
    ERC20 rewardToken = ERC20(stakingTokensAddress);

    uint256 principalTokenDecimals= principalToken.decimals();
    uint256 rewardTokenDecimals = rewardToken.decimals();

    //account for different token decimals places/denoms
    if(principalTokenDecimals < rewardToken.decimals()){
      uint256 decimalDiff = rewardTokenDecimals.sub(principalTokenDecimals);
      rewards = rewards.mul(10**decimalDiff);
    }

    if(principalTokenDecimals > rewardTokenDecimals){
      uint256 decimalDiff = principalTokenDecimals.sub(rewardTokenDecimals);
      rewards = rewards.div(10**decimalDiff);
    }




    require(principalToken.transfer(recipient, tokenDeposits[onBehalfOf][tokenAddress]), "There are not enough tokens in the pool to return principal. Contact the pool owner.");

    //not requiring this below, as we need to ensure at the very least the user gets their deposited tokens above back.
    rewardToken.transfer(recipient, rewards);

    tokenDeposits[onBehalfOf][tokenAddress] = 0;
    depositBalances[onBehalfOf][tokenAddress]= [block.timestamp, 0];


    return rewards;
  }


  //when apart of ecosystem, delegated is called
  function unstakeAndClaimDelegated(address onBehalfOf, address tokenAddress, address recipient) public onlyTier1 returns (uint256) {

    require(stakingTokenWhitelist[tokenAddress] ==true, "The token you are staking is not whitelisted");

    require(tokenDepositsDelegated[onBehalfOf][tokenAddress] > 0, "This user address does not have a staked balance for the token");

    uint256 rewards = calculateRewards(depositBalancesDelegated[onBehalfOf][tokenAddress][0], block.timestamp, tokenDepositsDelegated[onBehalfOf][tokenAddress], tokenAPRs[tokenAddress]);
    uint256 principalPlusRewards = tokenDepositsDelegated[onBehalfOf][tokenAddress].add(rewards);

    ERC20 principalToken = ERC20(tokenAddress);
    ERC20 rewardToken = ERC20(stakingTokensAddress);

    uint256 principalTokenDecimals= principalToken.decimals();
    uint256 rewardTokenDecimals = rewardToken.decimals();

    //account for different token decimals places/denoms
    if(principalTokenDecimals < rewardToken.decimals()){
      uint256 decimalDiff = rewardTokenDecimals.sub(principalTokenDecimals);
      rewards = rewards.mul(10**decimalDiff);
    }

    if(principalTokenDecimals > rewardTokenDecimals){
      uint256 decimalDiff = principalTokenDecimals.sub(rewardTokenDecimals);
      rewards = rewards.div(10**decimalDiff);
    }






    rewardToken.transfer(recipient, rewards);

    tokenDepositsDelegated[onBehalfOf][tokenAddress] = 0;
    depositBalancesDelegated[onBehalfOf][tokenAddress]= [block.timestamp, 0];


    return rewards;
  }

    function adminEmergencyWithdrawTokens(address token, uint amount, address payable destination) public onlyOwner returns(bool) {



      if (address(token) == ETH_TOKEN_ADDRESS) {
          destination.transfer(amount);
      }
      else {
          ERC20 tokenToken = ERC20(token);
          require(tokenToken.transfer(destination, amount));
      }




      return true;
  }


  //APR should have 3 zeroes after decimal (100% APR = 100000), .01% APR = 10)
  function calculateRewards(uint256 timestampStart, uint256 timestampEnd, uint256 principalAmount, uint256 apr) public view returns(uint256){
    uint256 timeDiff = timestampEnd.sub(timestampStart);
    if(timeDiff <= 0){
      return 0;
    }

    apr = apr.mul(10000000);
    //365.25 days, accounting for leap years. We should just have 1/4 days at the end of each year and cause more mass confusion than daylight savings. "Please set your clocks back 6 hours on Jan 1st, Thank you""
    //Imagine new years. You get to do it twice after 6hours. Or would it be recursive and end up in an infinite loop. Is that the secret to freezing time and staying young? Maybe because it's 2020.
    uint256 secondsInAvgYear = 31557600;

    uint256 rewardsPerSecond = (principalAmount.mul(apr)).div(secondsInAvgYear);
    uint256 rawRewards = timeDiff.mul(rewardsPerSecond);
    uint256 normalizedRewards = rawRewards.div(10000000000);
    return normalizedRewards;


  }




}
