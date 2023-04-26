// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// refer https://hecoinfo.com/address/0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F#code

interface IWHT {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function balanceOf(address guy) external view returns (uint);

    function deposit() external payable;
    function withdraw(uint wad) external;

    function totalSupply() external view returns (uint);
    function approve(address guy, uint wad) external returns (bool);
    function transfer(address dst, uint wad) external returns (bool);
    function transferFrom(address src, address dst, uint wad) external returns (bool);
}