// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

contract WETHMock {
    function deposit() external payable {}

    function approve(address guy, uint256 wad) public returns (bool) {}
}
