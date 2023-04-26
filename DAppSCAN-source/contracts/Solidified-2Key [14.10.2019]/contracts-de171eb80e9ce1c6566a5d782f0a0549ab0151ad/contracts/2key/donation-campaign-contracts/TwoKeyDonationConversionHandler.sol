pragma solidity ^0.4.0;


import "./InvoiceTokenERC20.sol";
import "../TwoKeyConversionStates.sol";
import "../TwoKeyConverterStates.sol";

import "../libraries/SafeMath.sol";
import "../interfaces/ITwoKeyDonationCampaign.sol";
import "../interfaces/ITwoKeyEventSource.sol";
import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";
import "../interfaces/ITwoKeyBaseReputationRegistry.sol";
import "../interfaces/ITwoKeyMaintainersRegistry.sol";
import "../interfaces/ITwoKeyExchangeRateContract.sol";
import "../upgradable-pattern-campaigns/UpgradeableCampaign.sol";


contract TwoKeyDonationConversionHandler is UpgradeableCampaign, TwoKeyConversionStates, TwoKeyConverterStates {

    using SafeMath for uint256; // Define lib necessary to handle uint operations
    bool isCampaignInitialized; //defaults to false

    Conversion [] public conversions;
    InvoiceTokenERC20 public erc20InvoiceToken; // ERC20 token which will be issued as an invoice

    ITwoKeyDonationCampaign twoKeyDonationCampaign;

    address twoKeySingletonRegistry;
    string currency;
    address contractor;
    uint numberOfConversions;
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
    uint [] counters; //Metrics counter


    mapping(address => uint256) private amountConverterSpentEthWEI; // Amount converter put to the contract in Ether
    mapping(bytes32 => address[]) stateToConverter; //State to all converters in that state
    mapping(address => ConverterState) converterToState; // Converter to state
    mapping(address => uint[]) converterToHisConversions;
    mapping(address => bool) isConverterAnonymous;
    mapping(address => bool) doesConverterHaveExecutedConversions;

    //Struct to represent donation in Ether
    struct Conversion {
        address contractor; // Contractor (creator) of campaign
        uint256 contractorProceedsETHWei; // How much contractor will receive for this conversion
        address converter; // Converter is one who's buying tokens -> plasma address
        ConversionState state;
        uint256 conversionAmount; // Amount for conversion (In ETH / FIAT)
        uint256 maxReferralRewardETHWei; // Total referral reward for the conversion
        uint256 maxReferralReward2key;
        uint256 moderatorFeeETHWei;
    }

    event InvoiceTokenCreated(
        address token,
        string tokenName,
        string tokenSymbol
    );

    event ConversionCreated(uint conversionId);

    modifier onlyContractorOrMaintainer {
        address twoKeyMaintainersRegistry = getAddressFromTwoKeySingletonRegistry("TwoKeyMaintainersRegistry");
        require(msg.sender == contractor || ITwoKeyMaintainersRegistry(twoKeyMaintainersRegistry).onlyMaintainer(msg.sender));
        _;
    }


    function setInitialParamsDonationConversionHandler(
        string tokenName,
        string tokenSymbol,
        string _currency,
        address _contractor,
        address _twoKeyDonationCampaign,
        address _twoKeySingletonRegistry
    )
    public
    {
        require(isCampaignInitialized == false);

        counters = new uint[](10);
        twoKeyDonationCampaign = ITwoKeyDonationCampaign(_twoKeyDonationCampaign);
        twoKeySingletonRegistry = _twoKeySingletonRegistry;
        contractor = _contractor;
        currency = _currency;
        // Deploy an ERC20 token which will be used as the Invoice
        erc20InvoiceToken = new InvoiceTokenERC20(tokenName,tokenSymbol,address(this));
        // Emit an event with deployed token address, name, and symbol
        emit InvoiceTokenCreated(address(erc20InvoiceToken), tokenName, tokenSymbol);
        isCampaignInitialized = true;
    }


    // Internal function to fetch address from TwoKeyRegTwoistry
    function getAddressFromTwoKeySingletonRegistry(string contractName) internal view returns (address) {
        return ITwoKeySingletoneRegistryFetchAddress(twoKeySingletonRegistry)
        .getContractProxyAddress(contractName);
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
        address twoKeyEventSource = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletonRegistry).getContractProxyAddress("TwoKeyEventSource");
        uint256 fee = _conversionAmountETHWei.mul(ITwoKeyEventSource(twoKeyEventSource).getTwoKeyDefaultIntegratorFeeFromAdmin()).div(100);
        return fee;
    }


    /**
     * @param _converterAddress is the one who calls join and donate function
     */
    function supportForCreateConversion(
        address _converterAddress,
        uint _conversionAmount,
        uint _maxReferralRewardETHWei,
        bool _isKYCRequired
    )
    public
    returns (uint)
    {
        require(msg.sender == address(twoKeyDonationCampaign));
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


        uint256 _moderatorFeeETHWei = calculateModeratorFee(_conversionAmount);
        uint256 _contractorProceeds = _conversionAmount - _maxReferralRewardETHWei - _moderatorFeeETHWei;
        counters[1]++;

        Conversion memory c = Conversion(
            contractor,
            _contractorProceeds,
            _converterAddress,
            ConversionState.APPROVED,
            _conversionAmount,
            _maxReferralRewardETHWei,
            0,
            _moderatorFeeETHWei
        );

        conversions.push(c);
        converterToHisConversions[_converterAddress].push(numberOfConversions);
        emit ConversionCreated(numberOfConversions);
        numberOfConversions++;

        return numberOfConversions-1;
    }

    function executeConversion(
        uint _conversionId
    )
    public
    {
        Conversion conversion = conversions[_conversionId];
        require(converterToState[conversion.converter] == ConverterState.APPROVED);
        require(conversion.state == ConversionState.APPROVED);

        counters[1]--; //Decrease number of approved conversions

//         Buy tokens from campaign and distribute rewards between referrers
        uint totalReward2keys = twoKeyDonationCampaign.buyTokensAndDistributeReferrerRewards(
            conversion.maxReferralRewardETHWei,
            conversion.converter,
            _conversionId
        );


        // Update reputation points in registry for conversion executed event
//        ITwoKeyBaseReputationRegistry(twoKeyBaseReputationRegistry).updateOnConversionExecutedEvent(
//            conversion.converter,
//            contractor,
//            twoKeyDonationCampaign
//        );


        amountConverterSpentEthWEI[conversion.converter] = amountConverterSpentEthWEI[conversion.converter].add(conversion.conversionAmount);
        counters[8] = counters[8].add(totalReward2keys);
        twoKeyDonationCampaign.buyTokensForModeratorRewards(conversion.moderatorFeeETHWei);
        twoKeyDonationCampaign.updateContractorProceeds(conversion.contractorProceedsETHWei);

        counters[6] = counters[6].add(conversion.conversionAmount);

        if(doesConverterHaveExecutedConversions[conversion.converter] == false) {
            counters[5]++; //increase number of unique converters
            doesConverterHaveExecutedConversions[conversion.converter] = true;
        }

        conversion.maxReferralReward2key = totalReward2keys;
        conversion.state = ConversionState.EXECUTED;
        counters[3]++; //Increase number of executed conversions

        //TODO: Add tokens transfer
        transferInvoiceToken(conversion.converter, conversion.conversionAmount);
    }

    function transferInvoiceToken(
        address _converter,
        uint _conversionAmountETHWei
    )
    internal
    {
        if(keccak256(currency) == keccak256('ETH')) {
            erc20InvoiceToken.transfer(_converter, _conversionAmountETHWei);
        } else {
            address twoKeyExchangeRateContract = getAddressFromTwoKeySingletonRegistry("TwoKeyExchangeRateContract");
            uint rate = ITwoKeyExchangeRateContract(twoKeyExchangeRateContract).getBaseToTargetRate(currency);

            uint conversionAmountInFIAT = (_conversionAmountETHWei*rate).div(10**18);

            erc20InvoiceToken.transfer(_converter, conversionAmountInFIAT);
        }
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
        moveFromPendingOrRejectedToApprovedState(_converter);
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

        address converter; // Defaults to 0x0

        if(isConverterAnonymous[conversion.converter] == false) {
            converter = conversion.converter;
        }

        return abi.encodePacked (
            conversion.contractor,
            converter,
            conversion.contractorProceedsETHWei,
            conversion.conversionAmount,
            conversion.maxReferralRewardETHWei,
            conversion.maxReferralReward2key,
            conversion.moderatorFeeETHWei,
            conversion.state
        );
    }

    function getAmountConverterSpent(
        address converter
    )
    public
    view
    returns (uint) {
        return amountConverterSpentEthWEI[converter];
    }

}
