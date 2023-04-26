// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract DBTC is Initializable, OwnableUpgradeable, ERC20Upgradeable {

  mapping(address => bool) public miners;

  event MinerChanged(address indexed miner, bool enabled);

  function initialize() public initializer {
    __Context_init_unchained();
    __Ownable_init_unchained();
    __ERC20_init_unchained("Mock Duet BTC", "DBTC");
  }

  function addMiner(address _miner) public onlyOwner {
    miners[_miner] = true;
    emit MinerChanged(_miner, true);
  }

  function mint(address account, uint256 amount) public {
    require(miners[msg.sender], "invalid miner");
    _mint(account, amount);
  }

  function burnFrom(address account, uint256 amount) public onlyOwner {
    _burn(account, amount);
  }

  function burn(uint256 amount) public {
    _burn(msg.sender, amount);
  }
}