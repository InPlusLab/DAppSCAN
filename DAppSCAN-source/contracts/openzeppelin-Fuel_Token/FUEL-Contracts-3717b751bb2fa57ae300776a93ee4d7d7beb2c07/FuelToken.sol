pragma solidity ^0.4.15;

import "zeppelin-solidity/contracts/math/SafeMath.sol";
import 'zeppelin-solidity/contracts/ownership/Ownable.sol';
import 'zeppelin-solidity/contracts/token/ERC20.sol';
import "./helpers/NonZero.sol";


contract FuelToken is ERC20, Ownable, NonZero {

    using SafeMath for uint;

/////////////////////// TOKEN INFORMATION ///////////////////////
    string public constant name = "Fuel Token";
    string public constant symbol = "FUEL";

    uint8 public decimals = 18;
    
    // Mapping to keep user's balances
    mapping (address => uint256) balances;
    // Mapping to keep user's allowances
    mapping (address => mapping (address => uint256)) allowed;

/////////////////////// VARIABLE INITIALIZATION ///////////////////////
    
    // Total FUEL allocated at a given time
    uint256 public totalAllocatedTokens;
    // Allocation for the Vanbex Team
    uint256 public vanbexTeamSupply;
    // Etherparty platform supply
    uint256 public platformSupply;
    // Total amount of Public FUEL that will be allocated
    uint256 public amountOfPublicTokensToAllocate;
    // Amount of FUEL for the presale
    uint256 public presaleSupply;
    // Amount of presale tokens remaining at a given time
    uint256 public presaleAmountRemaining;
    // Total ICO supply
    uint256 public icoSupply;
    // Community incentivisation supply
    uint256 public incentivisingEffortsSupply;
    // Crowdsale End Timestamp
    uint256 public crowdfundEndsAt;
    // Vesting period for the Vanbex Team allocation
    uint256 public vanbexTeamVestingPeriod;

    // Crowdfund Address
    address public crowdfundAddress;
    // Vanbex team address
    address public vanbexTeamAddress;
    // Etherparty platform address
    address public platformAddress;
    // Community incentivisation address
    address public incentivisingEffortsAddress;
    // Etherparty Address
    address public etherpartyAddress;

    // Flag keeping track of presale status. Ensures functions can only be called once
    bool public presaleFinalized = false;
    // Flag keeping track of crowdsale status. Ensures functions can only be called once
    bool public crowdfundFinalized = false;

/////////////////////// EVENTS ///////////////////////

    // Event called when crowdfund is done
    event CrowdfundFinalized(uint tokens);
    // Event called when presale is done
    event PresaleFinalized(uint tokens);

/////////////////////// MODIFIERS ///////////////////////

    // Ensure actions can only happen after crowdfund ends
    modifier notBeforeCrowdfundEnds(){
        require(now >= crowdfundEndsAt);
        _;
    }

    // Ensure vesting period is over
    modifier checkVanbexTeamVestingPeriod() {
        assert(now >= vanbexTeamVestingPeriod);
        _;
    }

    // Ensure only crowdfund can call the function
    modifier onlyCrowdfund() {
        require(msg.sender == crowdfundAddress);
        _;
    }

/////////////////////// ERC20 FUNCTIONS ///////////////////////

    // Transfer
    function transfer(address _to, uint256 _amount) notBeforeCrowdfundEnds nonZeroAmount(_amount) returns (bool success) {
        require(balanceOf(msg.sender) >= _amount);
        addToBalance(_to, _amount);
        decrementBalance(msg.sender, _amount);
        Transfer(msg.sender, _to, _amount);
        return true;
    }

    // Transfer from one address to another (need allowance to be called first)
    function transferFrom(address _from, address _to, uint256 _amount) notBeforeCrowdfundEnds nonZeroAmount(_amount) returns (bool success) {
        require(allowance(_from, msg.sender) >= _amount);
        addToBalance(_to, _amount);
        decrementBalance(_from, _amount);
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_amount);
        Transfer(_from, _to, _amount);
        return true;
    }

    // Approve another address a certain amount of FUEL
    function approve(address _spender, uint256 _value) returns (bool success) {
        require((_value == 0) || (allowance(msg.sender, _spender) == 0));
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    // Get an address's FUEL allowance
    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
        return allowed[_owner][_spender];
    }

    // Get the FUEL balance of any address
    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

