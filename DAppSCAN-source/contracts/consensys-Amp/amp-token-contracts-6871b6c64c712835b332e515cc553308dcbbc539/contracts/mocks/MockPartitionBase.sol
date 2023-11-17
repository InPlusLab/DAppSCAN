// SPDX-License-Identifier: MIT

pragma solidity 0.6.9;

import "../erc1820/ERC1820Client.sol";
import "../partitions/PartitionsBase.sol";


contract MockPartitionBase is ERC1820Client, PartitionsBase {
    function getAmpPartitionStrategyImplementer(bytes4 _prefix, address _amp)
        external
        view
        returns (address)
    {
        string memory iname = _getPartitionStrategyValidatorIName(_prefix);
        return ERC1820Client.interfaceAddr(_amp, iname);
    }
}
