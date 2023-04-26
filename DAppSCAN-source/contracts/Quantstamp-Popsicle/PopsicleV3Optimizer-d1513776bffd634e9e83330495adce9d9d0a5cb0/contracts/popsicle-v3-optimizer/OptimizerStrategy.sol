// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "./interfaces/IOptimizerStrategy.sol";

/// @title Permissioned Optimizer variables
/// @notice Contains Optimizer variables that may only be called by the governance
contract OptimizerStrategy is IOptimizerStrategy {

    /// @inheritdoc IOptimizerStrategy
    uint256 public override maxTotalSupply;
    // Address of the Optimizer's strategy owner
    address public governance;
    // Pending to claim ownership address
    address public pendingGovernance;

    /// @inheritdoc IOptimizerStrategy
    uint32 public override twapDuration;
    /// @inheritdoc IOptimizerStrategy
    int24 public override maxTwapDeviation;
    /// @inheritdoc IOptimizerStrategy
    int24 public override tickRangeMultiplier;
    /// @inheritdoc IOptimizerStrategy
    uint24 public override priceImpactPercentage;
    
    event TransferGovernance(address indexed previousGovernance, address indexed newGovernance);
    
    /**
     * @param _twapDuration TWAP duration in seconds for rebalance check
     * @param _maxTwapDeviation Max deviation from TWAP during rebalance
     * @param _tickRangeMultiplier Used to determine base order range
     * @param _priceImpactPercentage The price impact percentage during swap in hundredths of a bip, i.e. 1e-6
     * @param _maxTotalSupply Maximul PLP value that could be minted
     */
    constructor(
        uint32 _twapDuration,
        int24 _maxTwapDeviation,
        int24 _tickRangeMultiplier,
        uint24 _priceImpactPercentage,
        uint256 _maxTotalSupply
    ) {
        twapDuration = _twapDuration;
        maxTwapDeviation = _maxTwapDeviation;
        tickRangeMultiplier = _tickRangeMultiplier;
        priceImpactPercentage = _priceImpactPercentage;
        maxTotalSupply = _maxTotalSupply;
        governance = msg.sender;

        require(_maxTwapDeviation >= 20, "maxTwapDeviation");
        require(_twapDuration >= 100, "twapDuration");
        require(_priceImpactPercentage < 1e6 && _priceImpactPercentage > 0, "PIP");
        require(maxTotalSupply > 0, "maxTotalSupply");
    }

    modifier onlyGovernance {
        require(msg.sender == governance, "NOT ALLOWED");
        _;
    }

    function setMaxTotalSupply(uint256 _maxTotalSupply) external onlyGovernance {
        require(_maxTotalSupply > 0, "maxTotalSupply");
        maxTotalSupply = _maxTotalSupply;
    }

    function setTwapDuration(uint32 _twapDuration) external onlyGovernance {
        require(_twapDuration >= 100, "twapDuration");
        twapDuration = _twapDuration;
    }

    function setMaxTwapDeviation(int24 _maxTwapDeviation) external onlyGovernance {
        require(_maxTwapDeviation >= 20, "PF");
        maxTwapDeviation = _maxTwapDeviation;
    }

    function setTickRange(int24 _tickRangeMultiplier) external onlyGovernance {
        tickRangeMultiplier = _tickRangeMultiplier;
    }

    function setPriceImpact(uint16 _priceImpactPercentage) external onlyGovernance {
        require(_priceImpactPercentage < 1e6 && _priceImpactPercentage > 0, "PIP");
        priceImpactPercentage = _priceImpactPercentage;
    }

    
     /**
     * @notice `setGovernance()` should be called by the existing governance
     * address prior to calling this function.
     */
    function setGovernance(address _governance) external onlyGovernance {
        pendingGovernance = _governance;
    }

    /**
     * @notice Governance address is not updated until the new governance
     * address has called `acceptGovernance()` to accept this responsibility.
     */
    function acceptGovernance() external {
        require(msg.sender == pendingGovernance, "PG");
        emit TransferGovernance(governance, pendingGovernance);
        pendingGovernance = address(0);
        governance = msg.sender;
    }
}
