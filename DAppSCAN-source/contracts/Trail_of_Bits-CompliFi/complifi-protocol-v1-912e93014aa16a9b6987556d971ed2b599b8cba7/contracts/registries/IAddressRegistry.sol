// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

interface IAddressRegistry {
    function get(bytes32 _key) external view returns (address);

    function set(address _value) external;
}
