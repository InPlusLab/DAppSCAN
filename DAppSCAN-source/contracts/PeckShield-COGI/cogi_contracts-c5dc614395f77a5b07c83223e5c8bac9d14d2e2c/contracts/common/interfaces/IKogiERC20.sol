// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

/**
 * @title KOGI Token
 * @author KOGI Inc
 */

interface IKogiERC20 {
    
    //admin view
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function mintFrom(address to, uint256 amount) external;
    function mint(uint256 amount) external;
    function burnFrom(address to, uint256 amount) external;
    function addMinter(address account) external;
    function removeMinter(address account) external;
    function pause() external;
    function unpause() external;
    function freeze(address account) external;
    function unfreeze(address account) external;
    function approve(address spender, uint256 amount) external returns (bool);

    //anon view
    function burn(uint256 amount) external;
    function balanceOf(address _account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function maxSupply() external view returns (uint256);
}
