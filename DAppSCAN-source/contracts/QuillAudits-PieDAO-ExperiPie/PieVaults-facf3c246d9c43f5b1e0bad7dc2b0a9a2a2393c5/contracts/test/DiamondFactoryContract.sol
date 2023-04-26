// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import "diamond-2/contracts/Diamond.sol";

contract DiamondFactoryContract {
    event DiamondCreated(address tokenAddress);

    address[] public diamonds;
    mapping(address => bool) public isDiamond;

    function deployNewDiamond(
        address _owner,
        IDiamondCut.FacetCut[] memory _diamondCut
    ) public returns (address) {
        Diamond d = new Diamond(_diamondCut, _owner);

        diamonds.push(address(d));
        isDiamond[address(d)] = true;

        emit DiamondCreated(address(d));
    }

    function getDiamondCount() external view returns (uint256) {
        return diamonds.length;
    }
}
