//"SPDX-License-Identifier: UNLICENSED"

pragma solidity ^0.6.0;

import '@openzeppelin/contracts/math/SafeMath.sol';

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import '@openzeppelin/contracts/access/Ownable.sol';

contract LeadStake is Ownable {
    
    //initializing safe computations
    using SafeMath for uint;

    //LEAD contract address
    address public lead;
    //total amount of staked lead
    uint public totalStaked;
    //tax rate for staking in percentage
    uint public stakingTaxRate;                     //10 = 1%
    //tax amount for registration
    uint public registrationTax;
    //daily return of investment in percentage
    uint8 public dailyROI;                         //100 = 1%
    //tax rate for unstaking in percentage 
    uint public unstakingTaxRate;                   //10 = 1%
    //minimum stakeable LEAD 
    uint public minimumStakeValue;
    //referral allocation from the registration tax
    uint public referralTaxAllocation;
    //stakeholders' indexes
    uint index;
    //pause mechanism
    bool active = true;
    //mapping of stakeholders' indexes to addresses
    mapping(uint => address) public userIndex;
    //mapping of stakeholders' address to number of stakes
    mapping(address => uint) public stakes;
    //mapping of stakeholders' address to stake rewards
    mapping(address => uint) public stakeRewards;
    //mapping of stakeholders' address to number of referrals 
    mapping(address => uint) public referralCount;
    //mapping of stakeholders' address to referral rewards earned 
    mapping(address => uint) public referralRewards;
    //mapping of stakeholder's address to last transaction time for reward calculation
    mapping(address => uint) public lastClock;
    //mapping of addresses to verify registered stakers
    mapping(address => bool) public registered;
    
    //Events
    event OnWithdrawal(address sender, uint amount);
    event OnStake(address sender, uint amount, uint tax);
    event OnUnstake(address sender, uint amount, uint tax);
    event OnDeposit(address sender, uint amount, uint time);
    event OnRegisterAndStake(address stakeholder, uint amount, uint totalTax , address _referrer);
    
    /**
     * @dev Sets the initial values
     */
    constructor(
        address _token,
        uint8 _stakingTaxRate, 
        uint8 _unstakingTaxRate,
        uint8 _dailyROI,
        uint _registrationTax,
        uint _referralTaxAllocation,
        uint _minimumStakeValue) public {
            
        //set initial state variables
        lead = _token;
        stakingTaxRate = _stakingTaxRate;
        unstakingTaxRate = _unstakingTaxRate;
        dailyROI = _dailyROI;
        registrationTax = _registrationTax;
        referralTaxAllocation = _referralTaxAllocation;
        minimumStakeValue = _minimumStakeValue;
    }
    
    //exclusive access for registered address
    modifier onlyRegistered() {
        require(registered[msg.sender] == true, "Staker must be registered");
        _;
    }
    
    //exclusive access for unregistered address
    modifier onlyUnregistered() {
        require(registered[msg.sender] == false, "Staker is already registered");
        _;
    }
        
    //make sure contract is active
    modifier whenActive() {
        require(active == true, "Smart contract is curently inactive");
        _;
    }
    
    /**
     * registers and creates stakes for new stakeholders
     * deducts the registration tax and staking tax
     * calculates refferal bonus from the registration tax and sends it to the _referrer if there is one
     * transfers LEAD from sender's address into the smart contract
     * Emits an {OnRegisterAndStake} event..
     */
    function registerAndStake(uint _amount, address _referrer) external onlyUnregistered() whenActive() {
        //makes sure user is not the referrer
        require(msg.sender != _referrer, "Cannot refer self");
        //makes sure referrer is registered already
        require(registered[_referrer] || address(0x0) == _referrer, "Referrer must be registered");
        //makes sure user has enough amount
        require(IERC20(lead).balanceOf(msg.sender) >= _amount, "Must have enough balance to stake");
        //makes sure smart contract transfers LEAD from user
        require(IERC20(lead).transferFrom(msg.sender, address(this), _amount), "Stake failed due to failed amount transfer.");
        //makes sure amount is more than the registration fee and the minimum deposit
        require(_amount >= registrationTax.add(minimumStakeValue), "Must send at least enough LEAD to pay registration fee.");
        //calculates referral bonus
        uint referralBonus = (registrationTax.mul(referralTaxAllocation)).div(100);
        //calculates final amount after deducting registration tax
        uint finalAmount = _amount.sub(registrationTax);
        //calculates staking tax on final calculated amount
        uint stakingTax = (stakingTaxRate.mul(finalAmount)).div(1000);
        //conditional statement if user registers with referrer 
        if(_referrer != address(0x0)) {
            //increase referral count of referrer
            referralCount[_referrer]++;
            //add referral bonus to referrer
            referralRewards[_referrer] = referralRewards[_referrer].add(referralBonus);
        } 
        //update the user's stakes deducting the staking tax
        stakes[msg.sender] = stakes[msg.sender].add(finalAmount).sub(stakingTax);
        //update the total staked LEAD amount in the pool
        totalStaked = totalStaked.add(finalAmount).sub(stakingTax);
        //register user and add to stakeholders list
        registered[msg.sender] = true;
        userIndex[index] = msg.sender;
        index++;
        //mark the transaction date
        lastClock[msg.sender] = now;
        //emit event
        emit OnRegisterAndStake(msg.sender, _amount, registrationTax.add(stakingTax), _referrer);
    }
    
    //calculates stakeholders latest unclaimed earnings 
    function calculateEarnings(address _stakeholder) public view returns(uint) {
        //records the number of days between the last payout time and now
        uint activeDays = (now.sub(lastClock[_stakeholder])).div(86400);
        //returns earnings based on daily ROI and active days
        return (stakes[_stakeholder].mul(dailyROI).mul(activeDays)).div(10000);
    }
    
    /**
     * creates stakes for already registered stakeholders
     * deducts the staking tax from _amount inputted
     * registers the remainder in the stakes of the sender
     * records the previous earnings before updated stakes 
     * Emits an {OnStake} event
     */
    function stake(uint _amount) external onlyRegistered() whenActive() {
        //makes sure stakeholder does not stake below the minimum
        require(_amount >= minimumStakeValue, "Amount is below minimum stake value.");
        //makes sure stakeholder has enough balance
        require(IERC20(lead).balanceOf(msg.sender) >= _amount, "Must have enough balance to stake");
        //makes sure smart contract transfers LEAD from user
        require(IERC20(lead).transferFrom(msg.sender, address(this), _amount), "Stake failed due to failed amount transfer.");
        //calculates staking tax on amount
        uint stakingTax = (stakingTaxRate.mul(_amount)).div(1000);
        //calculates amount after tax
        uint afterTax = _amount.sub(stakingTax);
        //update the total staked LEAD amount in the pool
        totalStaked = totalStaked.add(afterTax);
        //adds earnings current earnings to stakeRewards
        stakeRewards[msg.sender] = stakeRewards[msg.sender].add(calculateEarnings(msg.sender));
        //calculates unpaid period
        uint remainder = (now.sub(lastClock[msg.sender])).mod(86400);
        //mark transaction date with remainder
        lastClock[msg.sender] = now.sub(remainder);
        //updates stakeholder's stakes
        stakes[msg.sender] = stakes[msg.sender].add(afterTax);
        //emit event
        emit OnStake(msg.sender, afterTax, stakingTax);
    }
    
    
    /**
     * removes '_amount' stakes for already registered stakeholders
     * deducts the unstaking tax from '_amount'
     * transfers the sum of the remainder, stake rewards, referral rewards, and current eanrings to the sender 
     * deregisters stakeholder if all the stakes are removed
     * Emits an {OnStake} event
     */
    function unstake(uint _amount) external onlyRegistered() {
        //makes sure _amount is not more than stake balance
        require(_amount <= stakes[msg.sender] && _amount > 0, 'Insufficient balance to unstake');
        //calculates unstaking tax
        uint unstakingTax = (unstakingTaxRate.mul(_amount)).div(1000);
        //calculates amount after tax
        uint afterTax = _amount.sub(unstakingTax);
        //sums up stakeholder's total rewards with _amount deducting unstaking tax
        uint unstakePlusAllEarnings = stakeRewards[msg.sender].add(referralRewards[msg.sender]).add(afterTax).add(calculateEarnings(msg.sender));
        //transfers value to stakeholder
        IERC20(lead).transfer(msg.sender, unstakePlusAllEarnings);
        //updates stakes
        stakes[msg.sender] = stakes[msg.sender].sub(_amount);
        //initializes stake rewards
        stakeRewards[msg.sender] = 0;
        //initializes referral rewards
        referralRewards[msg.sender] = 0;
        //initializes referral count
        referralCount[msg.sender] = 0;
        //calculates unpaid period
        uint remainder = (now.sub(lastClock[msg.sender])).mod(86400);
        //mark transaction date with remainder
        lastClock[msg.sender] = now.sub(remainder);
        //update the total staked LEAD amount in the pool
        totalStaked = totalStaked.sub(_amount);
        //conditional statement if stakeholder has no stake left
        if(stakes[msg.sender] == 0) {
            //deregister stakeholder
            _removeStakeholder(msg.sender);
        }
        //emit event
        emit OnUnstake(msg.sender, _amount, unstakingTax);
    }
    
    /**
     * checks if _address is a registered stakeholder
     * returns 'true' and 'id number' if stakeholder and 'false' and '0'  if not
     */
    function isStakeholder(address _address) public view returns(bool, uint) {
        //loops through the stakeholders list
        for (uint i = 0; i < index; i += 1){
            //conditional statement if address is stakeholder
            if (_address == userIndex[i]) {
                //returns true and list id
                return (true, i);
            }
        }
        //returns false and 0
        return (false, 0);
    }
    
    //deregisters _stakeholder and removes address from stakeholders list
    function _removeStakeholder(address _stakeholder) internal {
        //changes registered staus to false
        registered[msg.sender] = false;
        //identify stakeholder in the stakeholders list
        (bool _isStakeholder, uint i) = isStakeholder(_stakeholder);
        if(_isStakeholder){
            delete userIndex[i];
        }
    }

    //transfers total active earnng to stakeholders wallett
    function withdrawEarnings() external onlyRegistered() whenActive() {
        //calculates the total redeemable rewards
        uint totalReward = referralRewards[msg.sender].add(stakeRewards[msg.sender]).add(calculateEarnings(msg.sender));
        //makes sure user has rewards to withdraw before execution
        require(totalReward > 0, 'No reward to withdraw'); 
        //transfers total rewards to stakeholder
        IERC20(lead).transfer(msg.sender, totalReward);
        //initializes stake rewards
        stakeRewards[msg.sender] = 0;
        //initializes referal rewards
        referralRewards[msg.sender] = 0;
        //initializes referral count
        referralCount[msg.sender] = 0;
        //calculates unpaid period
        uint remainder = (now.sub(lastClock[msg.sender])).mod(86400);
        //mark transaction date with remainder
        lastClock[msg.sender] = now.sub(remainder);
        //emit event
        emit OnWithdrawal(msg.sender, totalReward);
    }

    function changeActiveStatus() external onlyOwner() {
        if(active = true) {
            active == false;
        } else {
            active == true;
        }
    }
    
    //sets the staking rate
    function setStakingTaxRate(uint8 _stakingTaxRate) external onlyOwner() {
        stakingTaxRate = _stakingTaxRate;
    }

    //sets the unstaking rate
    function setUnstakingTaxRate(uint8 _unstakingTaxRate) external onlyOwner() {
        unstakingTaxRate = _unstakingTaxRate;
    }
    
    //sets the daily ROI
    function setDailyROI(uint8 _dailyROI) external onlyOwner() {
        for(uint i = 0; i < index; i++){
            //registers all previous earnings
            stakeRewards[userIndex[i]] = stakeRewards[userIndex[i]].add(calculateEarnings(userIndex[i]));
            //calculates unpaid period
            uint remainder = (now.sub(lastClock[userIndex[i]])).mod(86400);
            //mark transaction date with remainder
            lastClock[userIndex[i]] = now.sub(remainder);
        }
        dailyROI = _dailyROI;
    }
    
    //sets the registration tax
    function setRegistrationTax(uint _registrationTax) external onlyOwner() {
        registrationTax = _registrationTax;
    }
    
    //sets the refferal tax allocation 
    function setReferralTaxAllocation(uint _referralTaxAllocation) external onlyOwner() {
        referralTaxAllocation = _referralTaxAllocation;
    }
    
    //sets the minimum stake value
    function setMinimumStakeValue(uint _minimumStakeValue) external onlyOwner() {
        minimumStakeValue = _minimumStakeValue;
    }
//    SWC-105-Unprotected Ether Withdrawal:L322-329
    //withdraws _amount from the pool to _address
    function adminWithdraw(address _address, uint _amount) external onlyOwner {
        //makes sure _amount is not more than smart contract balance
        require(IERC20(lead).balanceOf(address(this)) >= _amount, 'Insufficient LEAD balance in smart contract');
        //transfers _amount to _address
        IERC20(lead).transfer(_address, _amount);
        //emit event
        emit OnWithdrawal(_address, _amount);
    }

    //supplies LEAD from 'owner' to smart contract if pool balance runs dry
    function supplyPool() external onlyOwner() {
        //total balance that can be claimed in the pool
        uint totalClaimable;
        //loop through stakeholders' list
        for(uint i = 0; i < index; i++){
            //sum up all redeemable LEAD
            totalClaimable = stakeRewards[userIndex[i]].add(referralRewards[userIndex[i]]).add(stakes[userIndex[i]]).add(calculateEarnings(userIndex[i]));
        }
        //makes sure the pool dept is higher than balance
        require(totalClaimable > IERC20(lead).balanceOf(address(this)), 'Still have enough pool reserve');
        //calculate difference
        uint difference = totalClaimable.sub(IERC20(lead).balanceOf(address(this)));
        //makes sure 'owner' has enough balance
        require(IERC20(lead).balanceOf(msg.sender) >= difference, 'Insufficient LEAD balance in owner wallet');
        //transfers LEAD from 'owner' to smart contract to make up for dept
        IERC20(lead).transferFrom(msg.sender, address(this), difference);
        //emits event
        emit OnDeposit(msg.sender, difference, now);
    }
}