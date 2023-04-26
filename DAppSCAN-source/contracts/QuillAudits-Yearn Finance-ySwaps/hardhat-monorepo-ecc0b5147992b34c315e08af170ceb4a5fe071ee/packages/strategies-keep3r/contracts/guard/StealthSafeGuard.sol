// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/utils/structs/EnumerableSet.sol';
import '@yearn/contract-utils/contracts/abstract/UtilsReady.sol';
import '@yearn/contract-utils/contracts/utils/Manageable.sol';
import '@lbertenasco/bonded-stealth-tx/contracts/utils/OnlyStealthRelayer.sol';

import '../interfaces/gnosis/IGnosisSafe.sol';
import '../interfaces/utils/IGovernableAndManageable.sol';
import '../interfaces/stealth/IStealthRelayer.sol';

interface IStealthSafeGuard is IGuard, IGovernableAndManageable {
  error NotAuthorized();
  error ZeroAddress();
  error InvalidExecutor();
  error NotStealthRelayer();
  error NotExecutor();

  function overrideGuardChecks() external view returns (bool _overrideGuardChecks);

  function stealthRelayerCheck() external view returns (bool _stealthRelayerCheck);

  function executors() external view returns (address[] memory _executorsArray);

  function addExecutor(address _executor) external;

  function removeExecutor(address _executor) external;

  function setOverrideGuardChecks(bool _overrideGuardChecks) external;

  function setStealthRelayerCheck(bool _stealthRelayerCheck) external;
}

contract StealthSafeGuard is UtilsReady, Manageable, OnlyStealthRelayer, IStealthSafeGuard {
  using EnumerableSet for EnumerableSet.AddressSet;

  EnumerableSet.AddressSet internal _executors;

  bool public override overrideGuardChecks;
  bool public override stealthRelayerCheck;

  constructor(address _manager, address _stealthRelayer) UtilsReady() Manageable(_manager) OnlyStealthRelayer(_stealthRelayer) {}

  function executors() external view override returns (address[] memory _executorsArray) {
    return _executors.values();
  }

  function addExecutor(address _executor) external override onlyGovernorOrManager {
    if (_executor == address(0)) revert ZeroAddress();
    if (!_executors.add(_executor)) revert InvalidExecutor();
  }

  function removeExecutor(address _executor) external override onlyGovernorOrManager {
    if (_executor == address(0)) revert ZeroAddress();
    if (!_executors.remove(_executor)) revert InvalidExecutor();
  }

  function setOverrideGuardChecks(bool _overrideGuardChecks) external override onlyGovernorOrManager {
    overrideGuardChecks = _overrideGuardChecks;
  }

  function setStealthRelayerCheck(bool _stealthRelayerCheck) external override onlyGovernorOrManager {
    stealthRelayerCheck = _stealthRelayerCheck;
  }

  function checkTransaction(
    address, /*to*/
    uint256, /*value*/
    bytes memory, /*data*/
    Enum.Operation, /*operation*/
    uint256, /*safeTxGas*/
    uint256, /*baseGas*/
    uint256, /*gasPrice*/
    address, /*gasToken*/
    // solhint-disable-next-line no-unused-vars
    address payable, /*refundReceiver*/
    bytes memory, /*signatures*/
    address msgSender
  ) external view override {
    if (overrideGuardChecks) return;

    if (stealthRelayerCheck) {
      address _caller = IStealthRelayer(stealthRelayer).caller();

      if (msgSender != stealthRelayer || !_executors.contains(_caller)) {
        revert NotStealthRelayer();
      }
    } else {
      if (!_executors.contains(msgSender)) {
        revert NotExecutor();
      }
    }
  }

  // unused
  function checkAfterExecution(bytes32, bool) external view override {}

  // solhint-disable-next-line payable-fallback
  fallback() external {
    // We don't revert on fallback to avoid issues in case of a Safe upgrade
    // E.g. The expected check method might change and then the Safe would be locked.
  }

  // Manageable: setters
  function setPendingManager(address _pendingManager) external override onlyGovernor {
    _setPendingManager(_pendingManager);
  }

  function acceptManager() external override onlyPendingManager {
    _acceptManager();
  }

  // Stealth Relayer Setters
  function setStealthRelayer(address _stealthRelayer) external override onlyGovernorOrManager {
    _setStealthRelayer(_stealthRelayer);
  }

  modifier onlyGovernorOrManager() {
    if (!isGovernor(msg.sender) && !isManager(msg.sender)) revert NotAuthorized();
    _;
  }
}
