// Aave AToken Deposit (Converts from regular token to aToken, stores in this contract, and withdraws based on percentage of pool)
pragma solidity >=0.4.22 <0.8.0;

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




interface StakingInterface  {

  function deposit ( address asset, uint256 amount, address onBehalfOf, uint16 referralCode ) external;
  function getReservesList (  ) external view returns ( address[] memory );
  function getUserAccountData ( address user ) external view returns ( uint256 totalCollateralETH, uint256 totalDebtETH, uint256 availableBorrowsETH, uint256 currentLiquidationThreshold, uint256 ltv, uint256 healthFactor );
  function withdraw ( address asset, uint256 amount, address to ) external returns ( uint256 );
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





contract Tier2FarmController{

  using SafeMath
    for uint256;


  address payable public owner;
  address payable public admin;
  address public platformToken = 0x25550Cccbd68533Fa04bFD3e3AC4D09f9e00Fc50;
  address public tokenStakingContract = 0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9;
  address ETH_TOKEN_ADDRESS  = address(0x0);
  mapping (string => address) public stakingContracts;
  mapping (address => address) public tokenToFarmMapping;
  mapping (string => address) public stakingContractsStakingToken;
  mapping (address => mapping (address => uint256)) public depositBalances;
  mapping (address => address) public tokenToAToken;
    mapping (address => address) public aTokenToToken;
  uint256 public commission  = 400; // Default is 4 percent


  string public farmName = 'Aave';
  mapping (address => uint256) public totalAmountStaked;

   modifier onlyOwner {
         require(
             msg.sender == owner,
             "Only owner can call this function."
         );
         _;
 }

  modifier onlyAdmin {
         require(
             msg.sender == admin,
             "Only admin can call this function."
         );
         _;
 }







  constructor() public payable {
        stakingContracts["DAI"] =0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9 ;
        stakingContracts["ALL"] =0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9 ;
        stakingContractsStakingToken ["DAI"] = 0x25550Cccbd68533Fa04bFD3e3AC4D09f9e00Fc50;
        tokenToAToken[0x6B175474E89094C44Da98b954EedeAC495271d0F]= 0x25550Cccbd68533Fa04bFD3e3AC4D09f9e00Fc50;
        aTokenToToken[0x25550Cccbd68533Fa04bFD3e3AC4D09f9e00Fc50]= 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        tokenToFarmMapping[stakingContractsStakingToken ["DAI"]] =  stakingContracts["DAI"];
        owner= msg.sender;
        admin = msg.sender;

  }


  fallback() external payable {


  }


function updateATokens(address tokenAddress, address aTokenAddress) public onlyAdmin returns (bool){
    tokenToAToken[tokenAddress] = aTokenAddress;
    aTokenToToken[aTokenAddress] = tokenAddress;
    return true;
}

  function addOrEditStakingContract(string memory name, address stakingAddress, address stakingToken ) public onlyOwner returns (bool){

    stakingContracts[name] = stakingAddress;
    stakingContractsStakingToken[name] = stakingToken;
    tokenToFarmMapping[stakingToken] = stakingAddress;

    return true;

  }

  function updateCommission(uint amount) public onlyOwner returns(bool){
      commission = amount;
      return true;
  }

  function deposit(address tokenAddress, uint256 amount, address onBehalfOf) payable onlyOwner public returns (bool){




        ERC20 thisToken = ERC20(tokenAddress);
        require(thisToken.transferFrom(msg.sender, address(this), amount), "Not enough tokens to transferFrom or no approval");

        depositBalances[onBehalfOf][tokenAddress] = depositBalances[onBehalfOf][tokenAddress].add(amount);

        uint256 approvedAmount = thisToken.allowance(address(this), tokenToFarmMapping[tokenAddress]);
        if(approvedAmount < amount  ){
            thisToken.approve(tokenToFarmMapping[tokenAddress], amount.mul(10000000));
        }
        stake(amount, onBehalfOf, tokenAddress );

        totalAmountStaked[tokenAddress] = totalAmountStaked[tokenAddress].add(amount);

        emit Deposit(onBehalfOf, amount, tokenAddress);
        return true;
   }

   function stake(uint256 amount, address onBehalfOf, address tokenAddress) internal returns(bool){

      StakingInterface staker  = StakingInterface(tokenToFarmMapping[tokenAddress]);
      staker.deposit(tokenAddress, amount, address(this), 0);
      return true;

   }

   function unstake(uint256 amount, address onBehalfOf, address tokenAddress) internal returns(bool){
      ERC20 aToken  = ERC20(tokenToAToken[tokenAddress]);
      StakingInterface staker  =  StakingInterface(tokenToFarmMapping[tokenAddress]);
      staker.withdraw(tokenAddress, aToken.balanceOf(address(this)), address(this));
      return true;

   }


   function getStakedPoolBalanceByUser(address _owner, address tokenAddress) public view returns(uint256){
        StakingInterface staker  = StakingInterface(tokenToFarmMapping[tokenAddress]);
        ERC20 aToken  = ERC20(tokenToAToken[tokenAddress]);
        uint256 numberTokens = aToken.balanceOf(address(this));

        uint256 usersBalancePercentage = (depositBalances[_owner][tokenAddress].mul(1000000)).div(totalAmountStaked[tokenAddress]);
        uint256 numberTokensPlusRewardsForUser= (numberTokens.mul(1000).mul(usersBalancePercentage)).div(1000000000);


        return numberTokensPlusRewardsForUser;

    }

  //SWC-135-Code With No Effects: 205-253
  function withdraw(address tokenAddress, uint256 amount, address payable onBehalfOf) onlyOwner payable public returns(bool){

      ERC20 thisToken = ERC20(tokenAddress);
      //uint256 numberTokensPreWithdrawal = getStakedBalance(address(this), tokenAddress);

        if(tokenAddress == 0x0000000000000000000000000000000000000000){
            require(depositBalances[msg.sender][tokenAddress] >= amount, "You didnt deposit enough eth");

            totalAmountStaked[tokenAddress] = totalAmountStaked[tokenAddress].sub(depositBalances[onBehalfOf][tokenAddress]);
            depositBalances[onBehalfOf][tokenAddress] = depositBalances[onBehalfOf][tokenAddress]  - amount;
            onBehalfOf.send(amount);
            return true;

        }

        require(depositBalances[onBehalfOf][tokenAddress] > 0, "You dont have any tokens deposited");

        //uint256 numberTokensPostWithdrawal = thisToken.balanceOf(address(this));

        //uint256 usersBalancePercentage = depositBalances[onBehalfOf][tokenAddress].div(totalAmountStaked[tokenAddress]);

        uint256 numberTokensPlusRewardsForUser1 = getStakedPoolBalanceByUser(onBehalfOf, tokenAddress);
        uint256 commissionForDAO1 = calculateCommission(numberTokensPlusRewardsForUser1);
        uint256 numberTokensPlusRewardsForUserMinusCommission = numberTokensPlusRewardsForUser1-commissionForDAO1;

        unstake(amount, onBehalfOf, tokenAddress);

        //staking platforms only withdraw all for the most part, and for security sticking to this
        totalAmountStaked[tokenAddress] = totalAmountStaked[tokenAddress].sub(depositBalances[onBehalfOf][tokenAddress]);

        depositBalances[onBehalfOf][tokenAddress] = 0;
        require(numberTokensPlusRewardsForUserMinusCommission >0, "For some reason numberTokensPlusRewardsForUserMinusCommission is zero");

        require(thisToken.transfer(onBehalfOf, numberTokensPlusRewardsForUserMinusCommission), "You dont have enough tokens inside this contract to withdraw from deposits");
        if(numberTokensPlusRewardsForUserMinusCommission >0){
            thisToken.transfer(owner, commissionForDAO1);
        }


        uint256 remainingBalance = thisToken.balanceOf(address(this));
        if(remainingBalance>0){
            stake(remainingBalance, address(this), tokenAddress);
        }


        emit Withdrawal(onBehalfOf, amount, tokenAddress);
        return true;

   }


   function calculateCommission(uint256 amount) view public returns(uint256){
     uint256 commissionForDAO = (amount.mul(1000).mul(commission)).div(10000000);
     return commissionForDAO;
   }

   function changeOwner(address payable newAdmin) onlyOwner public returns (bool){
     owner = newAdmin;
     return true;
   }

   function changeAdmin(address payable newOwner) onlyAdmin public returns (bool){
     admin = newOwner;
     return true;
   }



   function getStakedBalance(address _owner, address tokenAddress) public view returns(uint256){

       ERC20 staker  = ERC20(tokenToAToken[tokenAddress]);
       return staker.balanceOf(_owner);
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



 function kill() virtual public onlyOwner {

         selfdestruct(owner);

 }


    event Deposit(address indexed user, uint256 amount, address token);
    event Withdrawal(address indexed user, uint256 amount, address token);




}
