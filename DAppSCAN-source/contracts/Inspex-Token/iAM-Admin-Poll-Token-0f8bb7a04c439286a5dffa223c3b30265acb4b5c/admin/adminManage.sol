// SPDX-License-Identifier: MIT
pragma solidity =0.8.4;

contract AdminManage {
  address private constant GENESIS_ADDRESS = address(0x1);
  address public superAdminHead;
  address public adminHead;

  mapping(address => Node) public superAdmin;
  mapping(address => Node) public admin;

  uint32 private deadline; // 28800 1 day in block = 1 block/3 sec
  uint256 public superAdminCount;
  uint256 public adminCount;

  struct Vote {
    address lastVoter;
    address kickVote;
    uint256 deadline;
  }

  struct Node {
    address prev;
    address next;
  }

  Vote public tmp;

  modifier onlySuperAdmin() {
    require(
      superAdmin[msg.sender].next != address(0) && msg.sender != GENESIS_ADDRESS,
      'AdminManage: require superAdmin'
    );
    _;
  }

  constructor(address inittialSuperadmin, uint32 _deadline) {
    superAdmin[inittialSuperadmin] = Node(address(0), GENESIS_ADDRESS);
    superAdmin[GENESIS_ADDRESS] = Node(inittialSuperadmin, address(0));
    superAdminHead = inittialSuperadmin;
    superAdminCount++;

    addAdmin(inittialSuperadmin);
    adminHead = inittialSuperadmin;

    deadline = _deadline;
  }

  function isSuperAdmin(address _address) external view returns (bool) {
    return superAdmin[_address].next != address(0);
  }

  function isAdmin(address _address) external view returns (bool) {
    return admin[_address].next != address(0);
  }

  function getSuperAdminList() external view returns (address[] memory) {
    address[] memory array = new address[](superAdminCount);
    uint256 index = 0;
    address currentSuperAdmin = superAdminHead;
    while (currentSuperAdmin != GENESIS_ADDRESS) {
      array[index] = currentSuperAdmin;
      currentSuperAdmin = superAdmin[currentSuperAdmin].next;
      index++;
    }

    return array;
  }

  function getAdminList() external view returns (address[] memory) {
    address[] memory array = new address[](adminCount);
    uint256 index = 0;
    address currentAdmin = adminHead;
    while (currentAdmin != GENESIS_ADDRESS) {
      array[index] = currentAdmin;
      currentAdmin = admin[currentAdmin].next;
      index++;
    }

    return array;
  }

  function addAdmin(address _newAdmin) public onlySuperAdmin {
    require(
      _newAdmin != address(0) && _newAdmin != GENESIS_ADDRESS,
      'AdminManage [addAdmin]: Invalid owner address provided'
    );
    require(admin[_newAdmin].next == address(0), 'AdminManage [addAdmin]: Address is already a admin');

    address latest = admin[GENESIS_ADDRESS].prev;
    admin[latest].next = _newAdmin;

    admin[_newAdmin].prev = latest;
    admin[_newAdmin].next = GENESIS_ADDRESS;
    admin[GENESIS_ADDRESS].prev = _newAdmin;
    adminCount++;
  }

  function addSuperAdmin(address _newSuperAdmin) public onlySuperAdmin {
    require(
      _newSuperAdmin != address(0) && _newSuperAdmin != GENESIS_ADDRESS,
      'AdminManage: Invalid owner address provided'
    );
    require(superAdmin[_newSuperAdmin].next == address(0), 'AdminManage: Address is already an superAdmin');

    address latest = superAdmin[GENESIS_ADDRESS].prev;
    superAdmin[latest].next = _newSuperAdmin;

    superAdmin[_newSuperAdmin].prev = latest;
    superAdmin[_newSuperAdmin].next = GENESIS_ADDRESS;
    superAdmin[GENESIS_ADDRESS].prev = _newSuperAdmin;
    superAdminCount++;
  }

  function removeAdmin(address _admin) public onlySuperAdmin {
    require(admin[_admin].next != address(0), 'AdminManage [removeAdmin]: require admin wallet at arg[0]');

    address _prevAdmin = admin[_admin].prev;

    // if head of admin
    if (_prevAdmin == address(0) && _admin == adminHead) {
      adminHead = admin[_admin].next;
      admin[admin[_admin].next].prev = address(0);
      admin[_admin].prev = address(0);
      admin[_admin].next = address(0);
      adminCount--;
      return;
    }

    require(
      _admin != address(0) && admin[_prevAdmin].next == _admin,
      'AdminManage [_removeSuperAdmin]: Invalid prevOwner, owner pair provided'
    );

    address _nextAdmin = admin[_admin].next;
    admin[_prevAdmin].next = admin[_admin].next;
    admin[_nextAdmin].prev = admin[_admin].prev;
    admin[_admin].prev = address(0);
    admin[_admin].next = address(0);
    adminCount--;
  }

  function removeSuperAdmin(address _superAdmin) public onlySuperAdmin {
    require(
      superAdmin[_superAdmin].next != address(0),
      'AdminManage [removeSuperAdmin]: require superAdmin wallet at arg[0]'
    );
    if (block.number > tmp.deadline || _superAdmin != tmp.kickVote) {
      tmp = Vote({lastVoter: msg.sender, kickVote: _superAdmin, deadline: block.number + deadline});

      return;
    }

    // ====  vote to same address ====
    // require vote 1 vote 1 address
    require(msg.sender != tmp.lastVoter, "AdminManage [removeSuperAdmin]: can't use the same address to vote");

    _removeSuperAdmin(_superAdmin);

    // empty tmp
    tmp = Vote({lastVoter: address(0), kickVote: address(0), deadline: block.number});
  }

  function _removeSuperAdmin(address _superAdmin) private {
    require(
      _superAdmin != GENESIS_ADDRESS && superAdminCount > 1,
      'AdminManage [_removeSuperAdmin]: Invalid owner address provided'
    );

    address _prevSuperAdmin = superAdmin[_superAdmin].prev;

    // if head of superAdmin
    if (_prevSuperAdmin == address(0) && _superAdmin == superAdminHead) {
      superAdminHead = superAdmin[_superAdmin].next;
      superAdmin[superAdmin[_superAdmin].next].prev = address(0);
      superAdmin[_superAdmin].prev = address(0);
      superAdmin[_superAdmin].next = address(0);
      superAdminCount--;
      return;
    }

    require(
      _superAdmin != address(0) && superAdmin[_prevSuperAdmin].next == _superAdmin,
      'AdminManage [_removeSuperAdmin]: Invalid prevOwner, owner pair provided'
    );

    address _nextSuperAdmin = superAdmin[_superAdmin].next;
    superAdmin[_prevSuperAdmin].next = superAdmin[_superAdmin].next;
    superAdmin[_nextSuperAdmin].prev = superAdmin[_superAdmin].prev;
    superAdmin[_superAdmin].prev = address(0);
    superAdmin[_superAdmin].next = address(0);
    superAdminCount--;
  }
}
