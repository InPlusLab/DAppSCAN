// SPDX-License-Identifier: Apache-2.0

pragma solidity ^0.8.0;

interface IStablecoin {
    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

    function burnFrom(address account, uint256 amount) external;

    function mintFromVault(address factory, uint256 vaultId_, address to, uint256 amount) external;

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}
