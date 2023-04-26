pragma solidity ^0.4.24;

import "../campaign-mutual-contracts/TwoKeyCampaign.sol";
import "../campaign-mutual-contracts/TwoKeyCampaignIncentiveModels.sol";

import "../libraries/IncentiveModels.sol";
import "../TwoKeyConverterStates.sol";
import "../TwoKeyConversionStates.sol";

import "../interfaces/ITwoKeyDonationConversionHandler.sol";
import "../interfaces/ITwoKeyDonationLogicHandler.sol";
import "../upgradable-pattern-campaigns/UpgradeableCampaign.sol";

/**
 * @author Nikola Madjarevic
 * Created at 2/19/19
 */
contract TwoKeyDonationCampaign is UpgradeableCampaign, TwoKeyCampaign, TwoKeyCampaignIncentiveModels {

    bool initialized;

    address public twoKeyDonationConversionHandler; // Contract which will handle all donations
    address public twoKeyDonationLogicHandler;

    bool acceptsFiat; // Will determine if fiat conversion can be created or not



    //Referral accounting stuff
    mapping(address => uint256) private referrerPlasma2cut; // Mapping representing how much are cuts in percent(0-100) for referrer address

    modifier onlyTwoKeyDonationConversionHandler {
        require(msg.sender == twoKeyDonationConversionHandler);
        _;
    }


    function setInitialParamsDonationCampaign(
        address _contractor,
        address _moderator,
        address _twoKeySingletonRegistry,
        address _twoKeyDonationConversionHandler,
        address _twoKeyDonationLogicHandler,
        uint [] numberValues,
        bool [] booleanValues
    )
    public
    {
        require(initialized == false);

        contractor = _contractor;
        // Moderator address
        moderator = _moderator;

        twoKeySingletonesRegistry = _twoKeySingletonRegistry;
        twoKeyEventSource = TwoKeyEventSource(getContractProxyAddress("TwoKeyEventSource"));

        totalSupply_ = 1000000;

        maxReferralRewardPercent = numberValues[0];
        conversionQuota = numberValues[6];

        twoKeyDonationConversionHandler = _twoKeyDonationConversionHandler;
        twoKeyDonationLogicHandler = _twoKeyDonationLogicHandler;


        mustConvertToReferr = booleanValues[0];
        isKYCRequired = booleanValues[1];
        acceptsFiat = booleanValues[2];


        ownerPlasma = twoKeyEventSource.plasmaOf(_contractor);
        received_from[ownerPlasma] = ownerPlasma;
        balances[ownerPlasma] = totalSupply_;


        initialized = true;
    }

    /**
      * @notice Function to set cut of
      * @param me is the address (ethereum)
      * @param cut is the cut value
      */
    function setCutOf(
        address me,
        uint256 cut
    )
    internal
    {
        // what is the percentage of the bounty s/he will receive when acting as an influencer
        // the value 255 is used to signal equal partition with other influencers
        // A sender can set the value only once in a contract
        address plasma = twoKeyEventSource.plasmaOf(me);
        require(referrerPlasma2cut[plasma] == 0 || referrerPlasma2cut[plasma] == cut);
        referrerPlasma2cut[plasma] = cut;
    }

    /**
     * @notice Function to set cut
     * @param cut is the cut value
     * @dev Executes internal setCutOf method
     */
    function setCut(
        uint256 cut
    )
    public
    {
        setCutOf(msg.sender, cut);
    }


    /**
     * @notice Function to get cut for an (ethereum) address
     * @param me is the ethereum address
     */
    function getReferrerCut(
        address me
    )
    public
    view
    returns (uint256)
    {
        return referrerPlasma2cut[twoKeyEventSource.plasmaOf(me)];
    }

    /**
     * @notice Function to track arcs and make ref tree
     * @param sig is the signature user joins from
     */
    function distributeArcsBasedOnSignature(
        bytes sig,
        address _converter
    )
    private
    {
        address[] memory influencers;
        address[] memory keys;
        uint8[] memory weights;
        address old_address;
        (influencers, keys, weights, old_address) = super.getInfluencersKeysAndWeightsFromSignature(sig, _converter);
        uint i;
        address new_address;
        uint numberOfInfluencers = influencers.length;
        for (i = 0; i < numberOfInfluencers; i++) {
            new_address = twoKeyEventSource.plasmaOf(influencers[i]);

            if (received_from[new_address] == 0) {
                transferFrom(old_address, new_address, 1);
            } else {
                require(received_from[new_address] == old_address,'only tree ARCs allowed');
            }
            old_address = new_address;

            // TODO Updating the public key of influencers may not be a good idea because it will require the influencers to use
            // a deterministic private/public key in the link and this might require user interaction (MetaMask signature)
            // TODO a possible solution is change public_link_key to address=>address[]
            // update (only once) the public address used by each influencer
            // we will need this in case one of the influencers will want to start his own off-chain link
            if (i < keys.length) {
                setPublicLinkKeyOf(new_address, keys[i]);
            }

            // update (only once) the cut used by each influencer
            // we will need this in case one of the influencers will want to start his own off-chain link
            if (i < weights.length) {
                setCutOf(new_address, uint256(weights[i]));
            }
        }
    }


    /**
     * @notice Option to update contractor proceeds
     * @dev can be called only from TwoKeyConversionHandler contract
     * @param value it the value we'd like to add to total contractor proceeds and contractor balance
     */
    function updateContractorProceeds(
        uint value
    )
    public
    {
        require(msg.sender == twoKeyDonationConversionHandler);
        contractorTotalProceeds = contractorTotalProceeds.add(value);
        contractorBalance = contractorBalance.add(value);
    }

    /**
     * @notice Function to join with signature and share 1 arc to the receiver
     * @param signature is the signature
     * @param receiver is the address we're sending ARCs to
     */
    function joinAndShareARC(
        bytes signature,
        address receiver
    )
    public
    {
        distributeArcsBasedOnSignature(signature, msg.sender);
        transferFrom(twoKeyEventSource.plasmaOf(msg.sender), twoKeyEventSource.plasmaOf(receiver), 1);
    }

    /**
     * @notice Function where converter can convert
     * @dev payable function
     */
    function convert(
        bytes signature
    )
    public
    payable
    {
        address _converterPlasma = twoKeyEventSource.plasmaOf(msg.sender);
        if(received_from[_converterPlasma] == address(0)) {
            distributeArcsBasedOnSignature(signature, msg.sender);
        }
        createConversion(msg.value, msg.sender);
        twoKeyEventSource.converted(address(this),msg.sender,msg.value);
    }

    /*
     * @notice Function which is executed to create conversion
     * @param conversionAmountETHWeiOrFiat is the amount of the ether sent to the contract
     * @param converterAddress is the sender of eth to the contract
     */
    function createConversion(
        uint conversionAmountEthWEI,
        address converterAddress
    )
    private
    {
        uint256 maxReferralRewardFiatOrETHWei = conversionAmountEthWEI.mul(maxReferralRewardPercent).div(100);

        uint id = ITwoKeyDonationConversionHandler(twoKeyDonationConversionHandler).supportForCreateConversion(
            converterAddress,
            conversionAmountEthWEI,
            maxReferralRewardFiatOrETHWei,
            isKYCRequired
        );

        if(isKYCRequired == false) {
            ITwoKeyDonationConversionHandler(twoKeyDonationConversionHandler).executeConversion(id);
        }
    }

    /**
      * @notice Function to delegate call to logic handler and update data, and buy tokens
      * @param _maxReferralRewardETHWei total reward in ether wei
      * @param _converter is the converter address
      * @param _conversionId is the ID of conversion
      */
    function buyTokensAndDistributeReferrerRewards(
        uint256 _maxReferralRewardETHWei,
        address _converter,
        uint _conversionId
    )
    public
    returns (uint)
    {
        require(msg.sender == twoKeyDonationConversionHandler);
        //Fiat rewards = fiatamount * moderatorPercentage / 100  / 0.095
        uint totalBounty2keys;
        //If fiat conversion do exactly the same just send different reward and don't buy tokens, take them from contract
        if(maxReferralRewardPercent > 0) {
            //Buy tokens from upgradable exchange
            totalBounty2keys = buyTokensFromUpgradableExchange(_maxReferralRewardETHWei, address(this));
            //Handle refchain rewards
            ITwoKeyDonationLogicHandler(twoKeyDonationLogicHandler).updateRefchainRewards(
                _maxReferralRewardETHWei,
                _converter,
                _conversionId,
                totalBounty2keys);
        }
        reservedAmount2keyForRewards = reservedAmount2keyForRewards.add(totalBounty2keys);
        return totalBounty2keys;
    }

    /**
     * @notice Function which will buy tokens from upgradable exchange for moderator
     * @param moderatorFee is the fee in tokens moderator earned
     */
    function buyTokensForModeratorRewards(
        uint moderatorFee
    )
    public
    onlyTwoKeyDonationConversionHandler
    {
        //Get deep freeze token pool address
        address twoKeyDeepFreezeTokenPool = getContractProxyAddress("TwoKeyDeepFreezeTokenPool");

        uint networkFee = twoKeyEventSource.getTwoKeyDefaultNetworkTaxPercent();

        // Balance which will go to moderator
        uint balance = moderatorFee.mul(100-networkFee).div(100);

        uint moderatorEarnings2key = buyTokensFromUpgradableExchange(balance,moderator); // Buy tokens for moderator
        buyTokensFromUpgradableExchange(moderatorFee - balance, twoKeyDeepFreezeTokenPool); // Buy tokens for deep freeze token pool

        moderatorTotalEarnings2key = moderatorTotalEarnings2key.add(moderatorEarnings2key);
    }

    /**
     * @notice Function which acts like getter for all cuts in array
     * @param last_influencer is the last influencer
     * @return array of integers containing cuts respectively
     */
    function getReferrerCuts(
        address last_influencer
    )
    public
    view
    returns (uint256[])
    {
        address[] memory influencers = ITwoKeyDonationLogicHandler(twoKeyDonationLogicHandler).getReferrers(last_influencer);
        uint256[] memory cuts = new uint256[](influencers.length + 1);

        uint numberOfInfluencers = influencers.length;
        for (uint i = 0; i < numberOfInfluencers; i++) {
            address influencer = influencers[i];
            cuts[i] = getReferrerCut(influencer);
        }
        cuts[influencers.length] = getReferrerCut(last_influencer);
        return cuts;
    }


    /**
     * @param _referrer we want to check earnings for
     */
    function getReferrerBalance(address _referrer) public view returns (uint) {
        return referrerPlasma2Balances2key[twoKeyEventSource.plasmaOf(_referrer)];
    }

    /**
     * @notice Function to update referrer plasma balance
     * @param _influencer is the plasma address of referrer
     * @param _balance is the new balance
     */
    function updateReferrerPlasmaBalance(
        address _influencer,
        uint _balance
    )
    public
    {
        require(msg.sender == twoKeyDonationLogicHandler);
        referrerPlasma2Balances2key[_influencer] = referrerPlasma2Balances2key[_influencer].add(_balance);
    }

    /**
     * @notice Contractor can withdraw funds only if criteria is satisfied
     */
    function withdrawContractor() public onlyContractor {
        super.withdrawContractor();
    }

    /**
     * @notice Function to get reserved amount of rewards
     */
    function getReservedAmount2keyForRewards() public view returns (uint) {
        return reservedAmount2keyForRewards;
    }

    /**
     * @notice Function to get balance of influencer for his plasma address
     * @param _influencer is the plasma address of influencer
     * @return balance in wei's
     */
    function getReferrerPlasmaBalance(
        address _influencer
    )
    public
    view
    returns (uint)
    {
        require(msg.sender == twoKeyDonationLogicHandler);
        return (referrerPlasma2Balances2key[_influencer]);
    }


}
