// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '../interfaces/IConditional.sol';
import '../interfaces/IMultiplier.sol';
import '../interfaces/IOKLGDividendDistributor.sol';
import '../OKLGWithdrawable.sol';

interface IERC20Decimals is IERC20 {
  function decimals() external view returns (uint8);
}

/**
 * @title OKLApeRewardsBooster
 * @dev Calculates the boost amount for OKLG native rewards.
 */
contract OKLApeRewardsBooster is IConditional, IMultiplier, OKLGWithdrawable {
  using SafeMath for uint256;

  struct Booster {
    uint256 baseBoost; // percentage boost: 100, 50, 25, etc.
    uint256 maxOKLGBalance; // max OKLG balance in this range of boosters
    uint256 maxNFTBalance; // maximum NFT balance to continue boosting rewards
  }

  IERC20Decimals oklg;
  IOKLGDividendDistributor distributor;
  Booster[] multipliers;

  constructor(address _oklg, address _dist) {
    oklg = IERC20Decimals(_oklg);
    distributor = IOKLGDividendDistributor(_dist);

    // seed initial rewards boosters
    multipliers.push(
      Booster({
        baseBoost: 50,
        maxOKLGBalance: uint256(15_000_000).mul(10**oklg.decimals()),
        maxNFTBalance: 6
      })
    );

    multipliers.push(
      Booster({
        baseBoost: 25,
        maxOKLGBalance: uint256(80_000_000).mul(10**oklg.decimals()),
        maxNFTBalance: 8
      })
    );

    multipliers.push(
      Booster({
        baseBoost: 15,
        maxOKLGBalance: uint256(999_999_999_999_999_999).mul(
          10**oklg.decimals()
        ),
        maxNFTBalance: 10
      })
    );
  }

  // required by rewards booster logic in rewards contract to determine if eligible for booster at all
  function passesTest(address wallet) external view override returns (bool) {
    uint256[] memory _userNFTTokenIds = distributor.getBoostNfts(wallet);
    return wallet == address(0) ? false : _userNFTTokenIds.length >= 1;
  }

  // returns number indicating percentage boost (0 == 0%, 1 == 1%, etc.)
  function getMultiplier(address wallet)
    external
    view
    override
    returns (uint256)
  {
    if (wallet == address(0)) return 0;

    uint256 _userOKLGBalance = distributor.getShares(wallet);
    if (_userOKLGBalance == 0) return 0;

    uint256[] memory _userNFTTokenIds = distributor.getBoostNfts(wallet);
    uint256 _userNFTBalance = _userNFTTokenIds.length;
    if (_userNFTBalance == 0) return 0;

    for (uint256 _i = 0; _i < multipliers.length; _i++) {
      Booster memory mult = multipliers[_i];
      if (_userOKLGBalance > mult.maxOKLGBalance) continue;

      uint256 nftBalanceAdjusted = _userNFTBalance > mult.maxNFTBalance
        ? mult.maxNFTBalance
        : _userNFTBalance;
      return mult.baseBoost.mul(nftBalanceAdjusted);
    }
    return 0;
  }

  function getOklgAddress() external view returns (address) {
    return address(oklg);
  }

  function setOklg(address _oklgAddy) external onlyOwner {
    oklg = IERC20Decimals(_oklgAddy);
  }

  function setDistributor(address _dist) external onlyOwner {
    distributor = IOKLGDividendDistributor(_dist);
  }

  function setAllMultipliers(Booster[] memory _boosters) external onlyOwner {
    delete multipliers;
    for (uint256 _i = 0; _i < _boosters.length; _i++) {
      multipliers.push(_boosters[_i]);
    }
  }
}
