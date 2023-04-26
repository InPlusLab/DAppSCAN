// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3rV1.sol';

interface IKeep3rEscrowParameters {
  event GovernanceSet(address _governance);
  event Keep3rV1Set(IKeep3rV1 _keep3rV1);
  event LPTokenSet(IERC20 _lpToken);
  event LPsReturnedToGovernance(address _governance, uint256 _amount);

  function governance() external returns (address);

  function keep3rV1() external returns (IKeep3rV1);

  function lpToken() external returns (IERC20);

  function setGovernance(address _governance) external;

  function setKeep3rV1(IKeep3rV1 _keep3rV1) external;

  function setLPToken(IERC20 _lpToken) external;

  function returnLPsToGovernance() external;
}

abstract contract Keep3rEscrowParameters is IKeep3rEscrowParameters {
  using SafeMath for uint256;

  address public override governance;
  IKeep3rV1 public override keep3rV1;
  IERC20 public override lpToken;

  constructor(
    address _governance,
    IKeep3rV1 _keep3r,
    IERC20 _lpToken
  ) public {
    _setGovernance(_governance);
    _setKeep3rV1(_keep3r);
    _setLPToken(_lpToken);
  }

  function _setGovernance(address _governance) internal {
    require(_governance != address(0), 'Keep3rEscrowParameters::_setGovernance::zero-address');
    governance = _governance;
    emit GovernanceSet(_governance);
  }

  function _setKeep3rV1(IKeep3rV1 _keep3rV1) internal {
    require(address(_keep3rV1) != address(0), 'Keep3rEscrowParameters::_setKeep3rV1::zero-address');
    keep3rV1 = _keep3rV1;
    emit Keep3rV1Set(_keep3rV1);
  }

  function _setLPToken(IERC20 _lpToken) internal {
    require(address(_lpToken) != address(0), 'Keep3rEscrowParameters::_setLPToken::zero-address');
    lpToken = _lpToken;
    emit LPTokenSet(_lpToken);
  }

  function _returnLPsToGovernance() internal {
    uint256 _tokenBalance = lpToken.balanceOf(address(this));
    require(_tokenBalance > 0, 'Keep3rEscrowParameters::_returnLPsToGovernance::no-lp-tokens');
    lpToken.transfer(governance, _tokenBalance);
    emit LPsReturnedToGovernance(governance, _tokenBalance);
  }
}
