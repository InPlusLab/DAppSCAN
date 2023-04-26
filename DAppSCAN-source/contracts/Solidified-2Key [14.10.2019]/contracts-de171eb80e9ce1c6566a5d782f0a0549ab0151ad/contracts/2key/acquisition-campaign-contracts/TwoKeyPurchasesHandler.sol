pragma solidity ^0.4.0;

import "../interfaces/ITwoKeyEventSource.sol";
import "../interfaces/IERC20.sol";
import "../upgradable-pattern-campaigns/UpgradeableCampaign.sol";


contract TwoKeyPurchasesHandler is UpgradeableCampaign {

    enum VestingAmount {BONUS, BASE_AND_BONUS}
    VestingAmount vestingAmount;

    bool initialized;
    bool isDistributionDateChanged;

    address proxyConversionHandler;
    address public assetContractERC20;
    address converter;
    address contractor;
    address twoKeyEventSource;

    mapping(uint => uint) public portionToUnlockingDate;

    uint numberOfPurchases;
    uint bonusTokensVestingStartShiftInDaysFromDistributionDate;
    uint tokenDistributionDate; // Start of token distribution
    uint numberOfVestingPortions; // For example 6
    uint numberOfDaysBetweenPortions; // For example 30 days
    uint maxDistributionDateShiftInDays;

    mapping(uint => Purchase) conversionIdToPurchase;

    event TokensWithdrawn(
        uint timestamp,
        address methodCaller,
        address tokensReceiver,
        uint portionId,
        uint portionAmount
    );

    struct Purchase {
        address converter;
        uint baseTokens;
        uint bonusTokens;
        uint [] portionAmounts;
        bool [] isPortionWithdrawn;
    }

    function setInitialParamsPurchasesHandler(
        uint[] values,
        address _contractor,
        address _assetContractERC20,
        address _twoKeyEventSource,
        address _proxyConversionHandler
    )
    public
    {
        require(initialized == false);

        tokenDistributionDate = values[2];
        maxDistributionDateShiftInDays = values[3];
        numberOfVestingPortions = values[4];
        numberOfDaysBetweenPortions = values[5];
        bonusTokensVestingStartShiftInDaysFromDistributionDate = values[6];
        vestingAmount = VestingAmount(values[7]);
        contractor = _contractor;
        assetContractERC20 = _assetContractERC20;
        twoKeyEventSource = _twoKeyEventSource;
        proxyConversionHandler = _proxyConversionHandler;

        uint bonusVestingStartDate;
        // In case vested amounts are both bonus and base, bonusTokensVestingStartShiftInDaysFromDistributionDate is ignored
        if(vestingAmount == VestingAmount.BASE_AND_BONUS) {
            bonusVestingStartDate = tokenDistributionDate + numberOfDaysBetweenPortions * (1 days);
        } else {
            bonusVestingStartDate = tokenDistributionDate + bonusTokensVestingStartShiftInDaysFromDistributionDate * (1 days);
        }


        portionToUnlockingDate[0] = tokenDistributionDate;

        for(uint i=1; i<numberOfVestingPortions + 1; i++) {
            portionToUnlockingDate[i] = bonusVestingStartDate + (i-1) * (numberOfDaysBetweenPortions * (1 days));
        }

        initialized = true;
    }


    function startVesting(
        uint _baseTokens,
        uint _bonusTokens,
        uint _conversionId,
        address _converter
    )
    public
    {
        require(msg.sender == proxyConversionHandler);
        if(vestingAmount == VestingAmount.BASE_AND_BONUS) {
            baseAndBonusVesting(_baseTokens, _bonusTokens, _conversionId, _converter);
        } else {
            bonusVestingOnly(_baseTokens, _bonusTokens, _conversionId, _converter);
        }
        numberOfPurchases++;
    }

    function bonusVestingOnly(
        uint _baseTokens,
        uint _bonusTokens,
        uint _conversionId,
        address _converter
    )
    internal
    {
        uint [] memory portionAmounts = new uint[](numberOfVestingPortions+1);
        bool [] memory isPortionWithdrawn = new bool[](numberOfVestingPortions+1);
        portionAmounts[0] = _baseTokens;

        uint bonusVestingStartDate = tokenDistributionDate + bonusTokensVestingStartShiftInDaysFromDistributionDate * (1 days);
        uint bonusPortionAmount = _bonusTokens / numberOfVestingPortions;

        for(uint i=1; i<numberOfVestingPortions + 1; i++) {
            portionAmounts[i] = bonusPortionAmount;
        }

        Purchase memory purchase = Purchase(
            _converter,
            _baseTokens,
            _bonusTokens,
            portionAmounts,
            isPortionWithdrawn
        );

        conversionIdToPurchase[_conversionId] = purchase;
    }

    function baseAndBonusVesting(
        uint _baseTokens,
        uint _bonusTokens,
        uint _conversionId,
        address _converter
    )
    internal
    {
        uint [] memory portionAmounts = new uint[](numberOfVestingPortions);
        bool [] memory isPortionWithdrawn = new bool[](numberOfVestingPortions);

        uint totalAmount = _baseTokens + _bonusTokens;
        uint portion = totalAmount / numberOfVestingPortions;

        for(uint i=0; i<numberOfVestingPortions; i++) {
            portionAmounts[i] = portion;
        }

        Purchase memory purchase = Purchase(
            _converter,
            _baseTokens,
            _bonusTokens,
            portionAmounts,
            isPortionWithdrawn
        );

        conversionIdToPurchase[_conversionId] = purchase;
    }


    function changeDistributionDate(
        uint _newDate
    )
    public
    {
        require(msg.sender == contractor);
        require(isDistributionDateChanged == false);
        require(_newDate - (maxDistributionDateShiftInDays * (1 days)) <= tokenDistributionDate);
        require(now < tokenDistributionDate);

        uint shift = tokenDistributionDate - _newDate;
        // If the date is changed shifting all tokens unlocking dates for the difference
        for(uint i=0; i<numberOfVestingPortions+1;i++) {
            portionToUnlockingDate[i] = portionToUnlockingDate[i] + shift;
        }

        isDistributionDateChanged = true;
        tokenDistributionDate = _newDate;
    }


    function withdrawTokens(
        uint conversionId,
        uint portion
    )
    public
    {
        Purchase p = conversionIdToPurchase[conversionId];
        //Only converter of maintainer can call this function
        require(msg.sender == p.converter || ITwoKeyEventSource(twoKeyEventSource).isAddressMaintainer(msg.sender) == true);
        require(p.isPortionWithdrawn[portion] == false && block.timestamp > portionToUnlockingDate[portion]);
        //Transfer tokens
        require(IERC20(assetContractERC20).transfer(p.converter, p.portionAmounts[portion]));
        p.isPortionWithdrawn[portion] = true;

        emit TokensWithdrawn (
            block.timestamp,
            msg.sender,
            converter,
            portion,
            p.portionAmounts[portion]
        );
    }

    function getPurchaseInformation(
        uint _conversionId
    )
    public
    view
    returns (address, uint, uint, uint[], bool[], uint[])
    {
        Purchase memory p = conversionIdToPurchase[_conversionId];
        uint [] memory unlockingDates = getPortionsUnlockingDates();
        return (
            p.converter,
            p.baseTokens,
            p.bonusTokens,
            p.portionAmounts,
            p.isPortionWithdrawn,
            unlockingDates
        );
    }

    function getStaticInfo()
    public
    view
    returns (uint,uint,uint,uint,uint,uint)
    {
        return (
            bonusTokensVestingStartShiftInDaysFromDistributionDate,
            tokenDistributionDate,
            numberOfVestingPortions,
            numberOfDaysBetweenPortions,
            maxDistributionDateShiftInDays,
            uint(vestingAmount)
        );
    }

    function getPortionsUnlockingDates()
    public
    view
    returns (uint[])
    {
        uint [] memory dates = new uint[](numberOfVestingPortions+1);
        for(uint i=0; i< numberOfVestingPortions+1; i++) {
            dates[i] = portionToUnlockingDate[i];
        }
        return dates;
    }



}
