pragma solidity ^0.4.24;

import "../TwoKeyConversionStates.sol";
import "../TwoKeyConverterStates.sol";

import "../interfaces/ITwoKeyAcquisitionCampaignERC20.sol";
import "../interfaces/ITwoKeyEventSource.sol";
import "../interfaces/ITwoKeyBaseReputationRegistry.sol";
import "../interfaces/ITwoKeyPurchasesHandler.sol";
import "../libraries/SafeMath.sol";
import "../upgradable-pattern-campaigns/UpgradeableCampaign.sol";

/**
 * @notice Contract to handle logic related for Acquisition
 * @dev There will be 1 conversion handler per Acquisition Campaign
 * @author Nikola Madjarevic
 */
contract TwoKeyConversionHandler is UpgradeableCampaign, TwoKeyConversionStates, TwoKeyConverterStates {

    using SafeMath for uint256;

    bool isCampaignInitialized;

    bool public isFiatConversionAutomaticallyApproved;

    event ConversionCreated(uint conversionId);
    uint numberOfConversions;

    Conversion[] conversions;
    ITwoKeyAcquisitionCampaignERC20 twoKeyAcquisitionCampaignERC20;

    mapping(address => uint256) private amountConverterSpentFiatWei; // Amount converter spent for Fiat conversions
    mapping(address => uint256) private amountConverterSpentEthWEI; // Amount converter put to the contract in Ether
    mapping(address => uint256) private unitsConverterBought; // Number of units (ERC20 tokens) bought


    mapping(bytes32 => address[]) stateToConverter; //State to all converters in that state
    mapping(address => uint[]) converterToHisConversions;

    mapping(address => ConverterState) converterToState; //Converter to his state
    mapping(address => bool) isConverterAnonymous;
    mapping(address => bool) doesConverterHaveExecutedConversions;
    /**
     * This array will represent counter values where position will be index (which counter) and value will be actual counter value
     * counters[0] = PENDING_CONVERSIONS
     * counters[1] = APPROVED_CONVERSIONS
     * counters[2] = REJECTED_CONVERSIONS
     * counters[3] = EXECUTED_CONVERSIONS
     * counters[4] = CANCELLED_CONVERSIONS
     * counters[5] = UNIQUE_CONVERTERS
     * counters[6] = RAISED_FUNDS_ETH_WEI
     * counters[7] = TOKENS_SOLD
     * counters[8] = TOTAL_BOUNTY
     * counters[9] = RAISED_FUNDS_FIAT_WEI
     */
    uint [] counters;

    uint expiryConversionInHours; // How long converter can be pending before it will be automatically rejected and funds will be returned to convertor (hours)

    address twoKeyEventSource;
    address contractor;
    address assetContractERC20;
    address twoKeyBaseReputationRegistry;
    address public twoKeyPurchasesHandler;


    /// Structure which will represent conversion
    struct Conversion {
        address contractor; // Contractor (creator) of campaign
        uint256 contractorProceedsETHWei; // How much contractor will receive for this conversion
        address converter; // Converter is one who's buying tokens -> plasma address
        ConversionState state;
        uint256 conversionAmount; // Amount for conversion (In ETH / FIAT)
        uint256 maxReferralRewardETHWei; // Total referral reward for the conversion
        uint256 maxReferralReward2key;
        uint256 moderatorFeeETHWei;
        uint256 baseTokenUnits;
        uint256 bonusTokenUnits;
        uint256 conversionCreatedAt; // When conversion is created
        uint256 conversionExpiresAt; // When conversion expires
        bool isConversionFiat;
    }

    modifier onlyContractorOrMaintainer {
        require(msg.sender == contractor || ITwoKeyEventSource(twoKeyEventSource).isAddressMaintainer(msg.sender));
        _;
    }


    function setInitialParamsConversionHandler(
        uint [] values,
        address _twoKeyAcquisitionCampaignERC20,
        address _twoKeyPurchasesHandler,
        address _contractor,
        address _assetContractERC20,
        address _twoKeyEventSource,
        address _twoKeyBaseReputationRegistry
    )
    public
    {
        require(isCampaignInitialized == false);
        counters = new uint[](10);

        expiryConversionInHours = values[0];

        if(values[1] == 1) {
            isFiatConversionAutomaticallyApproved = true;
        }

        // Instance of interface
        twoKeyPurchasesHandler = _twoKeyPurchasesHandler;
        twoKeyAcquisitionCampaignERC20 = ITwoKeyAcquisitionCampaignERC20(_twoKeyAcquisitionCampaignERC20);

        contractor = _contractor;
        assetContractERC20 =_assetContractERC20;
        twoKeyEventSource = _twoKeyEventSource;
        twoKeyBaseReputationRegistry = _twoKeyBaseReputationRegistry;
        isCampaignInitialized = true;
    }

    /**
     * given the total payout, calculates the moderator fee
     * @param  _conversionAmountETHWei total payout for escrow
     * @return moderator fee
     */
    function calculateModeratorFee(
        uint256 _conversionAmountETHWei
    )
    private
    view
    returns (uint256)
    {
        uint256 fee = _conversionAmountETHWei.mul(ITwoKeyEventSource(twoKeyEventSource).getTwoKeyDefaultIntegratorFeeFromAdmin()).div(100);
        return fee;
    }


    /// @notice Support function to create conversion
    /// @dev This function can only be called from TwoKeyAcquisitionCampaign contract address
    /// @param _contractor is the address of campaign contractor
    /// @param _converterAddress is the address of the converter
    /// @param _conversionAmount is the amount for conversion in ETH
    function supportForCreateConversion(
        address _contractor,
        address _converterAddress,
        uint256 _conversionAmount,
        uint256 _maxReferralRewardETHWei,
        uint256 baseTokensForConverterUnits,
        uint256 bonusTokensForConverterUnits,
        bool isConversionFiat,
        bool _isAnonymous,
        bool _isKYCRequired
    )
    public
    returns (uint)
    {
        require(msg.sender == address(twoKeyAcquisitionCampaignERC20));

        //If KYC is required, basic funnel executes and we require that converter is not previously rejected
        if(_isKYCRequired == true) {
            require(converterToState[_converterAddress] != ConverterState.REJECTED); // If converter is rejected then can't create conversion
            // Checking the state for converter, if this is his 1st time, he goes initially to PENDING_APPROVAL
            if(converterToState[_converterAddress] == ConverterState.NOT_EXISTING) {
                converterToState[_converterAddress] = ConverterState.PENDING_APPROVAL;
                stateToConverter[bytes32("PENDING_APPROVAL")].push(_converterAddress);
            }
        } else {
            //If KYC is not required converter is automatically approved
            if(converterToState[_converterAddress] == ConverterState.NOT_EXISTING) {
                converterToState[_converterAddress] = ConverterState.APPROVED;
                stateToConverter[bytes32("APPROVED")].push(_converterAddress);
            }
        }

        // Set if converter want to be anonymous
        isConverterAnonymous[_converterAddress] = _isAnonymous;


        uint _moderatorFeeETHWei = 0;
        uint256 _contractorProceeds = _conversionAmount; //In case of fiat conversion, this is going to be fiat value

        ConversionState state;

        if(isConversionFiat == false) {
            _moderatorFeeETHWei = calculateModeratorFee(_conversionAmount);
            _contractorProceeds = _conversionAmount - _maxReferralRewardETHWei - _moderatorFeeETHWei;
            //TODO: Add accounting for fiat proceeds
            state = ConversionState.APPROVED; // All eth conversions are auto approved
            counters[1]++;
        } else {
            //This means fiat conversion is automatically approved
            if(isFiatConversionAutomaticallyApproved) {
                state = ConversionState.APPROVED;
                counters[1] ++; // Increase the number of approved conversions
            } else {
                state = ConversionState.PENDING_APPROVAL; // Fiat conversion state is PENDING_APPROVAL
                counters[0]++; // If conversion is FIAT it will be always first pending and will have to be approved
            }
        }

        Conversion memory c = Conversion(_contractor, _contractorProceeds, _converterAddress,
            state ,_conversionAmount, _maxReferralRewardETHWei, 0, _moderatorFeeETHWei, baseTokensForConverterUnits,
            bonusTokensForConverterUnits,
            now, now + expiryConversionInHours * (1 hours), isConversionFiat);

        conversions.push(c);

        converterToHisConversions[_converterAddress].push(numberOfConversions);
        emit ConversionCreated(numberOfConversions);
        numberOfConversions++;

        return numberOfConversions-1;
    }


    /**
     * @notice Function to perform all the logic which has to be done when we're performing conversion
     * @param _conversionId is the id
     */
    function executeConversion(
        uint _conversionId
    )
    public
    {
        Conversion conversion = conversions[_conversionId];

        uint totalUnits = conversion.baseTokenUnits + conversion.bonusTokenUnits;

        // Converter must be approved in all cases
        require(converterToState[conversion.converter] == ConverterState.APPROVED);

        if(conversion.isConversionFiat == true) {
            if(isFiatConversionAutomaticallyApproved) {
                counters[1] --; // Decrease number of approved conversions
            } else {
                require(conversion.state == ConversionState.PENDING_APPROVAL);
                require(msg.sender == contractor); // first check who calls this in order to save gas
                uint availableTokens = twoKeyAcquisitionCampaignERC20.getAvailableAndNonReservedTokensAmount();
                require(totalUnits < availableTokens);
                counters[0]--; //Decrease number of pending conversions
            }

            //Update raised funds FIAT once the conversion is executed
            counters[9] = counters[9].add(conversion.conversionAmount);

            //Update amount converter spent in FIAT
            amountConverterSpentFiatWei[conversion.converter] = amountConverterSpentFiatWei[conversion.converter].add(conversion.conversionAmount);
        } else {
            require(conversion.state == ConversionState.APPROVED);
            amountConverterSpentEthWEI[conversion.converter] = amountConverterSpentEthWEI[conversion.converter].add(conversion.conversionAmount);
            counters[1]--; //Decrease number of approved conversions
        }
        //Update bought units
        unitsConverterBought[conversion.converter] = unitsConverterBought[conversion.converter].add(conversion.baseTokenUnits + conversion.bonusTokenUnits);

        // Total rewards for referrers
        uint totalReward2keys = 0;

        // Buy tokens from campaign and distribute rewards between referrers
        totalReward2keys = twoKeyAcquisitionCampaignERC20.buyTokensAndDistributeReferrerRewards(
            conversion.maxReferralRewardETHWei,
            conversion.converter,
            _conversionId,
            conversion.isConversionFiat
        );

//         Update reputation points in registry for conversion executed event
        ITwoKeyBaseReputationRegistry(twoKeyBaseReputationRegistry).updateOnConversionExecutedEvent(
            conversion.converter,
            contractor,
            twoKeyAcquisitionCampaignERC20
        );
//
        // Add total rewards
        counters[8] = counters[8].add(totalReward2keys);

        // update reserved amount of tokens on acquisition contract
        twoKeyAcquisitionCampaignERC20.updateReservedAmountOfTokensIfConversionRejectedOrExecuted(totalUnits);

        //Update total raised funds
        if(conversion.isConversionFiat == false) {
            // update moderator balances
            twoKeyAcquisitionCampaignERC20.buyTokensForModeratorRewards(conversion.moderatorFeeETHWei);
            // update contractor proceeds
            twoKeyAcquisitionCampaignERC20.updateContractorProceeds(conversion.contractorProceedsETHWei);
            // add conversion amount to counter
            counters[6] = counters[6].add(conversion.conversionAmount);
        }

        if(doesConverterHaveExecutedConversions[conversion.converter] == false) {
            counters[5]++; //increase number of unique converters
            doesConverterHaveExecutedConversions[conversion.converter] = true;
        }

        ITwoKeyPurchasesHandler(twoKeyPurchasesHandler).startVesting(
            conversion.baseTokenUnits,
            conversion.bonusTokenUnits,
            _conversionId,
            conversion.converter
        );

        // Transfer tokens to lockup contract
        twoKeyAcquisitionCampaignERC20.moveFungibleAsset(address(twoKeyPurchasesHandler), totalUnits);

        conversion.maxReferralReward2key = totalReward2keys;
        conversion.state = ConversionState.EXECUTED;
        counters[3]++; //Increase number of executed conversions
        counters[7] = counters[7].add(totalUnits); //update sold tokens once conversion is executed
    }


    /**
     * @notice Function to get conversion details by id
     * @param conversionId is the id of conversion
     */
    function getConversion(
        uint conversionId
    )
    external
    view
    returns (bytes)
    {
        Conversion memory conversion = conversions[conversionId];
        address empty = address(0);
        if(isConverterAnonymous[conversion.converter] == false) {
            empty = conversion.converter;
        }
        return abi.encodePacked (
            conversion.contractor,
            conversion.contractorProceedsETHWei,
            empty,
            conversion.state,
            conversion.conversionAmount,
            conversion.maxReferralRewardETHWei,
            conversion.maxReferralReward2key,
            conversion.moderatorFeeETHWei,
            conversion.baseTokenUnits,
            conversion.bonusTokenUnits,
            conversion.conversionCreatedAt,
            conversion.conversionExpiresAt,
            conversion.isConversionFiat
        );
    }


    function getAllConvertersPerState(
        bytes32 state
    )
    public
    view
    onlyContractorOrMaintainer
    returns (address[])
    {
        return stateToConverter[state];
    }


    /// @notice Function to move converter address from stateA to stateB
    /// @param _converter is the address of converter
    /// @param destinationState is the state we'd like to move converter to
    function moveFromStateAToStateB(
        address _converter,
        bytes32 destinationState
    )
    internal
    {
        ConverterState state = converterToState[_converter];
        bytes32 key = convertConverterStateToBytes(state);
        address[] memory pending = stateToConverter[key];
        for(uint i=0; i< pending.length; i++) {
            if(pending[i] == _converter) {
                stateToConverter[destinationState].push(_converter);
                pending[i] = pending[pending.length-1];
                delete pending[pending.length-1];
                stateToConverter[key] = pending;
                stateToConverter[key].length--;
                break;
            }
        }
    }


    /// @notice Function where we can change state of converter to Approved
    /// @dev Converter can only be approved if his previous state is pending or rejected
    /// @param _converter is the address of converter
    function moveFromPendingOrRejectedToApprovedState(
        address _converter
    )
    internal
    {
        bytes32 destination = bytes32("APPROVED");
        moveFromStateAToStateB(_converter, destination);
        converterToState[_converter] = ConverterState.APPROVED;
    }


    /// @notice Function where we're going to move state of conversion from pending to rejected
    /// @dev private function, will be executed in another one
    /// @param _converter is the address of converter
    function moveFromPendingToRejectedState(
        address _converter
    )
    internal
    {
        bytes32 destination = bytes32("REJECTED");
        moveFromStateAToStateB(_converter, destination);
        converterToState[_converter] = ConverterState.REJECTED;
    }


    /// @notice Function where we are approving converter
    /// @dev only maintainer or contractor can call this method
    /// @param _converter is the address of converter
    function approveConverter(
        address _converter
    )
    public
    onlyContractorOrMaintainer
    {
        require(converterToState[_converter] == ConverterState.PENDING_APPROVAL);
        uint len = converterToHisConversions[_converter].length;
        for(uint i=0; i<len; i++) {
            uint conversionId = converterToHisConversions[_converter][i];
            Conversion c = conversions[conversionId];
            if(c.state == ConversionState.PENDING_APPROVAL && c.isConversionFiat == true) {
                //TODO: Here should be APPROVED if it is not fiat
                counters[0]--; //Reduce number of pending conversions
                counters[1]++; //Increase number of approved conversions
                c.state = ConversionState.APPROVED;
//                conversions[conversionId] = c;
            }
        }
        moveFromPendingOrRejectedToApprovedState(_converter);
    }


    /// @notice Function where we can reject converter
    /// @dev only maintainer or contractor can call this function
    /// @param _converter is the address of converter
    function rejectConverter(
        address _converter
    )
    public
    onlyContractorOrMaintainer
    {
        require(converterToState[_converter] == ConverterState.PENDING_APPROVAL);
        moveFromPendingToRejectedState(_converter);
        uint reservedAmount = 0;
        uint refundAmount = 0;
        uint len = converterToHisConversions[_converter].length;
        for(uint i=0; i< len; i++) {
            uint conversionId = converterToHisConversions[_converter][i];
            Conversion c = conversions[conversionId];
            if(c.state == ConversionState.PENDING_APPROVAL || c.state == ConversionState.APPROVED) {
                counters[0]--; //Reduce number of pending conversions
                counters[2]++; //Increase number of rejected conversions
                ITwoKeyBaseReputationRegistry(twoKeyBaseReputationRegistry).updateOnConversionRejectedEvent(_converter, contractor, twoKeyAcquisitionCampaignERC20);
                c.state = ConversionState.REJECTED;
                reservedAmount += c.baseTokenUnits + c.bonusTokenUnits;
                if(c.isConversionFiat == false) {
                    refundAmount += c.conversionAmount;
                }
            }
        }
        //If there's an amount to be returned and reserved tokens, update state and execute cashback
        if(reservedAmount > 0 && refundAmount > 0) {
            twoKeyAcquisitionCampaignERC20.updateReservedAmountOfTokensIfConversionRejectedOrExecuted(reservedAmount);
            twoKeyAcquisitionCampaignERC20.sendBackEthWhenConversionCancelled(_converter, refundAmount);
        }
    }


    /**
     * @notice Function to get all conversion ids for the converter
     * @param _converter is the address of the converter
     * @return array of conversion ids
     * @dev can only be called by converter itself or maintainer/contractor
     */
    function getConverterConversionIds(
        address _converter
    )
    public
    view
    returns (uint[])
    {
//        require(msg.sender == contractor || ITwoKeyEventSource(twoKeyEventSource).isAddressMaintainer(msg.sender) || msg.sender == _converter);
        return converterToHisConversions[_converter];
    }

    function getLastConverterConversionId(
        address _converter
    )
    public
    view
    returns (uint)
    {
        return converterToHisConversions[_converter][converterToHisConversions[_converter].length - 1];
    }


    /**
     * @notice Function to get number of conversions
     * @dev Can only be called by contractor or maintainer
     */
    function getNumberOfConversions()
    external
    view
    returns (uint)
    {
        return numberOfConversions;
    }


    /**
     * @notice Function to cancel conversion and get back money
     * @param _conversionId is the id of the conversion
     * @dev returns all the funds to the converter back
     */
    function converterCancelConversion(
        uint _conversionId
    )
    external
    {
        Conversion conversion = conversions[_conversionId];

        require(conversion.conversionCreatedAt + 10*(1 days) < block.timestamp);
        require(msg.sender == conversion.converter);
        require(conversion.state == ConversionState.PENDING_APPROVAL);

        counters[0]--; // Reduce number of pending conversions
        counters[4]++; // Increase number of cancelled conversions
        conversion.state = ConversionState.CANCELLED_BY_CONVERTER;
        twoKeyAcquisitionCampaignERC20.sendBackEthWhenConversionCancelled(msg.sender, conversion.conversionAmount);
    }

    /**
     * @notice Get's number of converters per type, and returns tuple, as well as total raised funds
     getCampaignSummary
     */
    function getCampaignSummary()
    public
    view
    returns (uint,uint,uint,uint[])
    {
        bytes32 pending = convertConverterStateToBytes(ConverterState.PENDING_APPROVAL);
        bytes32 approved = convertConverterStateToBytes(ConverterState.APPROVED);
        bytes32 rejected = convertConverterStateToBytes(ConverterState.REJECTED);

        uint numberOfPending = stateToConverter[pending].length;
        uint numberOfApproved = stateToConverter[approved].length;
        uint numberOfRejected = stateToConverter[rejected].length;

        return (
            numberOfPending,
            numberOfApproved,
            numberOfRejected,
            counters
        );
    }

    /**
     * @notice Function to get converter state
     * @param _converter is the address of the requested converter
     * @return hexed string of the state
     */
    function getStateForConverter(
        address _converter
    )
    external
    view
    returns (bytes32)
    {
        return convertConverterStateToBytes(converterToState[_converter]);
    }


    /**
     * @notice Function to fetch how much user spent money and bought units in total
     * @param _converter is the converter we're checking this information for
     */
    function getConverterPurchasesStats(
        address _converter
    )
    public
    view
    returns (uint,uint,uint)
    {
        return (
            amountConverterSpentEthWEI[_converter],
            amountConverterSpentFiatWei[_converter],
            unitsConverterBought[_converter]
        );
    }

}
