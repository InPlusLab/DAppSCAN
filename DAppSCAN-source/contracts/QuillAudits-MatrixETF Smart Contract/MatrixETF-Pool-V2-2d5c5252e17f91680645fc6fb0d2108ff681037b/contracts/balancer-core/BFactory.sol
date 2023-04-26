// SPDX-License-Identifier: GPL-3.0
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is disstributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.12;

// Builds new BPools, logging their addresses and providing `isBPool(address) -> (bool)`

import "./BPool.sol";

contract BFactory {
    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool
    );

    mapping(address => bool) public isBPool;

    constructor() public { }

    function newBPool(string calldata name, string calldata symbol)
        external
        returns (BPool)
    {
        BPool bpool = new BPool(name, symbol);
        isBPool[address(bpool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(bpool));
        bpool.setController(msg.sender);
        return bpool;
    }
}
