// SPDX-License-Identifier: MIT

pragma solidity >=0.5.0;

interface ISwapAdapter {

    function sellBase(address to, address pool, bytes memory data) external;

    function sellQuote(address to, address pool, bytes memory data) external;
}