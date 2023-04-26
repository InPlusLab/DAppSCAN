// SPDX-License-Identifier: AGPL-3.0-only

/*
    PartialDifferencesTester.sol - SKALE Manager
    Copyright (C) 2018-Present SKALE Labs
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

import "../delegation/PartialDifferences.sol";

interface IPartialDifferencesTester {
    function createSequence() external;
    function addToSequence(uint sequence, uint diff, uint month) external;
    function subtractFromSequence(uint sequence, uint diff, uint month) external;
    function getAndUpdateSequenceItem(uint sequence, uint month) external returns (uint);
    function reduceSequence(
        uint sequence,
        uint a,
        uint b,
        uint month
    ) external;
    function latestSequence() external view returns (uint id);
}


contract PartialDifferencesTester is IPartialDifferencesTester {
    using PartialDifferences for PartialDifferences.Sequence;
    using PartialDifferences for PartialDifferences.Value;

    PartialDifferences.Sequence[] private _sequences;
    // PartialDifferences.Value[] private _values;

    function createSequence() external override {
        _sequences.push();
    }

    function addToSequence(uint sequence, uint diff, uint month) external override {
        require(sequence < _sequences.length, "Sequence does not exist");
        _sequences[sequence].addToSequence(diff, month);
    }

    function subtractFromSequence(uint sequence, uint diff, uint month) external override {
        require(sequence < _sequences.length, "Sequence does not exist");
        _sequences[sequence].subtractFromSequence(diff, month);
    }

    function getAndUpdateSequenceItem(uint sequence, uint month) external override returns (uint) {
        require(sequence < _sequences.length, "Sequence does not exist");
        return _sequences[sequence].getAndUpdateValueInSequence(month);
    }

    function reduceSequence(
        uint sequence,
        uint a,
        uint b,
        uint month
    )
        external
        override
    {
        require(sequence < _sequences.length, "Sequence does not exist");
        FractionUtils.Fraction memory reducingCoefficient = FractionUtils.createFraction(a, b);
        return _sequences[sequence].reduceSequence(reducingCoefficient, month);
    }

    function latestSequence() external view override returns (uint id) {
        require(_sequences.length > 0, "There are no _sequences");
        return _sequences.length - 1;
    }
}