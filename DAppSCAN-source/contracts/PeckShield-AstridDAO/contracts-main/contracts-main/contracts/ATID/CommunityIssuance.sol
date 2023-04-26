// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "../Interfaces/IATIDToken.sol";
import "../Interfaces/ICommunityIssuance.sol";
import "../Dependencies/BaseMath.sol";
import "../Dependencies/AstridMath.sol";
import "../Dependencies/Ownable.sol";
import "../Dependencies/CheckContract.sol";
import "../Dependencies/SafeMath.sol";

// There should be a separate instance of CommunityIssuance per collateral type.
contract CommunityIssuance is ICommunityIssuance, Ownable, CheckContract, BaseMath {
    using SafeMath for uint;

    // --- Data ---

    string constant public NAME = "CommunityIssuance";

    uint constant public SECONDS_IN_ONE_MINUTE = 60;

   /* The issuance factor F determines the curvature of the issuance curve.
    *
    * Minutes in one year: 60*24*365 = 525600
    *
    * For 80% of remaining tokens issued each year, with minutes as time units, we have:
    * 
    * F ** 525600 = 0.8
    * 
    * Re-arranging:
    * 
    * 525600 * ln(F) = ln(0.8)
    * F = 0.8 ** (1/525600)
    * F = 0.999999575449954440
    */
    uint constant public ISSUANCE_FACTOR = 999999575449954440;

    // Only max 20 collateral types are allowed to earn rewards.
    uint constant public MAX_REWARD_EARNING_COLLATERAL_COUNT = 20;

    /* 
    * The community ATID supply cap is the starting balance of the Community Issuance contract.
    * It should be minted to this contract by ATIDToken, when the token is deployed.
    * 
    * Set to 25% of total ATID supply, which is 25% of 1 billion, or 250 million.
    */
    uint public immutable ATIDSupplyCap;

    IATIDToken public atidToken;

    // Multiple collateral types can point to the same CommunityIssuance.
    mapping (address => string) public stabilityPoolAddressToCollateralName;

    uint public totalATIDIssued;
    uint public immutable deploymentTime;

    // Keys to the collateralNameToDistributionFraction.
    string[] public allRewardEarningCollateralNames;
    // Fraction of issued ATID per collateral type.
    mapping (string => uint) public collateralNameToDistributionFraction;  // Scaled by 10**18
    // Currently accumulated undistributed ATID tokens.
    mapping (string => uint) public collateralNameToAccumulatedATID;

    // --- Events ---

    event CollateralDistributionFractionSet();

    // --- Functions ---

    constructor(
        uint _ATIDSupplyCap
    ) {
        ATIDSupplyCap = _ATIDSupplyCap;
        deploymentTime = block.timestamp;
    }

    function setATIDTokenAddress
    (
        address _atidTokenAddress
    ) 
        external
        onlyOwner
        override
    {
        checkContract(_atidTokenAddress);

        atidToken = IATIDToken(_atidTokenAddress);

        // When ATIDToken deployed, it should have transferred CommunityIssuance's ATID entitlement
        uint ATIDBalance = atidToken.balanceOf(address(this));
        assert(ATIDBalance >= ATIDSupplyCap);

        emit ATIDTokenAddressSet(_atidTokenAddress);
        // _renounceOwnership();
    }

    // Set stability pool as handling a specific collateral name.
    function setStabilityPoolAddress(
        address _stabilityPoolAddress,
        string memory _collateralName
    )
        external
        onlyOwner
        override
    {
        checkContract(_stabilityPoolAddress);
        require(!_isStringEqual(_collateralName, ""), "CommunityIssuance: collateral name cannot be empty");
        stabilityPoolAddressToCollateralName[_stabilityPoolAddress] = _collateralName;
        emit StabilityPoolAddressSet(_stabilityPoolAddress, _collateralName);
    }

    // Set reward distribution fraction per collateral name.
    // Max 20 collaterals can receive rewards, each of them must have fraction > 0, and their total fraction must be 100%.
    function setRewardDistributionFractions
    (
        string[] memory _collateralNames,
        uint[] memory _fractions
    )
        external
        onlyOwner
        override
    {
        require(_collateralNames.length == _fractions.length, "CommunityIssuance: collateralNames and fractions length do not match");
        require(_collateralNames.length <= MAX_REWARD_EARNING_COLLATERAL_COUNT, "CommunityIssuance: too many collaterals");
        require(_collateralNames.length > 0, "CommunityIssuance: at least 1 collateral should be earning rewards");

        // Delete all existing fractions.
        for (uint i = 0; i < allRewardEarningCollateralNames.length; i++) {
            delete collateralNameToDistributionFraction[allRewardEarningCollateralNames[i]];
        }
        // Delete existing remembered reward earning names.
        delete allRewardEarningCollateralNames;
        
        // Replace with new fractions.
        uint totalFractions = 0;
        for (uint i = 0; i < _collateralNames.length; i++) {
            require(_fractions[i] > 0, "CommunityIssuance: fraction cannot be 0");
            require(collateralNameToDistributionFraction[_collateralNames[i]] == 0, "CommunityIssuance: same collateral cannot appear twice");

            allRewardEarningCollateralNames.push(_collateralNames[i]);
            collateralNameToDistributionFraction[_collateralNames[i]] = _fractions[i];
            totalFractions += _fractions[i];
        }
        require(totalFractions == DECIMAL_PRECISION, "CommunityIssuance: sum of all fractions should be 100%");
        emit CollateralDistributionFractionSet(); 
    }

    // ========= StabilityPool only operations ========= 

    // Issue ATID up to the current timestamp.
    // This will add to the accumulated ATID over all supported collaterals.
    // StabilityPools that do no earn rewards will also be able to call it.
    function issueATID() external override {
        _requireCallerIsStabilityPool();

        uint latestTotalATIDIssued = ATIDSupplyCap.mul(_getCumulativeIssuanceFraction()).div(DECIMAL_PRECISION);
        uint issuance = latestTotalATIDIssued.sub(totalATIDIssued);

        totalATIDIssued = latestTotalATIDIssued;
        emit TotalATIDIssuedUpdated(latestTotalATIDIssued);

        // Iterate through all active collateral names that earns ATID rewards.
        for (uint i = 0; i < allRewardEarningCollateralNames.length; i++) {
            uint collateralDistributionFraction = collateralNameToDistributionFraction[allRewardEarningCollateralNames[i]];
            collateralNameToAccumulatedATID[allRewardEarningCollateralNames[i]] += issuance.mul(collateralDistributionFraction).div(DECIMAL_PRECISION);
        }
    }

    // Clears the currently accumulated ATID for the current collateral type.
    // The value is likely accumulated with a certain amount in the past (when other peer StabilityPool called issueATID).
    // StabilityPools that do no earn rewards will also be able to call it, as long as the collateral name is indeed
    // managed by it (in stabilityPoolAddressToCollateralName).
    function getAndClearAccumulatedATID(string memory _collateralName) external override returns (uint accumulatedATID) {
        // It also requires the right StabilityPool to call it.
        _requireCallerIsStabilityPoolForCollateral(_collateralName);

        accumulatedATID = collateralNameToAccumulatedATID[_collateralName];
        delete collateralNameToAccumulatedATID[_collateralName];
    }

    /* Gets 1-f^t    where: f < 1

    f: issuance factor that determines the shape of the curve
    t:  time passed since last ATID issuance event  */
    function _getCumulativeIssuanceFraction() internal view returns (uint) {
        // Get the time passed since deployment
        uint timePassedInMinutes = block.timestamp.sub(deploymentTime).div(SECONDS_IN_ONE_MINUTE);

        // f^t
        uint power = AstridMath._decPow(ISSUANCE_FACTOR, timePassedInMinutes);

        //  (1 - f^t)
        uint cumulativeIssuanceFraction = (uint(DECIMAL_PRECISION).sub(power));
        assert(cumulativeIssuanceFraction <= DECIMAL_PRECISION); // must be in range [0,1]

        return cumulativeIssuanceFraction;
    }

    function sendATID(address _account, uint _ATIDamount) external override {
        _requireCallerIsStabilityPool();

        require(atidToken.transfer(_account, _ATIDamount), "CommunityIssuance: cannot receive ATID reward");
    }

    // --- 'require' functions ---

    function _requireCallerIsStabilityPool() internal view {
        require(!_isStringEqual(stabilityPoolAddressToCollateralName[msg.sender], ""), "CommunityIssuance: caller is not an SP");
    }

    function _requireCallerIsStabilityPoolForCollateral(string memory _collateralName) internal view {
        require(_isStringEqual(stabilityPoolAddressToCollateralName[msg.sender], _collateralName), "CommunityIssuance: caller is not the right SP");
    }

    // https://ethereum.stackexchange.com/questions/30912/how-to-compare-strings-in-solidity
    function _isStringEqual(string memory _a, string memory _b) internal pure returns (bool) {
        // Check for string length equals. This also addresses empty string issue.
        if (bytes(_a).length != bytes(_b).length) {
            return false;
        } else {
            // Use string hashes to compare string.
            return keccak256(abi.encodePacked(_a)) == keccak256(abi.encodePacked(_b));
        }
    }
}
