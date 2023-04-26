// SPDX-License-Identifier: AGPL-3.0-only

/*
    SkaleTokenInternalTester.sol - SKALE Manager
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

import "../SkaleToken.sol";

interface ISkaleTokenInterfaceTester {
    function getMsgData() external view returns (bytes memory);
}


contract SkaleTokenInternalTester is SkaleToken, ISkaleTokenInterfaceTester {

    constructor(address contractManagerAddress, address[] memory defOps)
    SkaleToken(contractManagerAddress, defOps)
    // solhint-disable-next-line no-empty-blocks
    { }

    function getMsgData() external view override returns (bytes memory) {
        return _msgData();
    }
}
