// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.6.12;

import "./balancer-core/BPool.sol";
import "./interfaces/MatrixPoolInterface.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";

contract MatrixPool is BPool, Initializable {
    /// @notice The event emitted when a dynamic weight set to token.
    event SetDynamicWeight(
        address indexed token,
        uint256 fromDenorm,
        uint256 targetDenorm,
        uint256 fromTimestamp,
        uint256 targetTimestamp
    );

    /// @notice The event emitted when weight per second bounds set.
    event SetWeightPerSecondBounds(uint256 minWeightPerSecond, uint256 maxWeightPerSecond);

    struct DynamicWeight {
        uint256 fromTimestamp;
        uint256 targetTimestamp;
        uint256 targetDenorm;
    }

    /// @dev Mapping for storing dynamic weights settings. fromDenorm stored in _records mapping as denorm variable.
    mapping(address => DynamicWeight) private _dynamicWeights;

    /// @dev Min weight per second limit.
    uint256 private _minWeightPerSecond;
    /// @dev Max weight per second limit.
    uint256 private _maxWeightPerSecond;

    constructor() public BPool("", "") {}

    function initialize(
        string calldata name,
        string calldata symbol,
        address controller,
        uint256 minWeightPerSecond,
        uint256 maxWeightPerSecond
    ) external initializer {
        _name = name;
        _symbol = symbol;
        _controller = controller;
        _minWeightPerSecond = minWeightPerSecond;
        _maxWeightPerSecond = maxWeightPerSecond;
    }

    /*** Controller Interface ***/

    /**
     * @notice Set minimum and maximum weight per second by controller.
     * @param minWeightPerSecond Minimum weight per second.
     * @param maxWeightPerSecond Maximum weight per second.
     */
    function setWeightPerSecondBounds(uint256 minWeightPerSecond, uint256 maxWeightPerSecond) public _logs_ _lock_ {
        _onlyController();
        _minWeightPerSecond = minWeightPerSecond;
        _maxWeightPerSecond = maxWeightPerSecond;

        emit SetWeightPerSecondBounds(minWeightPerSecond, maxWeightPerSecond);
    }

    /**
     * @notice Set dynamic weight for token by controller contract.
     * @param token Token to change weight.
     * @param targetDenorm Target weight. fromDenorm will fetch from current value of _getDenormWeight.
     * @param fromTimestamp Start timestamp for changing weight.
     * @param targetTimestamp Target timestamp for changing weight.
     */
    function setDynamicWeight(
        address token,
        uint256 targetDenorm,
        uint256 fromTimestamp,
        uint256 targetTimestamp
    ) public _logs_ _lock_ {
        _onlyController();
        _requireTokenIsBound(token);

        require(fromTimestamp > block.timestamp, "CANT_SET_PAST_TIMESTAMP");
        require(targetTimestamp > fromTimestamp, "TIMESTAMP_INCORRECT_DELTA");
        require(targetDenorm >= MIN_WEIGHT && targetDenorm <= MAX_WEIGHT, "TARGET_WEIGHT_BOUNDS");

        uint256 fromDenorm = _getDenormWeight(token);
        uint256 weightPerSecond = _getWeightPerSecond(fromDenorm, targetDenorm, fromTimestamp, targetTimestamp);
        require(weightPerSecond <= _maxWeightPerSecond, "MAX_WEIGHT_PER_SECOND");
        require(weightPerSecond >= _minWeightPerSecond, "MIN_WEIGHT_PER_SECOND");

        _records[token].denorm = fromDenorm;

        _dynamicWeights[token] = DynamicWeight({
        fromTimestamp : fromTimestamp,
        targetTimestamp : targetTimestamp,
        targetDenorm : targetDenorm
        });

        uint256 denormSum = 0;
        uint256 len = _tokens.length;
        for (uint256 i = 0; i < len; i++) {
            denormSum = badd(denormSum, _dynamicWeights[_tokens[i]].targetDenorm);
        }

        require(denormSum <= MAX_TOTAL_WEIGHT, "MAX_TARGET_TOTAL_WEIGHT");

        emit SetDynamicWeight(token, fromDenorm, targetDenorm, fromTimestamp, targetTimestamp);
    }

    /**
     * @notice Bind and setDynamicWeight at the same time.
     * @param token Token for bind.
     * @param balance Initial token balance.
     * @param targetDenorm Target weight.
     * @param fromTimestamp Start timestamp to change weight.
     * @param targetTimestamp Target timestamp to change weight.
     */
    function bind(
        address token,
        uint256 balance,
        uint256 targetDenorm,
        uint256 fromTimestamp,
        uint256 targetTimestamp
    )
    external
    _logs_ // _lock_  Bind does not lock because it jumps to `rebind` and `setDynamicWeight`, which does
    {
        super.bind(token, balance, MIN_WEIGHT);

        setDynamicWeight(token, targetDenorm, fromTimestamp, targetTimestamp);
    }

    /**
     * @dev Override parent unbind function.
     * @param token Token for unbind.
     */
    function unbind(address token) public override {
        super.unbind(token);

        _dynamicWeights[token] = DynamicWeight(0, 0, 0);
    }

    /**
     * @dev Override parent bind function and disable.
     */
    function bind(
        address token,
        uint256 balance,
        uint256 denorm
    ) public override {
        super.bind(token, balance, denorm);
    }

    /**
     * @notice Override parent rebind function. Allowed only for calling from bind function.
     * @param token Token for rebind.
     * @param balance Balance for rebind.
     * @param denorm Weight for rebind.
     */
    function rebind(
        address token,
        uint256 balance,
        uint256 denorm
    ) public override {
        super.rebind(token, balance, denorm);
        _dynamicWeights[token].fromTimestamp = 0;
        _dynamicWeights[token].targetTimestamp = 0;
        _dynamicWeights[token].targetDenorm = 0;
    }

    /*** View Functions ***/

    function getDynamicWeightSettings(address token)
    external
    view
    returns (
        uint256 fromTimestamp,
        uint256 targetTimestamp,
        uint256 fromDenorm,
        uint256 targetDenorm
    )
    {
        DynamicWeight storage dw = _dynamicWeights[token];
        return (dw.fromTimestamp, dw.targetTimestamp, _records[token].denorm, dw.targetDenorm);
    }

    function getWeightPerSecondBounds() external view returns (uint256 minWeightPerSecond, uint256 maxWeightPerSecond) {
        return (_minWeightPerSecond, _maxWeightPerSecond);
    }

    /*** Internal Functions ***/

    function _getDenormWeight(address token) internal view override returns (uint256) {
        DynamicWeight memory dw = _dynamicWeights[token];
        uint256 fromDenorm = _records[token].denorm;

        if (dw.fromTimestamp == 0 || dw.targetDenorm == fromDenorm || block.timestamp <= dw.fromTimestamp) {
            return fromDenorm;
        }
        if (block.timestamp >= dw.targetTimestamp) {
            return dw.targetDenorm;
        }

        uint256 weightPerSecond = _getWeightPerSecond(fromDenorm, dw.targetDenorm, dw.fromTimestamp, dw.targetTimestamp);
        uint256 deltaCurrentTime = bsub(block.timestamp, dw.fromTimestamp);
        if (dw.targetDenorm > fromDenorm) {
            return badd(fromDenorm, deltaCurrentTime * weightPerSecond);
        } else {
            return bsub(fromDenorm, deltaCurrentTime * weightPerSecond);
        }
    }

    function _getWeightPerSecond(
        uint256 fromDenorm,
        uint256 targetDenorm,
        uint256 fromTimestamp,
        uint256 targetTimestamp
    ) internal pure returns (uint256) {
        uint256 delta = targetDenorm > fromDenorm ? bsub(targetDenorm, fromDenorm) : bsub(fromDenorm, targetDenorm);
        return div(delta, bsub(targetTimestamp, fromTimestamp));
    }

    function _getTotalWeight() internal view override returns (uint256) {
        uint256 sum = 0;
        uint256 len = _tokens.length;
        for (uint256 i = 0; i < len; i++) {
            sum = badd(sum, _getDenormWeight(_tokens[i]));
        }
        return sum;
    }

    function _addTotalWeight(uint256 _amount) internal virtual override {
        // storage total weight don't change, it's calculated only by _getTotalWeight()
    }

    function _subTotalWeight(uint256 _amount) internal virtual override {
        // storage total weight don't change, it's calculated only by _getTotalWeight()
    }
}
