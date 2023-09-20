// SPDX-License-Identifier: NO LICENSE
pragma solidity 0.7.6;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract SHEESHA is ERC20Burnable, Ownable {
    using SafeMath for uint256;
//SWC-131-Presence of unused variables:L13-16
    //100,000 tokens
    uint256 public constant initialSupply = 100000e18;
    address public devAddress;
    address public teamAddress;
    address public marketingAddress;
    address public reserveAddress;

    // 15% team (4% monthly unlock over 25 months)
    // 10% dev
    // 10% marketing
    // 15% liquidity provision
    // 10% SHEESHA staking rewards
    // 20% LP rewards
    // 20% Reserve

    constructor(address _devAddress, address _marketingAddress, address _teamAddress, address _reserveAddress) ERC20("Sheesha Finance", "SHEESHA") {
        devAddress = _devAddress;
        marketingAddress = _marketingAddress;
        teamAddress = _teamAddress;
        reserveAddress = _reserveAddress;
        _mint(address(this), initialSupply);
        _transfer(address(this), devAddress, initialSupply.mul(10).div(100));
        _transfer(address(this), teamAddress, initialSupply.mul(15).div(100));
        _transfer(address(this), marketingAddress, initialSupply.mul(10).div(100));
        _transfer(address(this), reserveAddress, initialSupply.mul(20).div(100));
    }

    //one time only
    function transferVaultRewards(address _vaultAddress) public onlyOwner {
        _transfer(address(this), _vaultAddress, initialSupply.mul(10).div(100));
    }
//SWC-129-Typographical Error:L44
    //one time only
    function transferVaultLPewards(address _vaultLPAddress) public onlyOwner {
        _transfer(address(this), _vaultLPAddress, initialSupply.mul(20).div(100));
    }
}