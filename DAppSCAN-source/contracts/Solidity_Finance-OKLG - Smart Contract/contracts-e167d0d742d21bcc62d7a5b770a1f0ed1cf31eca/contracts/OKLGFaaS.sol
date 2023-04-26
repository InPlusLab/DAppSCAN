// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import './OKLGFaaSToken.sol';
import './OKLGProduct.sol';

/**
 * @title OKLGFaaS (sOKLG)
 * @author Lance Whatley
 * @notice Implements the master FaaS contract to keep track of all tokens being added
 * to be staked and staking.
 */
contract OKLGFaaS is OKLGProduct {
  // this is a mapping of tokenAddress => contractAddress[] that represents
  // a particular address for the token that someone has put up
  // to be staked and a list of contract addresses for the staking token
  // contracts paying out stakers for the given token.
  mapping(address => address[]) public tokensUpForStaking;
  address[] public allFarmingContracts;
  uint256 public totalStakingContracts;

  /**
   * @notice The constructor for the staking master contract.
   */
  constructor(address _tokenAddress, address _spendAddress)
    OKLGProduct(uint8(8), _tokenAddress, _spendAddress)
  {}

  function getAllFarmingContracts() external view returns (address[] memory) {
    return allFarmingContracts;
  }

  function getTokensForStaking(address _tokenAddress)
    external
    view
    returns (address[] memory)
  {
    return tokensUpForStaking[_tokenAddress];
  }

  function createNewTokenContract(
    address _rewardsTokenAddy,
    address _stakedTokenAddy,
    uint256 _supply,
    uint256 _perBlockAllocation,
    uint256 _lockedUntilDate,
    uint256 _timelockSeconds,
    bool _isStakedNft
  ) external payable {
    _payForService(0);

    // create new OKLGFaaSToken contract which will serve as the core place for
    // users to stake their tokens and earn rewards
    ERC20 _rewToken = ERC20(_rewardsTokenAddy);

    // Send the new contract all the tokens from the sending user to be staked and harvested
    _rewToken.transferFrom(msg.sender, address(this), _supply);

    // in order to handle tokens that take tax, are burned, etc. when transferring, need to get
    // the user's balance after transferring in order to send the remainder of the tokens
    // instead of the full original supply. Similar to slippage on a DEX
    uint256 _updatedSupply = _supply <= _rewToken.balanceOf(address(this))
      ? _supply
      : _rewToken.balanceOf(address(this));

    OKLGFaaSToken _contract = new OKLGFaaSToken(
      'OKLG Staking Token',
      'sOKLG',
      _updatedSupply,
      _rewardsTokenAddy,
      _stakedTokenAddy,
      msg.sender,
      _perBlockAllocation,
      _lockedUntilDate,
      _timelockSeconds,
      _isStakedNft
    );
    allFarmingContracts.push(address(_contract));
    tokensUpForStaking[_stakedTokenAddy].push(address(_contract));
    totalStakingContracts++;

    _rewToken.transfer(address(_contract), _updatedSupply);

    // do one more double check on balance of rewards token
    // in the staking contract and update if need be
    uint256 _finalSupply = _updatedSupply <=
      _rewToken.balanceOf(address(_contract))
      ? _updatedSupply
      : _rewToken.balanceOf(address(_contract));
    if (_updatedSupply != _finalSupply) {
      _contract.updateSupply(_finalSupply);
    }
  }

  function removeTokenContract(address _faasTokenAddy) external {
    OKLGFaaSToken _contract = OKLGFaaSToken(_faasTokenAddy);
    require(
      msg.sender == _contract.tokenOwner(),
      'user must be the original token owner to remove tokens'
    );
    require(
      block.timestamp > _contract.getLockedUntilDate() &&
        _contract.getLockedUntilDate() != 0,
      'it must be after the locked time the user originally configured and not locked forever'
    );

    _contract.removeStakeableTokens();
    totalStakingContracts--;
  }
}