/////////////////////// TOKEN FUNCTIONS ///////////////////////

    // Constructor
    function FuelToken() {
        crowdfundEndsAt = 1507852800;                                               // Oct 13, 00:00:00 UTC  - 1507852800
        vanbexTeamVestingPeriod = crowdfundEndsAt.add(183 * 1 days);                // 6 months vesting period

        totalSupply = 1 * 10**27;                                                   // 100% - 1 billion total FUEL tokens with 18 decimals
        vanbexTeamSupply = 5 * 10**25;                                              // 5% - 50 million for etherparty team
        platformSupply = 5 * 10**25;                                                // 5% - 50 million to be sold on the etherparty platform in-app
        incentivisingEffortsSupply = 1 * 10**26;                                    // 10% - 100 million for incentivising efforts
        presaleSupply = 54 * 10**25;                                                // 540,000,000 fuel tokens available for presale with overflow for bonus included
        icoSupply = 26 * 10**25;                                                    // 260 million fuel tokens for ico with potential for extra after finalizing presale
       
        amountOfPublicTokensToAllocate = presaleSupply + icoSupply;                 // Total amount of tokens available to the public
        presaleAmountRemaining = presaleSupply;                                     // Decreased over the course of the pre-sale
        vanbexTeamAddress = 0x413ea1484137526f3b1bd412e2f897c94c8e198d;             // Vanbex Team Address
        platformAddress = 0xa1602060f4630ef560009a3377a6b788d2b90484;               // Platform Address
        incentivisingEffortsAddress = 0xc82fe29c67e63df7a09902140c5354fd6279c86c;   // Community incentivisation address

        addToBalance(incentivisingEffortsAddress, incentivisingEffortsSupply);     
        addToBalance(platformAddress, platformSupply);                              

        allocateTokens(incentivisingEffortsSupply);
        allocateTokens(platformSupply);
    }

    // Sets the crowdfund address, can only be done once
    function setCrowdfundAddress(address _crowdfundAddress) external onlyOwner nonZeroAddress(_crowdfundAddress) {
        require(crowdfundAddress == 0x0);
        crowdfundAddress = _crowdfundAddress;
        addToBalance(crowdfundAddress, icoSupply); 
    }

    // Sets the Etherparty address
    function setEtherpartyAddress(address _etherpartyAddress) external onlyOwner nonZeroAddress(_etherpartyAddress) {
        etherpartyAddress = _etherpartyAddress;  
    }

    // Function for the Crowdfund to transfer tokens
    function transferFromCrowdfund(address _to, uint256 _amount) onlyCrowdfund nonZeroAmount(_amount) nonZeroAddress(_to) returns (bool success) {
        require(balanceOf(crowdfundAddress) >= _amount);
        decrementBalance(crowdfundAddress, _amount);
        addToBalance(_to, _amount);
        allocateTokens(_amount);
        Transfer(crowdfundAddress, _to, _amount);
        return true;
    }

    // Release Vanbex team supply after vesting period is finished.
    function releaseVanbexTeamTokens() checkVanbexTeamVestingPeriod onlyOwner returns(bool success) {
        require(vanbexTeamSupply > 0);
        addToBalance(vanbexTeamAddress, vanbexTeamSupply);
        Transfer(this, vanbexTeamAddress, vanbexTeamSupply);
        allocateTokens(vanbexTeamSupply);
        vanbexTeamSupply = 0;
        return true;
    }
//SWC-114-Transaction Order Dependence:L189
    // Finalize presale. If there are leftover FUEL, let them overflow to the crowdfund
    function finalizePresale() external onlyOwner returns (bool success) {
        require(presaleFinalized == false);
        uint256 amount = presaleAmountRemaining;
        if (amount != 0) {
            presaleAmountRemaining = 0;
            addToBalance(crowdfundAddress, amount);
        }
        presaleFinalized = true;
        PresaleFinalized(amount);
        return true;
    }

    // Finalize crowdfund. If there are leftover FUEL, let them overflow to the be sold at 1$ on the platform
    function finalizeCrowdfund() external onlyCrowdfund notBeforeCrowdfundEnds returns (bool success) {
        require(crowdfundFinalized == false);
        uint256 amount = balanceOf(crowdfundAddress);
        if (amount > 0) {
            balances[crowdfundAddress] = 0;
            addToBalance(platformAddress, amount);
            Transfer(crowdfundAddress, platformAddress, amount);
        }
        crowdfundFinalized = true;
        CrowdfundFinalized(amount);
        return true;
    }


    // Function to send FUEL to presale investors
    function deliverPresaleFuelBalances(address[] _batchOfAddresses, uint[] _amountOfFuel) external onlyOwner returns (bool success) {
        for (uint256 i = 0; i < _batchOfAddresses.length; i++) {
            deliverPresaleFuelBalance(_batchOfAddresses[i], _amountOfFuel[i]);            
        }
        return true;
    }

    // All presale purchases will be delivered. If one address has contributed more than once,
    // his contribution will be aggregated
    function deliverPresaleFuelBalance(address _accountHolder, uint _amountOfBoughtFuel) internal onlyOwner {
        require(balanceOf(_accountHolder) == 0 && presaleAmountRemaining > 0); 
        addToBalance(_accountHolder, _amountOfBoughtFuel);
        Transfer(this, _accountHolder, _amountOfBoughtFuel);
        presaleAmountRemaining = presaleAmountRemaining.sub(_amountOfBoughtFuel);
        allocateTokens(_amountOfBoughtFuel);        
    }

    // Add to balance
    function addToBalance(address _address, uint _amount) internal {
    	balances[_address] = balances[_address].add(_amount);
    }

    // Remove from balance
    function decrementBalance(address _address, uint _amount) internal {
    	balances[_address] = balances[_address].sub(_amount);
    }

    // Add to totalAllocatedTokens
    function allocateTokens(uint _amount) internal {
    	totalAllocatedTokens = totalAllocatedTokens.add(_amount);
    }

    // Reject any value transfer to this contract
    function () {
        revert();
    }
}
