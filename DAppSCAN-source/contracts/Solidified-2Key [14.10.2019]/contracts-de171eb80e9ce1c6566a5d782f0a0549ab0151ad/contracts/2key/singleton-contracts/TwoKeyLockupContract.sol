pragma solidity ^0.4.24;

import "../interfaces/IERC20.sol";
import "../interfaces/ITwoKeyEventSource.sol";

contract TwoKeyLockupContract {

    uint bonusTokensVestingStartShiftInDaysFromDistributionDate;
    uint tokenDistributionDate;
    uint numberOfVestingPortions; // For example 6
    uint numberOfDaysBetweenPortions; // For example 30 days
    uint maxDistributionDateShiftInDays;


    uint conversionId;

    uint public baseTokens;
    uint public bonusTokens;


    mapping(uint => uint) tokenUnlockingDate;
    mapping(uint => bool) isWithdrawn;

    address public converter;
    address contractor;
    address assetContractERC20;
    address twoKeyEventSource;

    bool changed;


    event TokensWithdrawn(
        uint timestamp,
        address methodCaller,
        address tokensReceiver,
        uint portionId,
        uint portionAmount
    );

    modifier onlyContractor() {
        require(msg.sender == contractor);
        _;
    }

    modifier onlyConverter() {
        require(msg.sender == converter);
        _;
    }


    constructor(
        uint _bonusTokensVestingStartShiftInDaysFromDistributionDate,
        uint _numberOfVestingPortions,
        uint _numberOfDaysBetweenPortions,
        uint _tokenDistributionDate,
        uint _maxDistributionDateShiftInDays,
        uint _baseTokens,
        uint _bonusTokens,
        uint _conversionId,
        address _converter,
        address _contractor,
        address _assetContractERC20,
        address _twoKeyEventSource
    )
    public
    {
        bonusTokensVestingStartShiftInDaysFromDistributionDate = _bonusTokensVestingStartShiftInDaysFromDistributionDate;
        numberOfVestingPortions = _numberOfVestingPortions;
        numberOfDaysBetweenPortions = _numberOfDaysBetweenPortions;
        tokenDistributionDate = _tokenDistributionDate;
        maxDistributionDateShiftInDays = _maxDistributionDateShiftInDays;
        baseTokens = _baseTokens;
        bonusTokens = _bonusTokens;
        conversionId = _conversionId;
        converter = _converter;
        contractor = _contractor;
        assetContractERC20 = _assetContractERC20;
        twoKeyEventSource = _twoKeyEventSource;
        tokenUnlockingDate[0] = tokenDistributionDate; //base tokens
        tokenUnlockingDate[1] = tokenDistributionDate + _bonusTokensVestingStartShiftInDaysFromDistributionDate * (1 days); // first part of bonus in days after tokens
        for(uint i=2 ;i<numberOfVestingPortions + 1; i++) {
            tokenUnlockingDate[i] = tokenUnlockingDate[1] + (i-1) * (numberOfDaysBetweenPortions * 1 days);
        }
    }

    function getLockupSummary()
    public
    view
    returns (uint, uint, uint, uint, uint[], bool[])
    {
        uint[] memory dates = new uint[](numberOfVestingPortions+1);
        bool[] memory areTokensWithdrawn = new bool[](numberOfVestingPortions+1);

        for(uint i=0; i<numberOfVestingPortions+1;i++) {
            dates[i] = tokenUnlockingDate[i];
            areTokensWithdrawn[i] = isWithdrawn[i];
        }
        //total = base + bonus
        // monthly bonus = bonus/numberOfVestingPortions
        return (baseTokens, bonusTokens, numberOfVestingPortions, conversionId, dates, areTokensWithdrawn);
    }


    /// @notice Function to change token distribution date
    /// @dev only contractor can issue calls to this method, and token distribution date can be changed only once
    /// @param _newDate is new token distribution date we'd like to set
    function changeTokenDistributionDate(
        uint _newDate
    )
    public
    onlyContractor
    {
        require(changed == false);
        require(_newDate - (maxDistributionDateShiftInDays * (1 days)) <= tokenDistributionDate);
        require(now < tokenDistributionDate);

        uint shift = tokenDistributionDate - _newDate;
        // If the date is changed shifting all tokens unlocking dates for the difference
        for(uint i=0; i<numberOfVestingPortions+1;i++) {
            tokenUnlockingDate[i] = tokenUnlockingDate[i] + shift;
        }

        changed = true;
        tokenDistributionDate = _newDate;
    }


    /// @notice Function where converter can withdraw his funds
    /// @return true is if transfer was successful, otherwise will revert
    /// onlyConverter
    function withdrawTokens(
        uint part
    )
    public
    returns (bool)
    {
        require(msg.sender == converter || ITwoKeyEventSource(twoKeyEventSource).isAddressMaintainer(msg.sender) == true);
        require(isWithdrawn[part] == false && part < numberOfVestingPortions+1 && block.timestamp > tokenUnlockingDate[part]);
        uint amount;
        if(part == 0) {
            amount = baseTokens;
        } else {
            amount = bonusTokens / numberOfVestingPortions;
        }
        isWithdrawn[part] = true;
        require(IERC20(assetContractERC20).transfer(converter,amount));

        // Emit an event after tokens are transfered
        emit TokensWithdrawn(
            block.timestamp,
            msg.sender,
            converter,
            part,
            amount
        );

        return true;
    }

}
