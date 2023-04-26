// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '../interfaces/IERC20Burnable.sol';

contract BigOwner {
  event NewAdmin(address indexed newAdmin, address indexed removeAdmin);
  event PendingAdmin(address indexed newPendingAdmin, address indexed removeAdmin);
  event ApprovePendingAdmin(address indexed newPendingAdmin, address indexed removeAdmin);
  event ExecuteAdminTransfer(
    bytes32 indexed txHash,
    address indexed target,
    address sender,
    address recipient,
    uint256 amount
  );
  event PendingAdminTransfer(
    bytes32 indexed txHash,
    address indexed target,
    address sender,
    address recipient,
    uint256 amount
  );
  event ExecuteTransferOwnership(bytes32 indexed txHash, address indexed target, address indexed newOwner);
  event PendingTransferOwnership(bytes32 indexed txHash, address indexed target, address indexed newOwner);

  uint256 public PANDING_BLOCK; // block
  bytes32 public pendingAdminHash;
  bool public pendingAdminHashApprove;
  address public pendingAdminHashSubmitter;
  uint256 private pendingAdminHashSubmitBlock;
  address[] private adminList;

  mapping(address => bool) public admin;
  mapping(bytes32 => pendingQueue) public queuedTransactions;

  struct pendingQueue {
    uint256 submitedBlock;
    address by;
  }

  modifier onlyOwner() {
    require(admin[msg.sender] == true, 'BigOwner: caller is not the admin');
    _;
  }

  constructor(address[] memory admin_, uint256 deadline_) {
    require(admin_.length >= 2, 'BigOwner: initial admin should more then 1 address.');

    for (uint32 i = 0; i < admin_.length; i++) {
      admin[admin_[i]] = true;
      adminList.push(admin_[i]);
    }

    PANDING_BLOCK = deadline_;
  }

  receive() external payable {}

  function getAdminList() external view returns (address[] memory) {
    return adminList;
  }

  function setDeadline(uint256 deadline_) external onlyOwner {
    PANDING_BLOCK = deadline_;
  }

  function acceptAdmin(address pendingAdmin_, address pendingRemoveAdmin_) public {
    bytes32 txHash = keccak256(abi.encode(pendingAdmin_, pendingRemoveAdmin_));
    require(txHash == pendingAdminHash, 'BigOwner::acceptAdmin: Argument not match pendingAdminHash.');
    require(msg.sender == pendingAdmin_, 'BigOwner::acceptAdmin: Call must come from newAdmin.');
    require(
      pendingAdminHashSubmitBlock + PANDING_BLOCK >= getBlockNumber(),
      "BigOwner::acceptAdmin: PendingAdmin hasn't surpassed pending time."
    );

    admin[pendingAdmin_] = true;
    admin[pendingRemoveAdmin_] = false;

    uint256 removeAdminIndex = 0;
    bool isFound = false;
    for (uint256 i = 0; i < adminList.length; i++) {
      if (adminList[i] == pendingRemoveAdmin_) {
        removeAdminIndex = i;
        isFound = true;
        break;
      }
    }
    assert(isFound);

    adminList[removeAdminIndex] = pendingAdmin_;

    pendingAdminHashSubmitter = address(0);
    pendingAdminHash = '';

    emit NewAdmin(pendingAdmin_, pendingAdmin_);
  }

  function approvePendingAdmin(address pendingAdmin_, address pendingRemoveAdmin_) external onlyOwner returns (bool) {
    bytes32 txHash = keccak256(abi.encode(pendingAdmin_, pendingRemoveAdmin_));
    require(txHash == pendingAdminHash, 'BigOwner::approvePendingAdmin: Argument not match to pendingAdminHash.');
    require(
      msg.sender != pendingAdminHashSubmitter,
      'BigOwner::approvePendingAdmin: Call must not come from pendingAdminHashSubmitter.'
    );

    pendingAdminHashApprove = true;

    emit ApprovePendingAdmin(pendingAdmin_, pendingRemoveAdmin_);
    return true;
  }

  function setPendingAdmin(address pendingAdmin_, address pendingRemoveAdmin_) external onlyOwner {
    // allows one time setting of admin for deployment purposes
    require(admin[pendingRemoveAdmin_] == true, 'BigOwner::setPendingAdmin: pendingRemoveAdmin should be admin.');
    require(admin[pendingAdmin_] == false, 'BigOwner::setPendingAdmin: pendingAdmin should not be admin.');

    bytes32 txHash = keccak256(abi.encode(pendingAdmin_, pendingRemoveAdmin_));
    pendingAdminHashSubmitter = msg.sender;
    pendingAdminHashSubmitBlock = getBlockNumber();
    pendingAdminHashApprove = false;
    pendingAdminHash = txHash;

    emit PendingAdmin(pendingAdmin_, pendingRemoveAdmin_);
  }

  function setPendingTransferOwnership(address target, address newOwner) external onlyOwner returns (bytes32) {
    bytes32 txHash = keccak256(abi.encode(target, newOwner));
    queuedTransactions[txHash] = pendingQueue(getBlockNumber(), msg.sender);

    emit PendingTransferOwnership(txHash, target, newOwner);
    return txHash;
  }

  function setPendingAdminTransfer(
    address target,
    address sender,
    address recipient,
    uint256 amount
  ) external onlyOwner returns (bytes32) {
    bytes32 txHash = keccak256(abi.encode(target, sender, recipient, amount));
    queuedTransactions[txHash] = pendingQueue(getBlockNumber(), msg.sender);

    emit PendingAdminTransfer(txHash, target, sender, recipient, amount);
    return txHash;
  }

  function executeTransferOwnership(address target, address newOwner) external onlyOwner returns (bool) {
    bytes32 txHash = keccak256(abi.encode(target, newOwner));
    require(
      queuedTransactions[txHash].by != address(0),
      "BigOwner::executeTransferOwnership: Transaction hasn't been queued."
    );
    require(
      getBlockNumber() <= queuedTransactions[txHash].submitedBlock + PANDING_BLOCK,
      "BigOwner::executeTransferOwnership: Transaction hasn't surpassed pending time."
    );

    // shoule not execute by queue creator
    require(
      queuedTransactions[txHash].by != msg.sender,
      'BigOwner::executeTransferOwnership: can not execute by queue creator.'
    );

    queuedTransactions[txHash] = pendingQueue(0, address(0));

    IERC20Burnable(target).transferOwnership(newOwner);

    emit ExecuteTransferOwnership(txHash, target, newOwner);

    return true;
  }

  function executeAdminTransfer(
    address target,
    address sender,
    address recipient,
    uint256 amount
  ) external onlyOwner returns (bool) {
    bytes32 txHash = keccak256(abi.encode(target, sender, recipient, amount));
    require(
      queuedTransactions[txHash].by != address(0),
      "BigOwner::executeAdminTransfer: Transaction hasn't been queued."
    );
    require(
      getBlockNumber() <= queuedTransactions[txHash].submitedBlock + PANDING_BLOCK,
      "BigOwner::executeAdminTransfer: Transaction hasn't surpassed pending time."
    );

    // shoule not execute by queue creator
    require(
      queuedTransactions[txHash].by != msg.sender,
      'BigOwner::executeAdminTransfer: can not execute by queue creator.'
    );

    queuedTransactions[txHash] = pendingQueue(0, address(0));

    bool success = IERC20Burnable(target).adminTransfer(sender, recipient, amount);
    require(success, 'BigOwner::executeAdminTransfer: Transaction execution reverted.');

    emit ExecuteAdminTransfer(txHash, target, sender, recipient, amount);

    return success;
  }

  function getBlockNumber() public view returns (uint256) {
    return block.number;
  }
}
