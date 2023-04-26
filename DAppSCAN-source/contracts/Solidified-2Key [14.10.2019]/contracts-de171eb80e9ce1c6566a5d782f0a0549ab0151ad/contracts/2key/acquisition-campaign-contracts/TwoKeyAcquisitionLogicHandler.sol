pragma solidity ^0.4.24;
//Interfaces
import "../interfaces/ITwoKeyExchangeRateContract.sol";
import "../interfaces/IERC20.sol";
import "../interfaces/ITwoKeyConversionHandler.sol";
import "../interfaces/ITwoKeyAcquisitionCampaignERC20.sol";
import "../interfaces/ITwoKeyReg.sol";
import "../interfaces/ITwoKeyAcquisitionARC.sol";
import "../interfaces/ITwoKeySingletoneRegistryFetchAddress.sol";
import "../interfaces/ITwoKeyEventSource.sol";
import "../interfaces/ITwoKeyMaintainersRegistry.sol";
//Libraries
import "../libraries/SafeMath.sol";
import "../libraries/Call.sol";
import "../libraries/IncentiveModels.sol";

import "../campaign-mutual-contracts/TwoKeyCampaignIncentiveModels.sol";
import "../upgradable-pattern-campaigns/UpgradeableCampaign.sol";

/**
 * @author Nikola Madjarevic
 * Created at 1/15/19
 */
