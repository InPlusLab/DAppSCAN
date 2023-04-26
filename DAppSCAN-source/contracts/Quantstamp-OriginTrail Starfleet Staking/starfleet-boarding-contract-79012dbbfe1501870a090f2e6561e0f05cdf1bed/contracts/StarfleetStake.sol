pragma solidity 0.6.10;

import "openzeppelin-solidity/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./mocks/IBridgeCustodian.sol";

contract StarfleetStake is Ownable {

    using SafeMath for uint256;
    IERC20 token;

    address public constant TRAC_TOKEN_ADDRESS = 0xaA7a9CA87d3694B5755f213B5D04094b8d0F0A6F;

    // minimum number of tokens for successful onboarding
    uint256 public constant MIN_THRESHOLD = 2e25;

    // maximum number of tokens allowed to be onboarded
    uint256 public constant MAX_THRESHOLD = 10e25;

    // Time periods

    // Official start time of the staking period
    uint256 public t_zero;
    uint256 public constant BOARDING_PERIOD_LENGTH = 30 days;
    uint256 public constant LOCK_PERIOD_LENGTH = 180 days;
    uint256 public constant BRIDGE_PERIOD_LENGTH = 180 days;
    uint256 public boarding_period_end;
    uint256 public lock_period_end;
    uint256 public bridge_period_end;
    bool public min_threshold_reached = false;

    // list of participants
    address[] internal participants;

    // participant stakes
    mapping(address => uint256) internal stake;
    mapping(address => uint256) internal participant_indexes;

    // for feature O1
    mapping(address => uint256) internal starTRAC_snapshot;

    event TokenStaked(address indexed staker, uint256 amount);
    event TokenWithdrawn(address indexed staker, uint256 amount);
    event TokenFallbackWithdrawn(address indexed staker, uint256 amount);
    event TokenTransferred(address indexed custodian, uint256 amount);
    event MinThresholdReached();

    constructor(uint256 start_time,address token_address)  public {

        if(start_time > now){
            t_zero = start_time;
        }else{
            t_zero = now;
        }

        boarding_period_end = t_zero.add(BOARDING_PERIOD_LENGTH);
        lock_period_end = t_zero.add(BOARDING_PERIOD_LENGTH).add(LOCK_PERIOD_LENGTH);
        bridge_period_end = t_zero.add(BOARDING_PERIOD_LENGTH).add(LOCK_PERIOD_LENGTH).add(BRIDGE_PERIOD_LENGTH);
        if (token_address!=address(0x0)){
            // for testing purposes
            token = IERC20(token_address);
        }else{
            // default use TRAC
            token = IERC20(TRAC_TOKEN_ADDRESS);
        }

    }

    // Override Ownable renounceOwnership function
    function renounceOwnership() public override onlyOwner {
        require(false, "Cannot renounce ownership of contract");
    }

    // Functional requirement FR1
    function depositTokens(uint256 amount) public {

        require(amount>0, "Amount cannot be zero");
        require(now >= t_zero, "Cannot deposit before staking starts");
        require(now < t_zero.add(BOARDING_PERIOD_LENGTH), "Cannot deposit after boarding period has expired");
        require(token.balanceOf(address(this)).add(amount) <= MAX_THRESHOLD, "Sender cannot deposit amounts that would cross the MAX_THRESHOLD");
        require(token.allowance(msg.sender, address(this)) >= amount, "Sender allowance must be equal to or higher than chosen amount");
        require(token.balanceOf(msg.sender) >= amount, "Sender balance must be equal to or higher than chosen amount!");

        bool transaction_result = token.transferFrom(msg.sender, address(this), amount);
        require(transaction_result, "Token transaction execution failed!");

        if (stake[msg.sender] == 0){
            participant_indexes[msg.sender] = participants.length;
            participants.push(msg.sender);
        }

        stake[msg.sender] = stake[msg.sender].add(amount);

        if ( token.balanceOf(address(this)) >= MIN_THRESHOLD && min_threshold_reached == false){
            min_threshold_reached = true;
            emit MinThresholdReached();
        }

        emit TokenStaked(msg.sender, amount);

    }

    function getStake(address participant) public view returns(uint256){
        return stake[participant];
    }

    function getNumberOfParticipants() public view returns(uint256){
        return participants.length;
    }

    function getParticipants() public view returns(address[] memory){
        return participants;
    }

    function isMinimumReached() public view returns(bool){
        return min_threshold_reached;
    }

    // Functional requirement FR2
    function withdrawTokens() public {

        require(!min_threshold_reached, "Cannot withdraw if minimum threshold has been reached");
        require(stake[msg.sender] > 0,"Cannot withdraw if there are no tokens staked with this address");
        uint256 amount = stake[msg.sender];
        stake[msg.sender] = 0;

        uint256 participant_index = participant_indexes[msg.sender];
        require(participant_index < participants.length, "Sender is not listed in participant list");
        if (participant_index != participants.length.sub(1)) {
            address last_participant = participants[participants.length.sub(1)];
            participants[participant_index] = last_participant;
            participant_indexes[last_participant] = participant_index;
        }
        participants.pop();

        bool transaction_result = token.transfer(msg.sender, amount);
        require(transaction_result, "Token transaction execution failed!");
        emit TokenWithdrawn(msg.sender, amount);


    }

    // Functional requirement FR6
    function fallbackWithdrawTokens() public {

        require(now > bridge_period_end, "Cannot use fallbackWithdrawTokens before end of bridge period");
        require(starTRAC_snapshot[msg.sender] > 0, "Cannot withdraw as this address has no starTRAC associated");
        uint256 amount = starTRAC_snapshot[msg.sender];
        starTRAC_snapshot[msg.sender] = 0;
        bool transaction_result = token.transfer(msg.sender, amount);
        require(transaction_result, "Token transaction execution failed!");
        emit TokenFallbackWithdrawn(msg.sender, amount);


    }

    // Functional requirement FR5
    function accountStarTRAC(address[] memory contributors, uint256[] memory amounts) onlyOwner public {
        require(now > bridge_period_end, "Cannot account starTRAC tokens before end of bridge period");
        require(contributors.length == amounts.length, "Wrong input - contributors and amounts have different lenghts");
        for (uint i = 0; i < contributors.length; i++) {
            starTRAC_snapshot[contributors[i]] = amounts[i];
        }

    }

    function getStarTRACamount(address contributor) public view returns(uint256){
        return starTRAC_snapshot[contributor];
    }


    // Functional requirement FR4
    function transferTokens(address payable custodian) onlyOwner public {

        require(custodian != address(0x0), "Custodian cannot be a zero address");
        uint contract_size;
        assembly { contract_size := extcodesize(custodian) }
        require(contract_size > 0, "Cannot transfer tokens to custodian that is not a contract!");

        IBridgeCustodian custodian_contract = IBridgeCustodian(custodian);
        bool has_owners_function = false;
        try custodian_contract.getOwners() returns (address[] memory owners) {
            has_owners_function = true;
            require(owners.length > 0, "Cannot transfer tokens to custodian without owners defined!");
        } catch {}
        require(has_owners_function, "Cannot transfer tokens to custodian without getOwners function!");
        require(now >= lock_period_end && now < bridge_period_end, "Cannot transfer tokens outside of the bridge period");

        uint256 balance_transferred= token.balanceOf(address(this));
        bool transaction_result = token.transfer(custodian, balance_transferred);
        require(transaction_result, "Token transaction execution failed!");

        emit TokenTransferred(custodian, balance_transferred);
    }

    function withdrawMisplacedEther() onlyOwner public {
        uint256 balance = address(this).balance;
        if (balance > 0) {
            msg.sender.transfer(balance);
        }
    }

    function withdrawMisplacedTokens(address token_contract_address) onlyOwner public {
        require(token_contract_address != address(token), "Cannot use this function with the TRAC contract");
        IERC20 token_contract = IERC20(token_contract_address);

        uint256 balance = token_contract.balanceOf(address(this));
        if (balance > 0) {
            bool transaction_result = token_contract.transfer(msg.sender, balance);
            require(transaction_result, "Token transaction execution failed");
        }
    }

}
