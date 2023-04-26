// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MooMonsterToken is ERC20, ERC20Snapshot, Ownable {
  uint256 public constant MAX_SUPPLY = 170_000_000 ether;
  uint256 public constant PUBLIC_SALE = 5_950_000 ether; // 3.5% * 170M
  uint256 public constant LIQUIDITY = 8_500_000 ether; // 5% * 170M
  uint256 public constant INITIAL_SUPPLY = PUBLIC_SALE + LIQUIDITY; // 8.5%

  bool public isMintVesting;

  event MintVestingToken(address _vesting, uint256 _amount);

  constructor() ERC20("MooMonster Token", "MOO") {
    _mint(_msgSender(), PUBLIC_SALE);
    _mint(_msgSender(), LIQUIDITY);
  }

  function mint(address _vesting) external onlyOwner {
    require(!isMintVesting, "MooMonsterToken: Vesting tokens already minted");
    uint256 vestingTokenAmount = MAX_SUPPLY - totalSupply();
    _mint(_vesting, vestingTokenAmount);
    isMintVesting = true;

    emit MintVestingToken(_vesting, vestingTokenAmount);
  }

  function snapshot() external onlyOwner {
    _snapshot();
  }

  function _beforeTokenTransfer(
    address from,
    address to,
    uint256 amount
  ) internal override(ERC20, ERC20Snapshot) {
    super._beforeTokenTransfer(from, to, amount);
  }
}
