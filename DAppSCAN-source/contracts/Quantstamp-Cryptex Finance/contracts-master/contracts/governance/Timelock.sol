// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/introspection/IERC165.sol";

contract Timelock is IERC165 {
  using SafeMath for uint256;

  event NewAdmin(address indexed newAdmin);
  event NewPendingAdmin(address indexed newPendingAdmin);
  event NewDelay(uint256 indexed newDelay);
  event CancelTransaction(
    bytes32 indexed txHash,
    address indexed target,
    uint256 value,
    string signature,
    bytes data,
    uint256 eta
  );
  event ExecuteTransaction(
    bytes32 indexed txHash,
    address indexed target,
    uint256 value,
    string signature,
    bytes data,
    uint256 eta
  );
  event QueueTransaction(
    bytes32 indexed txHash,
    address indexed target,
    uint256 value,
    string signature,
    bytes data,
    uint256 eta
  );

  uint256 public constant GRACE_PERIOD = 14 days;
  uint256 public constant MINIMUM_DELAY = 2 days;
  uint256 public constant MAXIMUM_DELAY = 30 days;

  address public admin;
  address public pendingAdmin;
  uint256 public delay;

  /**
   * @dev the computed interface ID according to ERC-165. The interface ID is a XOR of interface method selectors.
   * queueTransaction.selector ^
   * cancelTransaction.selector ^
   * executeTransaction.selector  =>  0x6b5cc770
   */
  bytes4 private constant _INTERFACE_ID_TIMELOCK = 0x6b5cc770;

  /// @dev bytes4(keccak256('supportsInterface(bytes4)')) == 0x01ffc9a7
  bytes4 private constant _INTERFACE_ID_ERC165 = 0x01ffc9a7;

  mapping(bytes32 => bool) public queuedTransactions;

  constructor(address admin_, uint256 delay_) {
    require(
      delay_ >= MINIMUM_DELAY,
      "Timelock::constructor: Delay must exceed minimum delay."
    );
    require(
      delay_ <= MAXIMUM_DELAY,
      "Timelock::setDelay: Delay must not exceed maximum delay."
    );

    admin = admin_;
    delay = delay_;
  }

  receive() external payable {}

  function setDelay(uint256 delay_) public {
    require(
      msg.sender == address(this),
      "Timelock::setDelay: Call must come from Timelock."
    );
    require(
      delay_ >= MINIMUM_DELAY,
      "Timelock::setDelay: Delay must exceed minimum delay."
    );
    require(
      delay_ <= MAXIMUM_DELAY,
      "Timelock::setDelay: Delay must not exceed maximum delay."
    );
    delay = delay_;

    emit NewDelay(delay);
  }

  /**
   * @notice ERC165 Standard for support of interfaces
   * @param _interfaceId bytes of interface
   * @return bool
   */
  function supportsInterface(bytes4 _interfaceId)
    external
    pure
    override
    returns (bool)
  {
    return (_interfaceId == _INTERFACE_ID_TIMELOCK ||
      _interfaceId == _INTERFACE_ID_ERC165);
  }

  function acceptAdmin() public {
    require(
      msg.sender == pendingAdmin,
      "Timelock::acceptAdmin: Call must come from pendingAdmin."
    );
    admin = msg.sender;
    pendingAdmin = address(0);

    emit NewAdmin(admin);
  }

  function setPendingAdmin(address pendingAdmin_) public {
    require(
      msg.sender == address(this),
      "Timelock::setPendingAdmin: Call must come from Timelock."
    );
    pendingAdmin = pendingAdmin_;

    emit NewPendingAdmin(pendingAdmin);
  }

  function queueTransaction(
    address target,
    uint256 value,
    string memory signature,
    bytes memory data,
    uint256 eta
  ) public returns (bytes32) {
    require(
      msg.sender == admin,
      "Timelock::queueTransaction: Call must come from admin."
    );
    require(
      eta >= getBlockTimestamp().add(delay),
      "Timelock::queueTransaction: Estimated execution block must satisfy delay."
    );

    bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
    queuedTransactions[txHash] = true;

    emit QueueTransaction(txHash, target, value, signature, data, eta);
    return txHash;
  }

  function cancelTransaction(
    address target,
    uint256 value,
    string memory signature,
    bytes memory data,
    uint256 eta
  ) public {
    require(
      msg.sender == admin,
      "Timelock::cancelTransaction: Call must come from admin."
    );

    bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
    queuedTransactions[txHash] = false;

    emit CancelTransaction(txHash, target, value, signature, data, eta);
  }

  function executeTransaction(
    address target,
    uint256 value,
    string memory signature,
    bytes memory data,
    uint256 eta
  ) public payable returns (bytes memory) {
    require(
      msg.sender == admin,
      "Timelock::executeTransaction: Call must come from admin."
    );

    bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
    require(
      queuedTransactions[txHash],
      "Timelock::executeTransaction: Transaction hasn't been queued."
    );
    require(
      getBlockTimestamp() >= eta,
      "Timelock::executeTransaction: Transaction hasn't surpassed time lock."
    );
    require(
      getBlockTimestamp() <= eta.add(GRACE_PERIOD),
      "Timelock::executeTransaction: Transaction is stale."
    );

    queuedTransactions[txHash] = false;

    bytes memory callData;

    if (bytes(signature).length == 0) {
      callData = data;
    } else {
      callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
    }

    // solium-disable-next-line security/no-call-value
    (bool success, bytes memory returnData) =
      target.call{value: value}(callData);
    require(
      success,
      "Timelock::executeTransaction: Transaction execution reverted."
    );

    emit ExecuteTransaction(txHash, target, value, signature, data, eta);

    return returnData;
  }

  function getBlockTimestamp() internal view returns (uint256) {
    // solium-disable-next-line security/no-block-members
    return block.timestamp;
  }
}
