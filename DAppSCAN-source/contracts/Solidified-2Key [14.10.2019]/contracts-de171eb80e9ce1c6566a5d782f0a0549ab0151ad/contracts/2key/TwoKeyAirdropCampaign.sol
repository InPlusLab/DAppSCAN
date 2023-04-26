pragma solidity ^0.4.24;

import "./TwoKeyConversionStates.sol";
import "./interfaces/IERC20.sol";

/**
 * @notice Contract for the airdrop campaigns
 * @author Nikola Madjarevic
 * Created at 12/20/18
 */
//TODO: Inherit arc contract
contract TwoKeyAirdropCampaign is TwoKeyConversionStates {


    // Campaign is activated once the 2key fee requirement is satisfied
    bool isActivated = false;
    // Here will be static address of the economy previously deployed (ropsten version)
    address constant TWO_KEY_ECONOMY = address(0);
    // Here will be static address of the contract which stores all other addresses of singletones (proxy)
    address constant TWO_KEY_SINGLETONE_ADDRESSES = address(0);
    // This is representing the contractor (creator) of the campaign
    address contractor;
    // This is the amount of the tokens contractor is willing to spend for the airdrop campaign
    uint inventoryAmount;
    // This will be the contract ERC20 from which we will do payouts
    address erc20ContractAddress;
    // Time when campaign starts
    uint campaignStartTime;
    // Time when campaign ends
    uint campaignEndTime;
    // This is representing the total number of tokens which will be given as reward to the converter
    uint public numberOfTokensPerConverter;
    // This is representing the total amount for the referral per conversion -> defaults to numberOfTokensPerConverter
    uint referralReward;
    // Array of conversion objects
    Conversion[] conversions;
    // Number of conversions - representing at the same time conversion id
    uint numberOfConversions = 0;
    // Regarding fixed inventory and reward per conversion there is total number of conversions per campaign
    uint maxNumberOfConversions;
    // Mapping converter address to the conversion => There can be only 1 converter per conversion
    mapping(address => uint) converterToConversionId;
    // Mapping referrer address to his balance
    mapping(address => uint) referrerBalances;
    // Mapping referrer address to his total earnings (only used for the statistics)
    mapping(address => uint) referrerTotalEarnings;
    // The amount of 2key tokens fee per conversion
    uint constant CONVERSION_FEE_2KEY = 5;

    struct Conversion {
        address converter;
        uint conversionTime; //We can add this optional thing, like saving timestamp when conversion is created
        ConversionState state;
    }

    // Modifier which will prevent to do any actions if the time expired or didn't even started yet.
    modifier isOngoing {
        require(block.timestamp >= campaignStartTime && block.timestamp <= campaignEndTime);
        _;
    }

    // Modifier which will restrict to overflow number of conversions
    modifier onlyIfMaxNumberOfConversionsNotReached {
        require(numberOfConversions < maxNumberOfConversions);
        _;
    }

    // Modifier which will prevent to do any actions if the msg.sender is not the contractor
    modifier onlyContractor {
        require(msg.sender == contractor);
        _;
    }

    // Modifier which will disallow function calls if it's not activated
    modifier onlyIfActivated {
        require(isActivated == true);
        _;
    }

    constructor(
        uint _inventory,
        address _erc20ContractAddress,
        uint _campaignStartTime,
        uint _campaignEndTime,
        uint _numberOfTokensPerConverterAndReferralChain
    ) public {
        contractor = msg.sender;
        inventoryAmount = _inventory;
        erc20ContractAddress = _erc20ContractAddress;
        campaignStartTime = _campaignStartTime;
        campaignEndTime = _campaignEndTime;
        numberOfTokensPerConverter = _numberOfTokensPerConverterAndReferralChain;
        referralReward = _numberOfTokensPerConverterAndReferralChain;
        maxNumberOfConversions = inventoryAmount / (2*_numberOfTokensPerConverterAndReferralChain);
        if(inventoryAmount - maxNumberOfConversions*2*_numberOfTokensPerConverterAndReferralChain > 0 ) {
            //TODO: This is sufficient balance which can't be used, and will be returned back to the contractor
        }
    }

    /**
     * @notice Function to activate campaign
     * @dev only contractor can activate campaign
     * We're supposing that he has already sent his tokens to the contract, and also submitted (staked) 2key fee
     */
    function activateCampaign() external onlyContractor {
        uint balance = IERC20(TWO_KEY_ECONOMY).balanceOf(address(this));
        if(erc20ContractAddress == TWO_KEY_ECONOMY) {
            require(balance == numberOfConversions * CONVERSION_FEE_2KEY + inventoryAmount);
        } else {
            require(balance == numberOfConversions * CONVERSION_FEE_2KEY);
        }
        isActivated = true;
    }

    /**
     * @notice Function which will be executed to create conversion
     * @dev This function will revert if the maxNumberOfConversions is reached
     */
    function convert(bytes signature) external onlyIfActivated onlyIfMaxNumberOfConversionsNotReached {
        //TODO: Add validators, update rewards fields, parse signature, etc.
        //TODO: Get from signature if there've been any converters
        //TODO: We can't allow anyone to do the action if there's not refchain behind him
        //TODO: Add validator that converter previously doesn't exist
        Conversion memory c = Conversion({
            converter: msg.sender,
            conversionTime: block.timestamp,
            state: ConversionState.PENDING_APPROVAL
        });
        conversions.push(c);
        numberOfConversions++;
    }

    /**
     * @notice Function to approve conversion
     * @dev This function can be called only by contractor
     * @param conversionId is the id of the conversion (position in the array of conversions)
     */
    function approveConversion(uint conversionId) external onlyContractor {
        Conversion memory c = conversions[conversionId];
        if(c.state == ConversionState.PENDING_APPROVAL) {
            c.state = ConversionState.APPROVED;
        }
        conversions[conversionId] = c;
    }

    /**
     * @notice Function to reject conversion
     * @dev This function can be called only by contractor
     * @param conversionId is the id of the conversion
     */
    function rejectConversion(uint conversionId) external onlyContractor {
        Conversion memory c = conversions[conversionId];
        if(c.state == ConversionState.PENDING_APPROVAL) {
            c.state = ConversionState.REJECTED;
        }
        conversions[conversionId] = c;
    }

    /**
     * @notice Function to return dynamic and static contract data, visible to everyone
     * @return encoded data
     */
    function getContractInformations() external view returns (bytes) {
        return abi.encodePacked(
            contractor,
            inventoryAmount,
            erc20ContractAddress,
            campaignStartTime,
            campaignEndTime,
            numberOfTokensPerConverter,
            numberOfConversions,
            maxNumberOfConversions
        );
    }

    /**
     * @notice Function returns the total available balance of the referrer and his total earnings for this campaign
     * @dev only referrer by himself or contractor can see the balance of the referrer
     * @param _referrer is the address of the referrer we're checking balance for
     */
    function getReferrerBalanceAndTotalEarnings(address _referrer) external view returns (uint,uint) {
        require(msg.sender == contractor || msg.sender == _referrer);
        return (referrerBalances[_referrer], referrerTotalEarnings[_referrer]);
    }

    /**
     * @notice Function to get conversion object
     * @param conversionId is the id of the conversion
     * @return tuple containing respectively converter address, conversionTime, and state of the conversion
     */
    function getConversion(uint conversionId) external view returns (address, uint, bytes32) {
        Conversion memory conversion = conversions[conversionId];
        require(msg.sender == conversion.converter || msg.sender == contractor);
        return (conversion.converter, conversion.conversionTime, convertConversionStateToBytes(conversion.state));
    }

    /**
     * @notice Function to determine the balance of converter
     * @dev Only converter by himself or contractor can see balance for the converter
     * @param _converter address is the only argument we need
     */
    function getConverterBalance(address _converter) external view returns (uint) {
        require(msg.sender == _converter || msg.sender == contractor);
        uint conversionId = converterToConversionId[_converter];
        Conversion memory conversion = conversions[conversionId];
        if(conversion.state == ConversionState.APPROVED) {
            return numberOfTokensPerConverter;
        } else {
            return 0;
        }
    }

    /**
     * @notice Once the conversion is approved, means that converter has done the required action and he can withdraw tokens
     */
    function converterWithdraw() external {
        uint conversionId = converterToConversionId[msg.sender];
        Conversion memory c = conversions[conversionId];
        require(c.state == ConversionState.APPROVED);
        c.state = ConversionState.EXECUTED;
        IERC20(erc20ContractAddress).transfer(msg.sender, numberOfTokensPerConverter); //this is going to be an erc20 transfer
        conversions[conversionId] = c;
    }

    /**
     * @notice Function to withdraw erc20 tokens for the referrer
     * @dev if referrer doesn't have any balance this will revert
     */
    function referrerWithdraw() external {
        require(referrerBalances[msg.sender] > 0);
        IERC20(erc20ContractAddress).transfer(msg.sender, referrerBalances[msg.sender]);
        referrerBalances[msg.sender] = 0;
    }


    function convertConversionStateToBytes(ConversionState state) internal pure returns (bytes32) {
        if(state == ConversionState.PENDING_APPROVAL) {
            return bytes32("PENDING_APPROVAL");
        } else if(state == ConversionState.APPROVED) {
            return bytes32("APPROVED");
        } else if(state == ConversionState.EXECUTED) {
            return bytes32("EXECUTED");
        } else if(state == ConversionState.REJECTED) {
            return bytes32("REJECTED");
        } else if(state == ConversionState.CANCELLED_BY_CONVERTER) {
            return bytes32("CANCELLED_BY_CONVERTER");
        } else {
            return bytes32(0);
        }
    }
}
