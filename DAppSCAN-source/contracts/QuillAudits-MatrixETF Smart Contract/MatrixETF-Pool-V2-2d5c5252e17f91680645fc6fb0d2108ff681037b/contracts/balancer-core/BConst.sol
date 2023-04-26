// SPDX-License-Identifier: GPL-3.0
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.12;

contract BConst {
    uint public constant BONE              = 10**18;
    // Minimum number of tokens in the pool
    uint public constant MIN_BOUND_TOKENS  = 2;
    // Maximum number of tokens in the pool
    uint public constant MAX_BOUND_TOKENS  = 21;
    // Minimum swap fee
    uint public constant MIN_FEE           = BONE / 10**6;
    // Maximum swap fee
    uint public constant MAX_FEE           = BONE / 10;
    // Minimum weight for token
    uint public constant MIN_WEIGHT        = 1000000000;
    // Maximum weight for token
    uint public constant MAX_WEIGHT        = BONE * 50;
    // Maximum total weight
    uint public constant MAX_TOTAL_WEIGHT  = BONE * 50;
    // Minimum balance for a token
    uint public constant MIN_BALANCE       = BONE / 10**12;
    // Initial pool tokens supply
    uint public constant INIT_POOL_SUPPLY  = BONE * 100;

    uint public constant MIN_BPOW_BASE     = 1 wei;
    uint public constant MAX_BPOW_BASE     = (2 * BONE) - 1 wei;
    uint public constant BPOW_PRECISION    = BONE / 10**10;
    // Maximum input tokens balance ratio for swaps.
    uint public constant MAX_IN_RATIO      = BONE / 2;
    // Maximum output tokens balance ratio for swaps.
    uint public constant MAX_OUT_RATIO     = (BONE / 3) + 1 wei;
}
