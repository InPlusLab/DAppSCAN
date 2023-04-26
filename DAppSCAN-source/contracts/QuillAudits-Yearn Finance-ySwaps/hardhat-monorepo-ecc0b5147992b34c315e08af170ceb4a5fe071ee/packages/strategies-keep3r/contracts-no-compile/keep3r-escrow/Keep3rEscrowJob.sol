// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@yearn/contract-utils/contracts/abstract/MachineryReady.sol';
import '@yearn/contract-utils/contracts/interfaces/keep3r/IKeep3rV1.sol';

import '../proxy-job/Keep3rJob.sol';
import '../interfaces/jobs/IKeep3rEscrowJob.sol';

import '../interfaces/keep3r/IKeep3rEscrow.sol';

contract Keep3rEscrowJob is MachineryReady, Keep3rJob, IKeep3rEscrowJob {
  IKeep3rV1 public Keep3rV1;
  IERC20 public Liquidity;

  IKeep3rEscrow public Escrow1;
  IKeep3rEscrow public Escrow2;

  constructor(
    address _mechanicsRegistry,
    address _keep3r,
    address _keep3rProxyJob,
    address _liquidity,
    address _escrow1,
    address _escrow2
  ) public MachineryReady(_mechanicsRegistry) Keep3rJob(_keep3rProxyJob) {
    Keep3rV1 = IKeep3rV1(_keep3r);
    Liquidity = IERC20(_liquidity);
    Escrow1 = IKeep3rEscrow(_escrow1);
    Escrow2 = IKeep3rEscrow(_escrow2);
  }

  // Keep3rV1 Escrow helper
  function getNextAction() public view override returns (IKeep3rEscrow Escrow, Actions _action) {
    uint256 liquidityProvided1 = Keep3rV1.liquidityProvided(address(Escrow1), address(Liquidity), address(Keep3rProxyJob));
    uint256 liquidityProvided2 = Keep3rV1.liquidityProvided(address(Escrow2), address(Liquidity), address(Keep3rProxyJob));
    if (liquidityProvided1 == 0 && liquidityProvided2 == 0) {
      // Only start if both escrow have liquidity
      require(Liquidity.balanceOf(address(Escrow1)) > 0, 'Keep3rEscrowJob::getNextAction:Escrow1-liquidity-is-0');
      require(Liquidity.balanceOf(address(Escrow2)) > 0, 'Keep3rEscrowJob::getNextAction:Escrow2-liquidity-is-0');

      // Start by addLiquidityToJob liquidity with Escrow1 as default
      return (Escrow1, Actions.addLiquidityToJob);
    }

    // The escrow with liquidityAmount is the one to call applyCreditToJob, the other should call unbondLiquidityFromJob
    if (
      Keep3rV1.liquidityAmount(address(Escrow1), address(Liquidity), address(Keep3rProxyJob)) > 0 &&
      Keep3rV1.liquidityApplied(address(Escrow1), address(Liquidity), address(Keep3rProxyJob)) < block.timestamp
    ) {
      return (Escrow1, Actions.applyCreditToJob);
    }
    if (
      Keep3rV1.liquidityAmount(address(Escrow2), address(Liquidity), address(Keep3rProxyJob)) > 0 &&
      Keep3rV1.liquidityApplied(address(Escrow2), address(Liquidity), address(Keep3rProxyJob)) < block.timestamp
    ) {
      return (Escrow2, Actions.applyCreditToJob);
    }

    // Check if we can removeLiquidityFromJob & instantly addLiquidityToJob
    uint256 liquidityAmountsUnbonding1 = Keep3rV1.liquidityAmountsUnbonding(address(Escrow1), address(Liquidity), address(Keep3rProxyJob));
    uint256 liquidityUnbonding1 = Keep3rV1.liquidityUnbonding(address(Escrow1), address(Liquidity), address(Keep3rProxyJob));
    if (liquidityAmountsUnbonding1 > 0 && liquidityUnbonding1 < block.timestamp) {
      return (Escrow1, Actions.removeLiquidityFromJob);
    }
    uint256 liquidityAmountsUnbonding2 = Keep3rV1.liquidityAmountsUnbonding(address(Escrow2), address(Liquidity), address(Keep3rProxyJob));
    uint256 liquidityUnbonding2 = Keep3rV1.liquidityUnbonding(address(Escrow2), address(Liquidity), address(Keep3rProxyJob));
    if (liquidityAmountsUnbonding2 > 0 && liquidityUnbonding2 < block.timestamp) {
      return (Escrow2, Actions.removeLiquidityFromJob);
    }

    return (IKeep3rEscrow(0), Actions.none);
  }

  // Job actions (not relevant to this job, but added to maintain consistency)
  function getWorkData() public override returns (bytes memory _workData) {}

  function decodeWorkData(bytes memory _workData) public pure {
    _workData; // shh
    return;
  }

  // Keep3r actions
  function workable() public override notPaused returns (bool) {
    (, Actions _action) = getNextAction();
    return _workable(_action);
  }

  function _workable(Actions _action) internal pure returns (bool) {
    return (_action != Actions.none);
  }

  function work(bytes memory _workData) external override notPaused onlyProxyJob {
    _workData; // shh, decodeWorkData(_workData);

    (IKeep3rEscrow Escrow, Actions _action) = getNextAction();
    require(_workable(_action), 'Keep3rEscrowJob::work:not-workable');

    _work(Escrow, _action);

    emit Worked();
  }

  // Governor escrow bypass
  function forceWork() external override onlyGovernorOrMechanic {
    (IKeep3rEscrow Escrow, Actions _action) = getNextAction();
    _work(Escrow, _action);
    emit ForceWorked();
  }

  function _work(IKeep3rEscrow Escrow, Actions _action) internal {
    if (_action == Actions.addLiquidityToJob) {
      uint256 _amount = Liquidity.balanceOf(address(Escrow));
      Escrow.addLiquidityToJob(address(Liquidity), address(Keep3rProxyJob), _amount);
      return;
    }

    if (_action == Actions.applyCreditToJob) {
      IKeep3rEscrow OtherEscrow = address(Escrow) == address(Escrow1) ? Escrow2 : Escrow1;

      // ALWAYS FIRST: Should try to unbondLiquidityFromJob from OtherEscrow
      uint256 _liquidityProvided = Keep3rV1.liquidityProvided(address(OtherEscrow), address(Liquidity), address(Keep3rProxyJob));
      uint256 _liquidityAmount = Keep3rV1.liquidityAmount(address(OtherEscrow), address(Liquidity), address(Keep3rProxyJob));
      if (_liquidityProvided > 0 && _liquidityAmount == 0) {
        OtherEscrow.unbondLiquidityFromJob(address(Liquidity), address(Keep3rProxyJob), _liquidityProvided);
      } else {
        //  - if can't unbound then addLiquidity
        uint256 _amount = Liquidity.balanceOf(address(OtherEscrow));
        if (_amount > 0) {
          OtherEscrow.addLiquidityToJob(address(Liquidity), address(Keep3rProxyJob), _amount);
        } else {
          //      - if no liquidity to add and liquidityAmountsUnbonding then removeLiquidityFromJob + addLiquidityToJob
          uint256 _liquidityAmountsUnbonding = Keep3rV1.liquidityAmountsUnbonding(
            address(OtherEscrow),
            address(Liquidity),
            address(Keep3rProxyJob)
          );
          uint256 _liquidityUnbonding = Keep3rV1.liquidityUnbonding(address(OtherEscrow), address(Liquidity), address(Keep3rProxyJob));
          if (_liquidityAmountsUnbonding > 0 && _liquidityUnbonding < block.timestamp) {
            OtherEscrow.removeLiquidityFromJob(address(Liquidity), address(Keep3rProxyJob));
            _amount = Liquidity.balanceOf(address(OtherEscrow));
            OtherEscrow.addLiquidityToJob(address(Liquidity), address(Keep3rProxyJob), _amount);
          }
        }
      }

      // Run applyCreditToJob
      Escrow.applyCreditToJob(address(Escrow), address(Liquidity), address(Keep3rProxyJob));
      return;
    }

    if (_action == Actions.removeLiquidityFromJob) {
      Escrow.removeLiquidityFromJob(address(Liquidity), address(Keep3rProxyJob));
      uint256 _amount = Liquidity.balanceOf(address(Escrow));
      Escrow.addLiquidityToJob(address(Liquidity), address(Keep3rProxyJob), _amount);
      return;
    }
  }

  function returnLPsToGovernance(address _escrow) external override onlyGovernorOrMechanic {
    require(_escrow == address(Escrow1) || _escrow == address(Escrow2), 'Keep3rEscrowJob::returnLPsToGovernance:invalid-escrow');
    IKeep3rEscrow Escrow = IKeep3rEscrow(_escrow);
    Escrow.returnLPsToGovernance();
  }

  function addLiquidityToJob(address _escrow) external override onlyGovernorOrMechanic {
    require(_escrow == address(Escrow1) || _escrow == address(Escrow2), 'Keep3rEscrowJob::addLiquidityToJob:invalid-escrow');
    IKeep3rEscrow Escrow = IKeep3rEscrow(_escrow);
    uint256 _amount = Liquidity.balanceOf(address(Escrow));
    Escrow.addLiquidityToJob(address(Liquidity), address(Keep3rProxyJob), _amount);
  }

  function applyCreditToJob(address _escrow) external override onlyGovernorOrMechanic {
    require(_escrow == address(Escrow1) || _escrow == address(Escrow2), 'Keep3rEscrowJob::applyCreditToJob:invalid-escrow');
    IKeep3rEscrow Escrow = IKeep3rEscrow(_escrow);
    Escrow.applyCreditToJob(address(Escrow), address(Liquidity), address(Keep3rProxyJob));
  }

  function unbondLiquidityFromJob(address _escrow) external override onlyGovernorOrMechanic {
    require(_escrow == address(Escrow1) || _escrow == address(Escrow2), 'Keep3rEscrowJob::unbondLiquidityFromJob:invalid-escrow');
    IKeep3rEscrow Escrow = IKeep3rEscrow(_escrow);
    uint256 _amount = Keep3rV1.liquidityProvided(address(Escrow), address(Liquidity), address(Keep3rProxyJob));
    Escrow.unbondLiquidityFromJob(address(Liquidity), address(Keep3rProxyJob), _amount);
  }

  function removeLiquidityFromJob(address _escrow) external override onlyGovernorOrMechanic {
    require(_escrow == address(Escrow1) || _escrow == address(Escrow2), 'Keep3rEscrowJob::removeLiquidityFromJob:invalid-escrow');
    IKeep3rEscrow Escrow = IKeep3rEscrow(_escrow);
    Escrow.removeLiquidityFromJob(address(Liquidity), address(Keep3rProxyJob));
  }

  // Escrow Governable and CollectableDust governor bypass
  function setPendingGovernorOnEscrow(address _escrow, address _pendingGovernor) external override onlyGovernor {
    require(_escrow == address(Escrow1) || _escrow == address(Escrow2), 'Keep3rEscrowJob::removeLiquidityFromJob:invalid-escrow');
    IKeep3rEscrow Escrow = IKeep3rEscrow(_escrow);
    Escrow.setPendingGovernor(_pendingGovernor);
  }

  function acceptGovernorOnEscrow(address _escrow) external override onlyGovernor {
    require(_escrow == address(Escrow1) || _escrow == address(Escrow2), 'Keep3rEscrowJob::removeLiquidityFromJob:invalid-escrow');
    IKeep3rEscrow Escrow = IKeep3rEscrow(_escrow);
    Escrow.acceptGovernor();
  }

  function sendDustOnEscrow(
    address _escrow,
    address _to,
    address _token,
    uint256 _amount
  ) external override onlyGovernor {
    require(_escrow == address(Escrow1) || _escrow == address(Escrow2), 'Keep3rEscrowJob::removeLiquidityFromJob:invalid-escrow');
    IKeep3rEscrow Escrow = IKeep3rEscrow(_escrow);
    Escrow.sendDust(_to, _token, _amount);
  }
}
