// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;

import "../erc1820/ERC1820Client.sol";
import "../erc1820/ERC1820Implementer.sol";

import "./PartitionsBase.sol";
import "./IAmpPartitionStrategyValidator.sol";


/**
 * @title Base contract that satisfies the IAmpPartitionStrategyValidator
 * interface
 */
contract AmpPartitionStrategyValidatorBase is
    PartitionsBase,
    IAmpPartitionStrategyValidator,
    ERC1820Client,
    ERC1820Implementer
{
    /**
     * @notice Partition prefix the hooks are valid for.
     * @dev Must to be set by the parent contract.
     */
    bytes4 public partitionPrefix;

    /**
     * @notice Amp contract address.
     */
    address public amp;

    /**
     * @notice Initialize the partition prefix and register the implementaiton
     * with the ERC1820 registry for the dynamic interface name.
     * @param _prefix Partition prefix the hooks are valid for.
     * @param _amp The address of the Amp contract.
     */
    constructor(bytes4 _prefix, address _amp) public {
        partitionPrefix = _prefix;

        string memory iname = _getPartitionStrategyValidatorIName(partitionPrefix);
        ERC1820Implementer._setInterface(iname);

        amp = _amp;
    }

    /**
     * @dev Placeholder to satisfy IAmpPartitionSpaceValidator interface that
     * can be overridden by parent.
     */
    function tokensFromPartitionToValidate(
        bytes4, /* functionSig */
        bytes32, /* fromPartition */
        address, /* operator */
        address, /* from */
        address, /* to */
        uint256, /* value */
        bytes calldata, /* data */
        bytes calldata /* operatorData */
    ) external virtual override {}

    /**
     * @dev Placeholder to satisfy IAmpPartitionSpaceValidator interface that
     * can be overridden by parent.
     */
    function tokensToPartitionToValidate(
        bytes4, /* functionSig */
        bytes32, /* fromPartition */
        address, /* operator */
        address, /* from */
        address, /* to */
        uint256, /* value */
        bytes calldata, /* data */
        bytes calldata /* operatorData */
    ) external virtual override {}

    /**
     * @notice Report if address is an operator for a partition based on the
     * partition's strategy.
     * @dev Placeholder that can be overriden by parent.
     */
    function isOperatorForPartitionScope(
        bytes32, /* partition */
        address, /* operator */
        address /* tokenHolder */
    ) external virtual override view returns (bool) {
        return false;
    }
}