contract TwoKeyAcquisitionLogicHandler is UpgradeableCampaign, TwoKeyCampaignIncentiveModels {

    using SafeMath for uint256;

    bool isCampaignInitialized;

    bool public IS_CAMPAIGN_ACTIVE;

    address public twoKeySingletoneRegistry;
    address public twoKeyAcquisitionCampaign;
    address public twoKeyConversionHandler;
    address public ownerPlasma;

    address twoKeyRegistry;
    address twoKeyMaintainersRegistry;

    address assetContractERC20;
    address contractor;
    address moderator;


    bool isFixedInvestmentAmount; // This means that minimal contribution is equal maximal contribution
    bool isAcceptingFiatOnly; // Means that only fiat conversions will be able to execute -> no referral rewards at all

    uint campaignStartTime; // Time when campaign start
    uint campaignEndTime; // Time when campaign ends
    uint minContributionETHorFiatCurrency; //Minimal contribution
    uint maxContributionETHorFiatCurrency; //Maximal contribution
    uint pricePerUnitInETHWeiOrUSD; // There's single price for the unit ERC20 (Should be in WEI)
    uint unit_decimals; // ERC20 selling data
    uint maxConverterBonusPercent; // Maximal bonus percent per converter
    uint campaignHardCapWei; // Hard cap of campaign

    string public currency; // Currency campaign is currently in

    // Enumerator representing incentive model selected for the contract
    IncentiveModel incentiveModel;

    //Referral accounting stuff
    mapping(address => uint256) internal referrerPlasma2TotalEarnings2key; // Total earnings for referrers
    mapping(address => uint256) internal referrerPlasmaAddressToCounterOfConversions; // [referrer][conversionId]
    mapping(address => mapping(uint256 => uint256)) internal referrerPlasma2EarningsPerConversion;


    modifier onlyContractor {
        require(msg.sender == contractor);
        _;
    }

    function setInitialParamsLogicHandler(
        uint [] values,
        string _currency,
        address _assetContractERC20,
        address _moderator,
        address _contractor,
        address _acquisitionCampaignAddress,
        address _twoKeySingletoneRegistry,
        address _twoKeyConversionHandler
    )
    public
    {
        require(values[1] >= values[0], "max contribution criteria not satisfied");
        require(values[4] > values[3], "campaign start time can't be greater than end time");
        require(isCampaignInitialized == false);

        if(values[0] == values[1]) {
            isFixedInvestmentAmount = true;
        }

        minContributionETHorFiatCurrency = values[0];
        maxContributionETHorFiatCurrency = values[1];
        pricePerUnitInETHWeiOrUSD = values[2];
        campaignStartTime = values[3];
        campaignEndTime = values[4];
        maxConverterBonusPercent = values[5];

        //Add as 6th argument incentive model uint
        incentiveModel = IncentiveModel(values[6]);
        if(values[7] == 1) {
            isAcceptingFiatOnly = true;
        }

        campaignHardCapWei = values[8];

        currency = _currency;
        assetContractERC20 = _assetContractERC20;
        moderator = _moderator;
        contractor = _contractor;
        unit_decimals = IERC20(_assetContractERC20).decimals();

        twoKeyAcquisitionCampaign = _acquisitionCampaignAddress;
        twoKeySingletoneRegistry = _twoKeySingletoneRegistry;

        twoKeyRegistry = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletoneRegistry).getContractProxyAddress("TwoKeyRegistry");
        twoKeyMaintainersRegistry = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletoneRegistry).getContractProxyAddress("TwoKeyMaintainersRegistry");

        ownerPlasma = plasmaOf(contractor);
        twoKeyConversionHandler = _twoKeyConversionHandler;

        isCampaignInitialized = true;
    }

    /**
     *
     */
    function activateCampaign() public onlyContractor {
        require(IS_CAMPAIGN_ACTIVE == false);
        uint balanceOfTokenBeingSoldOnAcquisition = getInventoryBalance();
        //balance is in weis, price is in weis and hardcap is regular number
        require((balanceOfTokenBeingSoldOnAcquisition * pricePerUnitInETHWeiOrUSD).div(10**18) >= campaignHardCapWei);
        IS_CAMPAIGN_ACTIVE = true;
    }


    function checkHowMuchUserCanSpend(uint alreadySpentETHWei, uint alreadySpentFiatWEI) public view returns (uint) {
        if(keccak256(currency) == keccak256('ETH')) {
            uint leftToSpendInEther = maxContributionETHorFiatCurrency - alreadySpentETHWei;
            return leftToSpendInEther;
        } else {
            //In order to work with this I have to convert everything to same currency
            address ethUSDExchangeContract = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletoneRegistry).getContractProxyAddress("TwoKeyExchangeRateContract");
            uint rate = ITwoKeyExchangeRateContract(ethUSDExchangeContract).getBaseToTargetRate(currency);

            uint totalAmountSpentConvertedToFIAT = (alreadySpentETHWei*rate).div(10**18) + alreadySpentFiatWEI;
            uint limit = maxContributionETHorFiatCurrency; // Initially we assume it's fiat currency campaign
            uint leftToSpendInFiats = limit-totalAmountSpentConvertedToFIAT;
            return leftToSpendInFiats;
        }
    }

    function canConversionBeCreated(address converter, uint amountWillingToSpend, bool isFiat) public view returns (bool) {
        bool canConvert = checkIsCampaignActive();
        if(IS_CAMPAIGN_ACTIVE == false) {
            return false;
        }
        if(canConvert == false) {
            return false;
        }
        //If we reach this point means we have reached point that campaign is still active
        if(isFiat) {
            (canConvert,)= canMakeFiatConversion(converter, amountWillingToSpend);
        } else {
            (canConvert,) = canMakeETHConversion(converter, amountWillingToSpend);
        }

        return canConvert;
    }

    //TODO: HANDLE INSIDE THIS METHODS MIN CONTRIBUTION AMOUNT

    function canMakeFiatConversion(address converter, uint amountWillingToSpendFiatWei) internal view returns (bool,uint) {
        uint alreadySpentETHWei;
        uint alreadySpentFIATWEI;
        if(keccak256(currency) == keccak256('ETH')) {
            return (false, 0);
        } else {
            (alreadySpentETHWei,alreadySpentFIATWEI,) = ITwoKeyConversionHandler(twoKeyConversionHandler).getConverterPurchasesStats(converter);

            uint leftToSpendFiat = checkHowMuchUserCanSpend(alreadySpentETHWei,alreadySpentFIATWEI);
            if(leftToSpendFiat >= amountWillingToSpendFiatWei) {
                return (true,leftToSpendFiat);
            } else {
                return (false,leftToSpendFiat);
            }
        }
    }

    function canMakeETHConversion(address converter, uint amountWillingToSpendEthWei) public view returns (bool,uint) {
        uint alreadySpentETHWei;
        uint alreadySpentFIATWEI;
        (alreadySpentETHWei,alreadySpentFIATWEI,) = ITwoKeyConversionHandler(twoKeyConversionHandler).getConverterPurchasesStats(converter);
        uint leftToSpend = checkHowMuchUserCanSpend(alreadySpentETHWei, alreadySpentFIATWEI);

        if(keccak256(currency) == keccak256('ETH')) {
            //Adding a deviation of 1000 weis
            if(leftToSpend + 1000 > amountWillingToSpendEthWei) {
                return(true, leftToSpend);
            } else {
                return(false, leftToSpend);
            }
        } else {
            address ethUSDExchangeContract = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletoneRegistry).getContractProxyAddress("TwoKeyExchangeRateContract");
            uint rate = ITwoKeyExchangeRateContract(ethUSDExchangeContract).getBaseToTargetRate(currency);
            uint amountToBeSpentInFiat = (amountWillingToSpendEthWei*rate).div(10**18);
            //Adding gap of 100 weis
            if(leftToSpend + 1000 >= amountToBeSpentInFiat) {
                return (true,leftToSpend);
            } else {
                return (false,leftToSpend);
            }
        }
    }

    /**
     * @notice Requirement for the checking if the campaign is active or not
     */
    function checkIsCampaignActive()
    public
    view
    returns (bool)
    {
        if(block.timestamp >= campaignStartTime && block.timestamp <= campaignEndTime) {
            return true;
        }
        return false;
    }


    /**
     * @notice Function to get investment rules
     * @return tuple containing if investment amount is fixed, and lower/upper bound of the same if not (if yes lower = upper)
     */
    function getInvestmentRules()
    public
    view
    returns (bool,uint,uint)
    {
        return (isFixedInvestmentAmount, minContributionETHorFiatCurrency, maxContributionETHorFiatCurrency);
    }



    /**
     * @notice Function which will calculate the base amount, bonus amount
     * @param conversionAmountETHWeiOrFiat is amount of eth in conversion
     * @return tuple containing (base,bonus)
     */
    function getEstimatedTokenAmount(
        uint conversionAmountETHWeiOrFiat,
        bool isFiatConversion
    )
    public
    view
    returns (uint, uint)
    {
        uint value = pricePerUnitInETHWeiOrUSD;
        uint baseTokensForConverterUnits;
        uint bonusTokensForConverterUnits;
        if(isFiatConversion == true) {
            baseTokensForConverterUnits = conversionAmountETHWeiOrFiat.mul(10**18).div(value);
            bonusTokensForConverterUnits = baseTokensForConverterUnits.mul(maxConverterBonusPercent).div(100);
            return (baseTokensForConverterUnits, bonusTokensForConverterUnits);
        } else {
            if(keccak256(currency) != keccak256('ETH')) {
                address ethUSDExchangeContract = ITwoKeySingletoneRegistryFetchAddress(twoKeySingletoneRegistry).getContractProxyAddress("TwoKeyExchangeRateContract");
                uint rate = ITwoKeyExchangeRateContract(ethUSDExchangeContract).getBaseToTargetRate(currency);

                conversionAmountETHWeiOrFiat = (conversionAmountETHWeiOrFiat.mul(rate)).div(10 ** 18); //converting eth to $wei
            }
        }

        baseTokensForConverterUnits = conversionAmountETHWeiOrFiat.mul(10 ** unit_decimals).div(value);
        bonusTokensForConverterUnits = baseTokensForConverterUnits.mul(maxConverterBonusPercent).div(100);
        return (baseTokensForConverterUnits, bonusTokensForConverterUnits);
    }

    /**
     * @notice Function to update MinContributionETH
     * @dev only Contractor can call this method, otherwise it will revert - emits Event when updated
     * @param value is the new value we are going to set for minContributionETH
     */
    function updateMinContributionETHOrUSD(
        uint value
    )
    public
    onlyContractor
    {
        minContributionETHorFiatCurrency = value;
    }

    /**
     * @notice Function to update maxContributionETH
     * @dev only Contractor can call this method, otherwise it will revert - emits Event when updated
     * @param value is the new maxContribution value
     */
    function updateMaxContributionETHorUSD(
        uint value
    )
    external
    onlyContractor
    {
        maxContributionETHorFiatCurrency = value;
    }

    /**
     * @notice Get all constants from the contract
     * @return all constants from the contract
     */
    function getConstantInfo()
    public
    view
    returns (uint,uint,uint,uint,uint,uint,uint)
    {
        return (
            campaignStartTime,
            campaignEndTime,
            minContributionETHorFiatCurrency,
            maxContributionETHorFiatCurrency,
            unit_decimals,
            pricePerUnitInETHWeiOrUSD,
            maxConverterBonusPercent
        );
    }


    /**
    * @notice Function to check balance of the ERC20 inventory (view - no gas needed to call this function)
    * @dev we're using Utils contract and fetching the balance of this contract address
    * @return balance value as uint
    */
    function getInventoryBalance()
    internal
    view
    returns (uint)
    {
        uint balance = IERC20(assetContractERC20).balanceOf(twoKeyAcquisitionCampaign);
        return balance;
    }


    /**
     * @notice Function to check if the msg.sender has already joined
     * @return true/false depending of joined status
     */
    function getAddressJoinedStatus(
        address _address
    )
    public
    view
    returns (bool)
    {
        address plasma = plasmaOf(_address);
        if (_address == address(0)) {
            return false;
        }
        if (plasma == ownerPlasma || _address == address(moderator) ||
        ITwoKeyAcquisitionARC(twoKeyAcquisitionCampaign).getReceivedFrom(plasma) != address(0)
        || ITwoKeyAcquisitionARC(twoKeyAcquisitionCampaign).balanceOf(plasma) > 0) {
            return true;
        }
        return false;
    }



    /**
     * @notice Function to fetch stats for the address
     */
    function getAddressStatistic(
        address _address,
        bool plasma,
        bool flag,
        address referrer
    )
    internal
    view
    returns (bytes)
    {
        bytes32 state; // NOT-EXISTING AS CONVERTER DEFAULT STATE

        address eth_address = ethereumOf(_address);
        address plasma_address = plasmaOf(_address);

        if(_address == contractor) {
            abi.encodePacked(0, 0, 0, false, false);
        } else {
            bool isConverter;
            bool isReferrer;
            uint unitsConverterBought;
            uint amountConverterSpent;
            uint amountConverterSpentFIAT;

            (amountConverterSpent,amountConverterSpentFIAT, unitsConverterBought) = ITwoKeyConversionHandler(twoKeyConversionHandler).getConverterPurchasesStats(eth_address);
            if(unitsConverterBought> 0) {
                isConverter = true;
                state = ITwoKeyConversionHandler(twoKeyConversionHandler).getStateForConverter(eth_address);
            }
            if(referrerPlasma2TotalEarnings2key[plasma_address] > 0) {
                isReferrer = true;
            }

//            if(flag == false) {
//                //referrer is address in signature
//                //plasma_address is plasma address of the address requested in method
//                referrerTotalBalance  = getTotalReferrerEarnings(referrer, eth_address);
//            }

            return abi.encodePacked(
                amountConverterSpent,
                referrerPlasma2TotalEarnings2key[plasma_address],
                unitsConverterBought,
                isConverter,
                isReferrer,
                state
            );
        }
    }

    function recover(
        bytes signature
    )
    internal
    view
    returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding referrer to plasma")),
            keccak256(abi.encodePacked("GET_REFERRER_REWARDS"))));
        address x = Call.recoverHash(hash, signature, 0);
        return x;
    }

    /**
     * @notice Function to get super statistics
     * @param _user is the user address we want stats for
     * @param plasma is if that address is plasma or not
     * @param signature in case we're calling this from referrer who doesn't have yet opened wallet
     */
    function getSuperStatistics(
        address _user,
        bool plasma,
        bytes signature
    )
    public
    view
    returns (bytes)
    {
        address eth_address = _user;

        if (plasma) {
            (eth_address) = ITwoKeyReg(twoKeyRegistry).getPlasmaToEthereum(_user);
        }

        bytes memory userData = ITwoKeyReg(twoKeyRegistry).getUserData(eth_address);

        bool isJoined = getAddressJoinedStatus(_user);
        bool flag;

        address _address;

        if(msg.sender == contractor || msg.sender == eth_address) {
            flag = true;
        } else {
            _address = recover(signature);
            if(_address == ownerPlasma) {
                flag = true;
            }
        }
        bytes memory stats = getAddressStatistic(_user, plasma, flag, _address);
        return abi.encodePacked(userData, isJoined, eth_address, stats);
    }

    /**
     * @notice Function to return referrers participated in the referral chain
     * @param customer is the one who converted (bought tokens)
     * @param acquisitionCampaignContract is the acquisition campaign address
     * @return array of referrer addresses
     */
    function getReferrers(
        address customer,
        address acquisitionCampaignContract
    )
    public
    view
    returns (address[])
    {
        address influencer = plasmaOf(customer);
        uint n_influencers = 0;

        while (true) {
            influencer = plasmaOf(ITwoKeyAcquisitionARC(acquisitionCampaignContract).getReceivedFrom(influencer));
            if (influencer == plasmaOf(contractor)) {
                break;
            }
            n_influencers++;
        }

        address[] memory influencers = new address[](n_influencers);
        influencer = plasmaOf(customer);

        while (n_influencers > 0) {
            influencer = plasmaOf(ITwoKeyAcquisitionARC(acquisitionCampaignContract).getReceivedFrom(influencer));
            n_influencers--;
            influencers[n_influencers] = influencer;
        }

        return influencers;
    }

    function updateReferrerMappings(address referrerPlasma, uint reward, uint conversionId) internal {
        ITwoKeyAcquisitionCampaignERC20(twoKeyAcquisitionCampaign).updateReferrerPlasmaBalance(referrerPlasma,reward);
        referrerPlasma2TotalEarnings2key[referrerPlasma] = referrerPlasma2TotalEarnings2key[referrerPlasma].add(reward);
        referrerPlasma2EarningsPerConversion[referrerPlasma][conversionId] = reward;
        referrerPlasmaAddressToCounterOfConversions[referrerPlasma] += 1;
    }

    /**
     * @notice Update refferal chain with rewards (update state variables)
     * @param _maxReferralRewardETHWei is the max referral reward set
     * @param _converter is the address of the converter
     * @dev This function can only be called by TwoKeyConversionHandler contract
     */
    function updateRefchainRewards(
        uint256 _maxReferralRewardETHWei,
        address _converter,
        uint _conversionId,
        uint totalBounty2keys
    )
    public
    {
        require(msg.sender == twoKeyAcquisitionCampaign);

        //Get all the influencers
        address[] memory influencers = getReferrers(_converter,twoKeyAcquisitionCampaign);

        //Get array length
        uint numberOfInfluencers = influencers.length;

        uint i;
        uint reward;
        if(incentiveModel == IncentiveModel.VANILLA_AVERAGE) {
            reward = IncentiveModels.averageModelRewards(totalBounty2keys, numberOfInfluencers);
            for(i=0; i<numberOfInfluencers; i++) {
                updateReferrerMappings(influencers[i], reward, _conversionId);

            }
        } else if (incentiveModel == IncentiveModel.VANILLA_AVERAGE_LAST_3X) {
            uint rewardForLast;
            // Calculate reward for regular ones and for the last
            (reward, rewardForLast) = IncentiveModels.averageLast3xRewards(totalBounty2keys, numberOfInfluencers);

            //Update equal rewards to all influencers but last
            for(i=0; i<numberOfInfluencers - 1; i++) {
                updateReferrerMappings(influencers[i], reward, _conversionId);

            }
            //Update reward for last
            updateReferrerMappings(influencers[numberOfInfluencers-1], rewardForLast, _conversionId);
        } else if(incentiveModel == IncentiveModel.VANILLA_POWER_LAW) {
            // Get rewards per referrer
            uint [] memory rewards = IncentiveModels.powerLawRewards(totalBounty2keys, numberOfInfluencers, 2);
            //Iterate through all referrers and distribute rewards
            for(i=0; i<numberOfInfluencers; i++) {
                updateReferrerMappings(influencers[i], rewards[i], _conversionId);
            }
        } else if(incentiveModel == IncentiveModel.MANUAL) {
            for (i = 0; i < numberOfInfluencers; i++) {
                uint256 b;

                if (i == influencers.length - 1) {  // if its the last influencer then all the bounty goes to it.
                    b = totalBounty2keys;
                }
                else {
                    uint256 cut = ITwoKeyAcquisitionCampaignERC20(twoKeyAcquisitionCampaign).getReferrerCut(influencers[i]);
                    if (cut > 0 && cut <= 101) {
                        b = totalBounty2keys.mul(cut.sub(1)).div(100);
                    } else {// cut == 0 or 255 indicates equal particine of the bounty
                        b = totalBounty2keys.div(influencers.length - i);
                    }
                }

                updateReferrerMappings(influencers[i], b, _conversionId);
                //Decrease bounty for distributed
                totalBounty2keys = totalBounty2keys.sub(b);
            }
        }
    }


