// SPDX-License-Identifier: AGPL-3.0-only

/*
    FieldOperationsTester.sol - SKALE Manager
    Copyright (C) 2021-Present SKALE Labs
    @author Artem Payvin

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

import "../utils/FieldOperations.sol";

interface IFieldOperationsTester {
    function add(ISkaleDKG.G2Point memory value1, ISkaleDKG.G2Point memory value2)
        external
        view
        returns (ISkaleDKG.G2Point memory);
}


contract FieldOperationsTester is IFieldOperationsTester {

    using Fp2Operations for ISkaleDKG.Fp2Point;
    using G2Operations for ISkaleDKG.G2Point;

    function add(ISkaleDKG.G2Point memory value1, ISkaleDKG.G2Point memory value2)
        external
        view
        override
        returns (ISkaleDKG.G2Point memory)
    {
        require(value1.isG2(), "First value not in G2");
        require(value2.isG2(), "Second value not in G2");
        return value1.addG2(value2);
    }
}
