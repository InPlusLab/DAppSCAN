// SPDX-License-Identifier: MIT
//Mainnet: 0x97b00db19bAe93389ba652845150CAdc597C6B2F
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


interface Tier2StakingInterface {

  //staked balance info
  function depositBalances(address _owner, address token) external view returns(uint256 balance);
  function getStakedBalances(address _owner, address token) external view returns(uint256 balance);
  function getStakedPoolBalanceByUser(address _owner, address tokenAddress) external view returns(uint256);

  //basic info
  function tokenToFarmMapping(address tokenAddress) external view returns(address stakingContractAddress);
  function stakingContracts(string calldata platformName) external view returns(address stakingAddress);
  function stakingContractsStakingToken(string calldata platformName) external view returns(address tokenAddress);
  function platformToken() external view returns(address tokenAddress);
  function owner() external view returns(address ownerAddress);

  //actions
  function deposit(address tokenAddress, uint256 amount, address onBehalfOf) payable external returns (bool);
  function withdraw(address tokenAddress, uint256 amount, address payable onBehalfOf) payable external returns(bool);
  function addOrEditStakingContract(string calldata name, address stakingAddress, address stakingToken ) external  returns (bool);
  function updateCommission(uint amount) external  returns(bool);
  function changeOwner(address payable newOwner) external returns (bool);
  function adminEmergencyWithdrawTokens(address token, uint amount, address payable destination) external returns(bool);
  function kill() virtual external;
}
interface Oracle {
  function getAddress(string memory) view external returns (address);

}

interface Rewards {
  function unstakeAndClaimDelegated(uint256 amount, address onBehalfOf, address tokenAddress, address recipient) external returns (uint256);
  function stakeDelegated(uint256 amount, address tokenAddress, address onBehalfOf) external returns(bool);

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





contract Tier1FarmController{

  using SafeMath
    for uint256;


  address payable public owner;
  address payable public admin;
  address ETH_TOKEN_ADDRESS  = address(0x0);
  mapping (string => address) public tier2StakingContracts;
  uint256 public commission  = 400; // Default is 4 percent
    Oracle oracle;
    address oracleAddress;

  string public farmName = 'Tier1Aggregator';
  mapping (address => uint256) totalAmountStaked;

  modifier onlyOwner {
         require(
             msg.sender == owner,
             "Only owner can call this function."
         );
         _;
 }

 modifier onlyAdmin {
         require(
             msg.sender == oracle.getAddress("CORE"),
             "Only owner can call this function."
         );
         _;
 }






  constructor() public payable {
        tier2StakingContracts["FARM"] = 0x618fDCFF3Cca243c12E6b508D9d8a6fF9018325c;

        owner= msg.sender;
        updateOracleAddress(0xBDfF00110c97D0FE7Fefbb78CE254B12B9A7f41f);

  }


  fallback() external payable {


  }

function updateOracleAddress(address newOracleAddress ) public onlyOwner returns (bool){
    oracleAddress= newOracleAddress;
    oracle = Oracle(newOracleAddress);
    return true;

  }


  function addOrEditTier2ChildStakingContract(string memory name, address stakingAddress ) public onlyOwner returns (bool){

    tier2StakingContracts[name] = stakingAddress;
    return true;

  }

  function addOrEditTier2ChildsChildStakingContract(address tier2Contract, string memory name, address stakingAddress, address stakingToken ) public onlyOwner returns (bool){

    Tier2StakingInterface tier2Con = Tier2StakingInterface(tier2Contract);
    tier2Con.addOrEditStakingContract(name, stakingAddress, stakingToken);
    return true;

  }

  function updateCommissionTier2(address tier2Contract, uint amount) public onlyOwner returns(bool){
    Tier2StakingInterface tier2Con = Tier2StakingInterface(tier2Contract);
    tier2Con.updateCommission(amount);
    return true;
  }





  function deposit(string memory tier2ContractName, address tokenAddress, uint256 amount, address payable onBehalfOf) onlyAdmin payable public returns (bool){

    address tier2Contract = tier2StakingContracts[tier2ContractName];
    ERC20 thisToken = ERC20(tokenAddress);
    require(thisToken.transferFrom(msg.sender, address(this), amount), "Not enough tokens to transferFrom or no approval");
    //approve the tier2 contract to handle tokens from this account
    thisToken.approve(tier2Contract, amount.mul(100));

    Tier2StakingInterface tier2Con = Tier2StakingInterface(tier2Contract);

    tier2Con.deposit(tokenAddress, amount, onBehalfOf);

    address  rewardsContract = oracle.getAddress("REWARDS");

    if(rewardsContract != address(0x0)){
        Rewards rewards = Rewards(rewardsContract);
         try rewards.stakeDelegated(amount, tokenAddress, onBehalfOf) {

        }
        catch{

        }
    }



      return true;
   }






  function withdraw(string memory tier2ContractName, address tokenAddress, uint256 amount, address payable onBehalfOf) onlyAdmin payable public returns(bool){

        address tier2Contract = tier2StakingContracts[tier2ContractName];
        ERC20 thisToken = ERC20(tokenAddress);
        Tier2StakingInterface tier2Con = Tier2StakingInterface(tier2Contract);
        tier2Con.withdraw(tokenAddress, amount, onBehalfOf);
        address rewardsContract = oracle.getAddress("REWARDS");
          if(rewardsContract != address(0x0)){
            Rewards rewards = Rewards(rewardsContract);

           try rewards.unstakeAndClaimDelegated(amount, onBehalfOf, tokenAddress, onBehalfOf){

           }
           catch{

           }

          }
     return true;
   }


   function changeTier2Owner(address payable tier2Contract, address payable newOwner) onlyOwner public returns (bool){
     Tier2StakingInterface tier2Con = Tier2StakingInterface(tier2Contract);
     tier2Con.changeOwner(newOwner);
     return true;
   }

   function changeOwner(address payable newOwner) onlyOwner public returns (bool){
     owner = newOwner;
     return true;
   }

   //admin can deposit and withdraw and should be the core contract

   /*
   function changeAdmin(address payable newAdmin) onlyAdmin public returns (bool){
     admin = newAdmin;
     return true;
   }
   */




  function adminEmergencyWithdrawTokensTier2(address payable tier2Contract, address token, uint amount, address payable destination) public onlyOwner returns(bool) {
    Tier2StakingInterface tier2Con = Tier2StakingInterface(tier2Contract);
    tier2Con.adminEmergencyWithdrawTokens(token, amount, destination);
    return true;
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



function getStakedPoolBalanceByUser(string memory tier2ContractName, address _owner, address tokenAddress) public view returns(uint256){
  address tier2Contract = tier2StakingContracts[tier2ContractName];
  ERC20 thisToken = ERC20(tokenAddress);
  Tier2StakingInterface tier2Con = Tier2StakingInterface(tier2Contract);
  uint balance = tier2Con.getStakedPoolBalanceByUser(_owner, tokenAddress);
  return balance;

}

function getDepositBalanceByUser(string calldata tier2ContractName, address _owner, address token) external view returns(uint256 ){
  address tier2Contract = tier2StakingContracts[tier2ContractName];
  ERC20 thisToken = ERC20(token);
  Tier2StakingInterface tier2Con = Tier2StakingInterface(tier2Contract);
  uint balance = tier2Con.depositBalances(_owner, token);
  return balance;
}


 function kill() virtual public onlyOwner {

         selfdestruct(owner);

 }







}
