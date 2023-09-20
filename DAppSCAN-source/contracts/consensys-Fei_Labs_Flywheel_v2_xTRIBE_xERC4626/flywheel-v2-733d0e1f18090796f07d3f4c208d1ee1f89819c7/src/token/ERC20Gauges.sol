// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "solmate/auth/Auth.sol";
import "solmate/tokens/ERC20.sol";
import "solmate/utils/SafeCastLib.sol";
import "../../lib/EnumerableSet.sol";
import "../interfaces/Errors.sol";

/** 
 @title  An ERC20 with an embedded "Gauge" style vote with liquid weights
 @author Tribe DAO
 @notice This contract is meant to be used to support gauge style votes with weights associated with resource allocation.
         Holders can allocate weight in any proportion to supported gauges.
         A "gauge" is represented by an address which would receive the resources periodically or continuously.

         For example, gauges can be used to direct token emissions, similar to Curve or Tokemak.
         Alternatively, gauges can be used to direct another quantity such as relative access to a line of credit.

         The contract's Authority <https://github.com/Rari-Capital/solmate/blob/main/src/auth/Auth.sol> manages the gauge set and cap.
         "Live" gauges are in the set.  
         Users can only add weight to live gauges but can remove weight from live or deprecated gauges.
         Gauges can be deprecated and reinstated, and will maintain any non-removed weight from before.

 @dev    SECURITY NOTES: `maxGauges` is a critical variable to protect against gas DOS attacks upon token transfer. 
         This must be low enough to allow complicated transactions to fit in a block.
 
         Weight state is preserved on the gauge and user level even when a gauge is removed, in case it is re-added. 
         This maintains state efficiently, and global accounting is managed only on the `_totalWeight`
*/
abstract contract ERC20Gauges is ERC20, Auth {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeCastLib for *;

    constructor(uint32 _gaugeCycleLength, uint32 _incrementFreezeWindow) {
        if (_incrementFreezeWindow >= _gaugeCycleLength) revert IncrementFreezeError();
        gaugeCycleLength = _gaugeCycleLength;
        incrementFreezeWindow = _incrementFreezeWindow;
    }

    /*///////////////////////////////////////////////////////////////
                        GAUGE STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice the length of a gauge cycle
    uint32 public immutable gaugeCycleLength;

    /// @notice the period at the end of a cycle where votes cannot increment
    uint32 public immutable incrementFreezeWindow;

    struct Weight {
        uint112 storedWeight;
        uint112 currentWeight;
        uint32 currentCycle;
    }

    /// @notice a mapping from users to gauges to a user's allocated weight to that gauge
    mapping(address => mapping(address => uint112)) public getUserGaugeWeight;

    /// @notice a mapping from a user to their total allocated weight across all gauges
    /// @dev NOTE this may contain weights for deprecated gauges
    mapping(address => uint112) public getUserWeight;

    /// @notice a mapping from a gauge to the total weight allocated to it
    /// @dev NOTE this may contain weights for deprecated gauges
    mapping(address => Weight) internal _getGaugeWeight;

    /// @notice the total global allocated weight ONLY of live gauges
    Weight internal _totalWeight;

    mapping(address => EnumerableSet.AddressSet) internal _userGauges;

    EnumerableSet.AddressSet internal _gauges;

    // Store deprecated gauges in case a user needs to free dead weight
    EnumerableSet.AddressSet internal _deprecatedGauges;

    /*///////////////////////////////////////////////////////////////
                              VIEW HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice return the end of the current cycle. This is the next unix timestamp which evenly divides `gaugeCycleLength`
    function getGaugeCycleEnd() public view returns (uint32) {
        return _getGaugeCycleEnd();
    }

    /// @notice see `getGaugeCycleEnd()`
    function _getGaugeCycleEnd() internal view returns (uint32) {
        uint32 nowPlusOneCycle = block.timestamp.safeCastTo32() + gaugeCycleLength;
        unchecked {
            return (nowPlusOneCycle / gaugeCycleLength) * gaugeCycleLength; // cannot divide by zero and always <= nowPlusOneCycle so no overflow
        }
    }

    /// @notice returns the current weight of a given gauge
    function getGaugeWeight(address gauge) public view returns (uint112) {
        return _getGaugeWeight[gauge].currentWeight;
    }

    /// @notice returns the stored weight of a given gauge. This is the snapshotted weight as-of the end of the last cycle.
    function getStoredGaugeWeight(address gauge) public view returns (uint112) {
        return _getStoredWeight(_getGaugeWeight[gauge], _getGaugeCycleEnd());
    }

    /// @notice see `getStoredGaugeWeight()`
    function _getStoredWeight(Weight storage gaugeWeight, uint32 currentCycle) internal view returns (uint112) {
        return gaugeWeight.currentCycle < currentCycle ? gaugeWeight.currentWeight : gaugeWeight.storedWeight;
    }

    /// @notice returns the current total allocated weight
    function totalWeight() external view returns (uint112) {
        return _totalWeight.currentWeight;
    }

    /// @notice returns the stored total allocated weight
    function storedTotalWeight() external view returns (uint112) {
        return _getStoredWeight(_totalWeight, _getGaugeCycleEnd());
    }

    /// @notice returns the set of live gauges
    function gauges() external view returns (address[] memory) {
        return _gauges.values();
    }

    /** 
      @notice returns a paginated subset of live gauges
      @param offset the index of the first gauge element to read
      @param num the number of gauges to return
    */
    function gauges(uint256 offset, uint256 num) external view returns (address[] memory values) {
        values = new address[](num);
        for (uint256 i = 0; i < num; ) {
            unchecked {
                values[i] = _gauges.at(offset + i); // will revert if out of bounds
                i++;
            }
        }
    }

    /// @notice returns true if `gauge` is in gauges
    function isGauge(address gauge) external view returns (bool) {
        return _gauges.contains(gauge);
    }

    /// @notice returns the number of live gauges
    function numGauges() external view returns (uint256) {
        return _gauges.length();
    }

    /// @notice returns the set of previously live but now deprecated gauges
    function deprecatedGauges() external view returns (address[] memory) {
        return _deprecatedGauges.values();
    }

    /// @notice returns the number of live gauges
    function numDeprecatedGauges() external view returns (uint256) {
        return _deprecatedGauges.length();
    }

    /// @notice returns the set of gauges the user has allocated to, may be live or deprecated.
    function userGauges(address user) external view returns (address[] memory) {
        return _userGauges[user].values();
    }

    /// @notice returns true if `gauge` is in user gauges
    function isUserGauge(address user, address gauge) external view returns (bool) {
        return _userGauges[user].contains(gauge);
    }

    /** 
      @notice returns a paginated subset of gauges the user has allocated to, may be live or deprecated.
      @param user the user to return gauges from.
      @param offset the index of the first gauge element to read.
      @param num the number of gauges to return.
    */
    function userGauges(
        address user,
        uint256 offset,
        uint256 num
    ) external view returns (address[] memory values) {
        values = new address[](num);
        for (uint256 i = 0; i < num; ) {
            unchecked {
                values[i] = _userGauges[user].at(offset + i); // will revert if out of bounds
                i++;
            }
        }
    }

    /// @notice returns the number of user gauges
    function numUserGauges(address user) external view returns (uint256) {
        return _userGauges[user].length();
    }

    /// @notice helper function exposing the amount of weight available to allocate for a user
    function userUnusedWeight(address user) external view returns (uint256) {
        return balanceOf[user] - getUserWeight[user];
    }

    /** 
     @notice helper function for calculating the proportion of a `quantity` allocated to a gauge
     @param gauge the gauge to calculate allocation of
     @param quantity a representation of a resource to be shared among all gauges
     @return the proportion of `quantity` allocated to `gauge`. Returns 0 if gauge is not live, even if it has weight.
    */
    function calculateGaugeAllocation(address gauge, uint256 quantity) external view returns (uint256) {
        if (!_gauges.contains(gauge)) return 0;
        uint32 currentCycle = _getGaugeCycleEnd();

        uint112 total = _getStoredWeight(_totalWeight, currentCycle);
        uint112 weight = _getStoredWeight(_getGaugeWeight[gauge], currentCycle);
        return (quantity * weight) / total;
    }

    /*///////////////////////////////////////////////////////////////
                        USER GAUGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when trying to increment/decrement a mismatched number of gauges and weights.
    error SizeMismatchError();

    /// @notice thrown when trying to increment over the max allowed gauges.
    error MaxGaugeError();

    /// @notice thrown when incrementing over a users free weight.
    error OverWeightError();

    /// @notice thrown when incremending during the freeze window.
    error IncrementFreezeError();

    /// @notice emitted when incrementing a gauge
    event IncrementGaugeWeight(address indexed user, address indexed gauge, uint256 weight, uint32 cycleEnd);

    /// @notice emitted when decrementing a gauge
    event DecrementGaugeWeight(address indexed user, address indexed gauge, uint256 weight, uint32 cycleEnd);

    /** 
     @notice increment a gauge with some weight for the caller
     @param gauge the gauge to increment
     @param weight the amount of weight to increment on gauge
     @return newUserWeight the new user weight
    */
    function incrementGauge(address gauge, uint112 weight) external returns (uint112 newUserWeight) {
        uint32 currentCycle = _getGaugeCycleEnd();
        _incrementGaugeWeight(msg.sender, gauge, weight, currentCycle);
        return _incrementUserAndGlobalWeights(msg.sender, weight, currentCycle);
    }

    function _incrementGaugeWeight(
        address user,
        address gauge,
        uint112 weight,
        uint32 cycle
    ) internal {
        if (!_gauges.contains(gauge)) revert InvalidGaugeError();
        unchecked {
            if (cycle - block.timestamp <= incrementFreezeWindow) revert IncrementFreezeError();
        }

        bool added = _userGauges[user].add(gauge); // idempotent add
        if (added && _userGauges[user].length() > maxGauges && !canContractExceedMaxGauges[user])
            revert MaxGaugeError();

        getUserGaugeWeight[user][gauge] += weight;

        _writeGaugeWeight(_getGaugeWeight[gauge], _add, weight, cycle);

        emit IncrementGaugeWeight(user, gauge, weight, cycle);
    }

    function _incrementUserAndGlobalWeights(
        address user,
        uint112 weight,
        uint32 cycle
    ) internal returns (uint112 newUserWeight) {
        newUserWeight = getUserWeight[user] + weight;
        // Ensure under weight
        if (newUserWeight > balanceOf[user]) revert OverWeightError();

        // Update gauge state
        getUserWeight[user] = newUserWeight;

        _writeGaugeWeight(_totalWeight, _add, weight, cycle);
    }

    /** 
     @notice increment a list of gauges with some weights for the caller
     @param gaugeList the gauges to increment
     @param weights the weights to increment by
     @return newUserWeight the new user weight
    */
    function incrementGauges(address[] calldata gaugeList, uint112[] calldata weights)
        external
        returns (uint256 newUserWeight)
    {
        uint256 size = gaugeList.length;
        if (weights.length != size) revert SizeMismatchError();

        // store total in summary for batch update on user/global state
        uint112 weightsSum;

        uint32 currentCycle = _getGaugeCycleEnd();

        // Update gauge specific state
        for (uint256 i = 0; i < size; ) {
            address gauge = gaugeList[i];
            uint112 weight = weights[i];
            weightsSum += weight;

            _incrementGaugeWeight(msg.sender, gauge, weight, currentCycle);
            unchecked {
                i++;
            }
        }
        return _incrementUserAndGlobalWeights(msg.sender, weightsSum, currentCycle);
    }

    /** 
     @notice decrement a gauge with some weight for the caller
     @param gauge the gauge to decrement
     @param weight the amount of weight to decrement on gauge
     @return newUserWeight the new user weight
    */
    function decrementGauge(address gauge, uint112 weight) external returns (uint112 newUserWeight) {
        uint32 currentCycle = _getGaugeCycleEnd();

        // All operations will revert on underflow, protecting against bad inputs
        _decrementGaugeWeight(msg.sender, gauge, weight, currentCycle);
        return _decrementUserAndGlobalWeights(msg.sender, weight, currentCycle);
    }

    function _decrementGaugeWeight(
        address user,
        address gauge,
        uint112 weight,
        uint32 cycle
    ) internal {
        uint112 oldWeight = getUserGaugeWeight[user][gauge];

        getUserGaugeWeight[user][gauge] = oldWeight - weight;
        if (oldWeight == weight) {
            // If removing all weight, remove gauge from user list.
            assert(_userGauges[user].remove(gauge));
        }

        _writeGaugeWeight(_getGaugeWeight[gauge], _subtract, weight, cycle);

        emit DecrementGaugeWeight(user, gauge, weight, cycle);
    }

    function _decrementUserAndGlobalWeights(
        address user,
        uint112 weight,
        uint32 cycle
    ) internal returns (uint112 newUserWeight) {
        newUserWeight = getUserWeight[user] - weight;

        getUserWeight[user] = newUserWeight;
        _writeGaugeWeight(_totalWeight, _subtract, weight, cycle);
    }

    /** 
     @notice decrement a list of gauges with some weights for the caller
     @param gaugeList the gauges to decrement
     @param weights the list of weights to decrement on the gauges
     @return newUserWeight the new user weight
    */
    function decrementGauges(address[] calldata gaugeList, uint112[] calldata weights)
        external
        returns (uint112 newUserWeight)
    {
        uint256 size = gaugeList.length;
        if (weights.length != size) revert SizeMismatchError();

        // store total in summary for batch update on user/global state
        uint112 weightsSum;

        uint32 currentCycle = _getGaugeCycleEnd();

        // Update gauge specific state
        // All operations will revert on underflow, protecting against bad inputs
        for (uint256 i = 0; i < size; ) {
            address gauge = gaugeList[i];
            uint112 weight = weights[i];
            weightsSum += weight;

            _decrementGaugeWeight(msg.sender, gauge, weight, currentCycle);
            unchecked {
                i++;
            }
        }
        return _decrementUserAndGlobalWeights(msg.sender, weightsSum, currentCycle);
    }

    /**
     @dev this function is the key to the entire contract.
     The storage weight it operates on is either a global or gauge-specific weight.
     The operation applied is either addition for incrementing gauges or subtraction for decrementing a gauge.
    */
    function _writeGaugeWeight(
        Weight storage weight,
        function(uint112, uint112) view returns (uint112) op,
        uint112 delta,
        uint32 cycle
    ) private {
        uint112 currentWeight = weight.currentWeight;
        // If the last cycle of the weight is before the current cycle, use the current weight as the stored.
        uint112 stored = weight.currentCycle < cycle ? currentWeight : weight.storedWeight;
        uint112 newWeight = op(currentWeight, delta);

        weight.storedWeight = stored;
        weight.currentWeight = newWeight;
        weight.currentCycle = cycle;
    }

    function _add(uint112 a, uint112 b) private pure returns (uint112) {
        return a + b;
    }

    function _subtract(uint112 a, uint112 b) private pure returns (uint112) {
        return a - b;
    }

    /*///////////////////////////////////////////////////////////////
                        ADMIN GAUGE OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice thrown when trying to increment or remove a non-live gauge, or add a live gauge.
    error InvalidGaugeError();

    /// @notice emitted when adding a new gauge to the live set.
    event AddGauge(address indexed gauge);

    /// @notice emitted when removing a gauge from the live set.
    event RemoveGauge(address indexed gauge);

    /// @notice emitted when updating the max number of gauges a user can delegate to.
    event MaxGaugesUpdate(uint256 oldMaxGauges, uint256 newMaxGauges);

    /// @notice emitted when changing a contract's approval to go over the max gauges.
    event CanContractExceedMaxGaugesUpdate(address indexed account, bool canContractExceedMaxGauges);

    /// @notice the default maximum amount of gauges a user can allocate to.
    uint256 public maxGauges;

    /// @notice an approve list for contracts to go above the max gauge limit.
    mapping(address => bool) public canContractExceedMaxGauges;

    /// @notice add a new gauge. Requires auth by `authority`.
    function addGauge(address gauge) external requiresAuth {
        _addGauge(gauge);
    }

    function _addGauge(address gauge) internal {
        // add and fail loud if already present or zero address
        if (gauge == address(0) || !_gauges.add(gauge)) revert InvalidGaugeError();
        _deprecatedGauges.remove(gauge); // silently remove gauge from deprecated if present

        uint32 currentCycle = _getGaugeCycleEnd();

        // Check if some previous weight exists and re-add to total. Gauge and user weights are preserved.
        uint112 weight = _getGaugeWeight[gauge].currentWeight;
        if (weight > 0) {
            _writeGaugeWeight(_totalWeight, _add, weight, currentCycle);
        }

        emit AddGauge(gauge);
    }

    /// @notice remove a new gauge. Requires auth by `authority`.
    function removeGauge(address gauge) external requiresAuth {
        _removeGauge(gauge);
    }

    function _removeGauge(address gauge) internal {
        // remove and fail loud if not present
        if (!_gauges.remove(gauge)) revert InvalidGaugeError();
        _deprecatedGauges.add(gauge); // add gauge to deprecated. Must not be present if previously in live set.

        uint32 currentCycle = _getGaugeCycleEnd();

        // Remove weight from total but keep the gauge and user weights in storage in case gauge is re-added.
        uint112 weight = _getGaugeWeight[gauge].currentWeight;
        if (weight > 0) {
            _writeGaugeWeight(_totalWeight, _subtract, weight, currentCycle);
        }

        emit RemoveGauge(gauge);
    }

    /// @notice replace a gauge. Requires auth by `authority`.
    function replaceGauge(address oldGauge, address newGauge) external requiresAuth {
        _removeGauge(oldGauge);
        _addGauge(newGauge);
    }

    /// @notice set the new max gauges. Requires auth by `authority`.
    // SWC-110-Assert Violation: L500-L505
    function setMaxGauges(uint256 newMax) external requiresAuth {
        uint256 oldMax = maxGauges;
        maxGauges = newMax;

        emit MaxGaugesUpdate(oldMax, newMax);
    }

    /// @notice set the canContractExceedMaxGauges flag for an account.
    function setContractExceedMaxGauges(address account, bool canExceedMax) external requiresAuth {
        if (canExceedMax && account.code.length == 0) revert Errors.NonContractError(); // can only approve contracts

        canContractExceedMaxGauges[account] = canExceedMax;

        emit CanContractExceedMaxGaugesUpdate(account, canExceedMax);
    }

    /*///////////////////////////////////////////////////////////////
                             ERC20 LOGIC
    //////////////////////////////////////////////////////////////*/

    /// NOTE: any "removal" of tokens from a user requires userUnusedWeight < amount.
    /// _decrementWeightUntilFree is called as a greedy algorithm to free up weight.
    /// It may be more gas efficient to free weight before burning or transferring tokens.

    function _burn(address from, uint256 amount) internal virtual override {
        _decrementWeightUntilFree(from, amount);
        super._burn(from, amount);
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        _decrementWeightUntilFree(msg.sender, amount);
        return super.transfer(to, amount);
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        _decrementWeightUntilFree(from, amount);
        return super.transferFrom(from, to, amount);
    }

    /// a greedy algorithm for freeing weight before a token burn/transfer
    /// frees up entire gauges, so likely will free more than `weight`
    function _decrementWeightUntilFree(address user, uint256 weight) internal {
        uint256 userFreeWeight = balanceOf[user] - getUserWeight[user];

        // early return if already free
        if (userFreeWeight >= weight) return;

        uint32 currentCycle = _getGaugeCycleEnd();

        // cache totals for batch updates
        uint112 userFreed;
        uint112 totalFreed;

        // Loop through all user gauges, live and deprecated
        address[] memory gaugeList = _userGauges[user].values();

        // Free gauges until through entire list or under weight
        uint256 size = gaugeList.length;
        for (uint256 i = 0; i < size && (userFreeWeight + totalFreed) < weight; ) {
            address gauge = gaugeList[i];
            uint112 userGaugeWeight = getUserGaugeWeight[user][gauge];
            if (userGaugeWeight != 0) {
                // If the gauge is live (not deprecated), include its weight in the total to remove
                if (_gauges.contains(gauge)) {
                    totalFreed += userGaugeWeight;
                }
                userFreed += userGaugeWeight;
                _decrementGaugeWeight(user, gauge, userGaugeWeight, currentCycle);

                unchecked {
                    i++;
                }
            }
        }

        getUserWeight[user] -= userFreed;
        _writeGaugeWeight(_totalWeight, _subtract, totalFreed, currentCycle);
    }
}