//    /**
//     * @notice Helper function to get how much _referrer address earned for all conversions for eth_address
//     * @param _referrer is the address we're checking the earnings
//     * @param eth_address is the converter address we're getting all conversion ids for
//     * @return sum of all earnings
//     */
//    function getTotalReferrerEarnings(
//        address _referrer,
//        address eth_address
//    )
//    internal
//    view
//    returns (uint)
//    {
//        uint[] memory conversionIds = ITwoKeyConversionHandler(twoKeyConversionHandler).getConverterConversionIds(eth_address);
//        uint sum = 0;
//        uint len = conversionIds.length;
//        for(uint i=0; i<len; i++) {
//            sum += referrerPlasma2EarningsPerConversion[_referrer][conversionIds[i]];
//        }
//        return sum;
//    }


    /**
     * @notice Function to get balance and total earnings for all referrer addresses passed in arg
     * @param _referrerPlasmaList is the array of plasma addresses of referrer
     * @return two arrays. 1st contains current plasma balance and 2nd contains total plasma balances
     */
    function getReferrersBalancesAndTotalEarnings(
        address[] _referrerPlasmaList
    )
    public
    view
    returns (uint256[], uint256[])
    {
        require(ITwoKeyMaintainersRegistry(twoKeyMaintainersRegistry).onlyMaintainer(msg.sender));

        uint numberOfAddresses = _referrerPlasmaList.length;
        uint256[] memory referrersPendingPlasmaBalance = new uint256[](numberOfAddresses);
        uint256[] memory referrersTotalEarningsPlasmaBalance = new uint256[](numberOfAddresses);

        for (uint i=0; i<numberOfAddresses; i++){
            referrersPendingPlasmaBalance[i] = ITwoKeyAcquisitionCampaignERC20(twoKeyAcquisitionCampaign).getReferrerPlasmaBalance(_referrerPlasmaList[i]);
            referrersTotalEarningsPlasmaBalance[i] = referrerPlasma2TotalEarnings2key[_referrerPlasmaList[i]];
        }

        return (referrersPendingPlasmaBalance, referrersTotalEarningsPlasmaBalance);
    }


    /**
     * @notice Function to fetch for the referrer his balance, his total earnings, and how many conversions he participated in
     * @dev only referrer by himself, moderator, or contractor can call this
     * @param _referrer is the address of referrer we're checking for
     * @param signature is the signature if calling functions from FE without ETH address
     * @param conversionIds are the ids of conversions this referrer participated in
     * @return tuple containing this 3 information
     */
    function getReferrerBalanceAndTotalEarningsAndNumberOfConversions(
        address _referrer,
        bytes signature,
        uint[] conversionIds
    )
    public
    view
    returns (uint,uint,uint,uint[])
    {
        if(_referrer != address(0)) {
            require(msg.sender == _referrer || msg.sender == contractor || ITwoKeyMaintainersRegistry(twoKeyMaintainersRegistry).onlyMaintainer(msg.sender));
            _referrer = plasmaOf(_referrer);
        } else {
            bytes32 hash = keccak256(abi.encodePacked(keccak256(abi.encodePacked("bytes binding referrer to plasma")),
                keccak256(abi.encodePacked("GET_REFERRER_REWARDS"))));
            _referrer = Call.recoverHash(hash, signature, 0);
        }

        uint len = conversionIds.length;
        uint[] memory earnings = new uint[](len);

        for(uint i=0; i<len; i++) {
            earnings[i] = referrerPlasma2EarningsPerConversion[_referrer][conversionIds[i]];
        }

        uint referrerBalance = ITwoKeyAcquisitionCampaignERC20(twoKeyAcquisitionCampaign).getReferrerPlasmaBalance(_referrer);
        return (referrerBalance, referrerPlasma2TotalEarnings2key[_referrer], referrerPlasmaAddressToCounterOfConversions[_referrer], earnings);
    }


    function getReferrerPlasmaTotalEarnings(
        address _referrer
    )
    public
    view
    returns (uint)
    {
        require(msg.sender == twoKeyAcquisitionCampaign);
        return referrerPlasma2TotalEarnings2key[_referrer];
    }

    /**
     * @notice Function to determine plasma address of ethereum address
     * @param me is the address (ethereum) of the user
     * @return an address
     */
    function plasmaOf(
        address me
    )
    public
    view
    returns (address)
    {
        address plasma = ITwoKeyReg(twoKeyRegistry).getEthereumToPlasma(me);
        if (plasma != address(0)) {
            return plasma;
        }
        return me;
    }

    /**
     * @notice Function to determine ethereum address of plasma address
     * @param me is the plasma address of the user
     * @return ethereum address
     */
    function ethereumOf(
        address me
    )
    public
    view
    returns (address)
    {
        address ethereum = ITwoKeyReg(twoKeyRegistry).getPlasmaToEthereum(me);
        if (ethereum != address(0)) {
            return ethereum;
        }
        return me;
    }

}
