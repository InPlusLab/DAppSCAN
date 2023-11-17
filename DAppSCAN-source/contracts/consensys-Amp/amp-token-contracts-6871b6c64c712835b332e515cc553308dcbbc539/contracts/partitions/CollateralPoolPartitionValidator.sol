// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;

import "./AmpPartitionStrategyValidatorBase.sol";


interface IAmp {
    function isCollateralManager(address) external view returns (bool);
}


/**
 * @title CollateralPoolPartitionValidator
 */
contract CollateralPoolPartitionValidator is AmpPartitionStrategyValidatorBase {
    bytes4 constant PARTITION_PREFIX = 0xCCCCCCCC;

    constructor(address _amp)
        public
        AmpPartitionStrategyValidatorBase(PARTITION_PREFIX, _amp)
    {}

    /**
     * @notice Reports if the token holder is an operator for the partition.
     * @dev The `_operator` address param is unused. For this strategy, this will
     * be being called on behalf of suppliers, as they have sent their tokens
     * to the collateral manager address, and are now trying to execute a
     * transfer from the pool. This implies that the pool sender hook
     * MUST be implemented in such a way as to restrict any unauthorized
     * transfers, as the partitions affected by this strategy will allow
     * all callers to make an attempt to transfer from the collateral
     * managers partition.
     * @param _partition The partition to check.
     * @param _tokenHolder The collateral manager holding the pool of tokens.
     * @return The operator check for this strategy returns true if the partition
     * owner (identified by the final 20 bytes of the partition) is the
     * same as the token holder address, as in this case the token holder
     * is the collateral manager address.
     */
    function isOperatorForPartitionScope(
        bytes32 _partition,
        address, /* operator */
        address _tokenHolder
    ) external override view returns (bool) {
        require(msg.sender == address(amp), "Hook must be called by amp");

        (, , address partitionOwner) = _splitPartition(_partition);
        if (!IAmp(amp).isCollateralManager(partitionOwner)) {
            return false;
        }

        return _tokenHolder == partitionOwner;
    }

    /**
     * @notice Validate the rules of the strategy when tokens are being sent to
     * a partition under the purview of the strategy.
     * @dev The `_toPartition` must be formatted with the PARTITION_PREFIX as the
     * first 4 bytes, the `_to` value as the final 20 bytes. The 8 bytes in the
     * middle can be used by the manager to create sub partitions within their
     * impelemntation.
     * @param _toPartition The partition the tokens are transferred to.
     * @param _to The address of the collateral manager.
     */
    function tokensToPartitionToValidate(
        bytes4, /* functionSig */
        bytes32 _toPartition,
        address, /* operator */
        address, /* from */
        address _to,
        uint256, /* value */
        bytes calldata, /* _data */
        bytes calldata /* operatorData */
    ) external override {
        require(msg.sender == address(amp), "Hook must be called by amp");

        (, , address toPartitionOwner) = _splitPartition(_toPartition);

        require(
            _to == toPartitionOwner,
            "Transfers to this partition must be to the partitionOwner"
        );
        require(
            IAmp(amp).isCollateralManager(toPartitionOwner),
            "Partition owner is not a registered collateral manager"
        );
    }
}
