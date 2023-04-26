// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3rV1.sol';

import '../interfaces/keep3r/IUniquoteKeep3rEscrow.sol';

// DEPRECATED
contract UniquoteKeep3rEscrow is UtilsReady, IUniquoteKeep3rEscrow {
  using SafeMath for uint256;

  address public immutable override governance;
  address public immutable override keep3rV1;
  address public immutable override lpToken;
  address public immutable override job;
  address public immutable override keeper;

  constructor(
    address _governance,
    address _keep3r,
    address _lpToken,
    address _job,
    address _keeper
  ) public UtilsReady() {
    governance = _governance;
    keep3rV1 = _keep3r;
    lpToken = _lpToken;
    _addProtocolToken(_lpToken);
    job = _job;
    keeper = _keeper;
  }

  function returnLPsToGovernance() external override onlyGovernor {
    IERC20(lpToken).transfer(governance, IERC20(lpToken).balanceOf(address(this)));
  }

  function addLiquidityToJob() external override onlyGovernorOrKeeper {
    uint256 _amount = IERC20(lpToken).balanceOf(address(this));
    IERC20(lpToken).approve(keep3rV1, _amount);
    IKeep3rV1(keep3rV1).addLiquidityToJob(lpToken, job, _amount);
  }

  function applyCreditToJob() external override onlyGovernorOrKeeper {
    IKeep3rV1(keep3rV1).applyCreditToJob(address(this), lpToken, job);
  }

  function unbondLiquidityFromJob() external override onlyGovernorOrKeeper {
    uint256 _amount = IKeep3rV1(keep3rV1).liquidityProvided(address(this), lpToken, job);
    IKeep3rV1(keep3rV1).unbondLiquidityFromJob(lpToken, job, _amount);
  }

  function removeLiquidityFromJob() external override onlyGovernorOrKeeper {
    IKeep3rV1(keep3rV1).removeLiquidityFromJob(lpToken, job);
  }

  modifier onlyGovernorOrKeeper() {
    require(isGovernor(msg.sender) || msg.sender == keeper, 'UniquoteKeep3rEscrow::onlyGovernorOrKeeper:invalid-msg-sender');
    _;
  }
}
