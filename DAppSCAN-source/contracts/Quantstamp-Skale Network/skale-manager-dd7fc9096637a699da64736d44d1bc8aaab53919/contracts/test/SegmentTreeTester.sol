// SPDX-License-Identifier: AGPL-3.0-only

/*
    SegmentTreeTester.sol - SKALE Manager
    Copyright (C) 2021-Present SKALE Labs
    @author Artem Payvin
    @author Dmytro Stebaiev

    SKALE Manager is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    SKALE Manager is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with SKALE Manager.  If not, see <https://www.gnu.org/licenses/>.
*/

pragma solidity 0.8.11;

import "../utils/SegmentTree.sol";

interface ISegmentTreeTester {
    function initTree() external;
    function addElemInPlaces(uint place, uint elem) external;
    function addToLast(uint elem) external;
    function addToPlace(uint place, uint elem) external;
    function removeFromPlace(uint place, uint elem) external;
    function moveFromPlaceToPlace(uint fromPlace, uint toPlace, uint elem) external;
    function sumFromPlaceToLast(uint place) external view returns (uint);
    function getRandomElem(uint place) external view returns (uint);
    function getElem(uint index) external view returns (uint);
    function getSize() external view returns (uint);
}


contract SegmentTreeTester is ISegmentTreeTester {

    using SegmentTree for SegmentTree.Tree;

    SegmentTree.Tree private _tree;

    uint[129] private _places;

    function initTree() external override {
        _tree.create(128);
        for (uint8 i = 1; i <= 128; i++) {
            if (_places[i] > 0)
                _tree.addToPlace(i, _places[i]);
        }
    }

    function addElemInPlaces(uint place, uint elem) external override {
        _places[place] = elem;
    }

    function addToLast(uint elem) external override {
        _tree.addToPlace(_tree.getSize(), elem);
    }

    function addToPlace(uint place, uint elem) external override {
        _tree.addToPlace(place, elem);
    }

    function removeFromPlace(uint place, uint elem) external override {
        _tree.removeFromPlace(place, elem);
    }

    function moveFromPlaceToPlace(uint fromPlace, uint toPlace, uint elem) external override {
        _tree.moveFromPlaceToPlace(fromPlace, toPlace, elem);
    }

    function sumFromPlaceToLast(uint place) external view override returns (uint) {
        return _tree.sumFromPlaceToLast(place);
    }

    function getRandomElem(uint place) external view override returns (uint) {
        IRandom.RandomGenerator memory randomGenerator = Random.createFromEntropy(
            abi.encodePacked(uint(blockhash(block.number - 1)), place)
        );
        return _tree.getRandomNonZeroElementFromPlaceToLast(place, randomGenerator);
    }

    function getElem(uint index) external view override returns (uint) {
        require(index < _tree.tree.length, "Incorrect index");
        return _tree.tree[index];
    }

    function getSize() external view override returns (uint) {
        return _tree.getSize();
    }
}
