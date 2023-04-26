pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;


interface IACL {
    function accessible(address from, address to, bytes4 sig)
        external
        view
        returns (bool);
}

interface IReplaceACL {
    function setACL(address _ACL) external;
}

contract ACL {
    //系统停机控制
    bool public locked;

    //系统维护者
    address public admin;

    struct ownerset {
        address[] addresses;
        mapping(address => uint256) indexes;
    }

    ownerset private _owners_set;
    uint public owners_size;

    address public pending_admin;
    address public pending_owner;

    //控制签名串的重放攻击
    uint public nonce;

    //访问控制列表(函数级别)
    mapping(address => mapping(address => mapping(bytes4 => bool))) public facl;
    //访问控制列表(合约级别)
    mapping(address => mapping(address => bool)) public cacl;

    modifier auth {
        require(
            accessible(msg.sender, address(this), msg.sig),
            "access unauthorized"
        );
        _;
    }

    function owners() public view returns (address[] memory) {
        return _owners_set.addresses;
    }

    constructor(address[] memory _owners, uint _owners_size) public {
        for (uint256 i = 0; i < _owners.length; ++i) {
            require(_add(_owners[i]), "added address is already an owner");
        }
        admin = msg.sender;
        owners_size = _owners_size;
    }

    function unlock() external auth {
        locked = false;
    }

    function lock() external auth {
        locked = true;
    }

    function accessible(address sender, address to, bytes4 sig)
        public
        view
        returns (bool)
    {
        if (msg.sender == admin) return true;
        if (_indexof(sender) != 0) return true;
        if (locked) return false;
        if (cacl[sender][to]) return true;
        if (facl[sender][to][sig]) return true;
        return false;
    }

    function mulsigauth(
        bytes32 _hash,
        uint8[] memory v,
        bytes32[] memory r,
        bytes32[] memory s,
        address who) public {
        uint256 _size = _size();
        uint256 weights = _size / 2 + 1;
        require(_indexof(who) != 0, "msg.sender must be owner");
        require(v.length == r.length && r.length == s.length, "invalid signatures");
        require(v.length <= _size && v.length >= weights, "invalid length");

        uint256[] memory unique = new uint256[](_size);
        for (uint256 i = 0; i < v.length; ++i) {
            address owner = ecrecover(_hash, v[i], r[i], s[i]);
            uint256 _i = _indexof(owner);
            require(_i != 0, "is not owner");
            require(unique[_i - 1] == 0, "duplicate signature");
            unique[_i - 1] = 1;
        }

        uint256 _weights = 0;
        for (uint256 i = 0; i < _size; ++i) {
            _weights += unique[i];
        }

        require(_weights >= weights, "insufficient weights");
    }

    function multiSigSetACLs(
        uint8[] memory v,
        bytes32[] memory r,
        bytes32[] memory s,
        address[] memory execTargets,
        address newACL) public {
        bytes32 inputHash = keccak256(abi.encode(newACL, msg.sender, nonce));
        bytes32 totalHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inputHash));
        mulsigauth(totalHash, v, r, s, msg.sender);
        nonce += 1;
        for (uint i = 0; i < execTargets.length; ++i) {
            IReplaceACL(execTargets[i]).setACL(newACL);
        }
    }

    //预设置 @who 具有owner权限.
    function proposeOwner(
        uint8[] calldata v,
        bytes32[] calldata r,
        bytes32[] calldata s,
        address who
    ) external {
        bytes32 inputHash = keccak256(abi.encode(who, msg.sender, nonce));
        bytes32 totalHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inputHash));
        mulsigauth(totalHash, v, r, s, msg.sender);
        pending_owner = who;
        nonce += 1;
    }

    function confirmOwner() external {
        require(msg.sender == pending_owner, "sender is not pending_owner");
        require(_add(msg.sender), "added address is already an owner");
        pending_owner = address(0);
    }

    //最高级别owner修改admin
    function proposeAdmin(address who) external {
        require(_indexof(msg.sender) != 0, "msg.sender is not sys owner");
        pending_admin = who;
    }

    function confirmAdmin() external {
        require(msg.sender == pending_admin, "sender is not pending_admin");
        admin = msg.sender;
        pending_admin = address(0);
    }

    function replace(address who) external {
        require(msg.sender == pending_owner, "sender is not pending_owner");
        require(_add(msg.sender), "added address is already an owner");
        require(_remove(who), "removed address is not owner");
        pending_owner = address(0);
    }

    function remove(
        uint8[] calldata v,
        bytes32[] calldata r,
        bytes32[] calldata s,
        address who
    ) external {
        bytes32 inputHash = keccak256(abi.encode(who, msg.sender, nonce));
        bytes32 totalHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inputHash));
        mulsigauth(totalHash, v, r, s, msg.sender);
        require(_remove(who), "removed address is not owner");
        require(_size() >= owners_size, "invalid size and weights");
        nonce += 1;
    }

    function updateOwnerSize(
        uint8[] calldata v,
        bytes32[] calldata r,
        bytes32[] calldata s,
        uint256 _owners_size
    ) external {
        bytes32 inputHash = keccak256(abi.encode(_owners_size, msg.sender, nonce));
        bytes32 totalHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", inputHash));
        mulsigauth(totalHash, v, r, s, msg.sender);
        nonce += 1;
        owners_size = _owners_size;
        require(_size() >= owners_size, "invalid size and weights");
    }

    //添加访问控制: 允许 @who 访问 @code 的所有方法
    function enable(address sender, address to, bytes4 sig) external auth {
        facl[sender][to][sig] = true;
    }

    function disable(address sender, address to, bytes4 sig) external auth {
        facl[sender][to][sig] = false;
    }

    function enableany(address sender, address to) external auth {
        cacl[sender][to] = true;
    }

    function enableboth(address sender, address to) external auth {
        cacl[sender][to] = true;
        cacl[to][sender] = true;
    }

    function disableany(address sender, address to) external auth {
        cacl[sender][to] = false;
    }

    function _add(address value) internal returns (bool) {
        if (_owners_set.indexes[value] != 0) return false;
        _owners_set.addresses.push(value);
        _owners_set.indexes[value] = _owners_set.addresses.length;
        return true;
    }

    function _remove(address value) internal returns (bool) {
        if (_owners_set.indexes[value] == 0) return false;

        uint256 _i = _owners_set.indexes[value];
        address _popv = _owners_set.addresses[_size() - 1];

        _owners_set.addresses[_i - 1] = _popv;
        _owners_set.addresses.pop();

        _owners_set.indexes[_popv] = _i;
        delete _owners_set.indexes[value];

        return true;
    }

    function _size() internal view returns (uint256) {
        return _owners_set.addresses.length;
    }

    function _indexof(address owner) internal view returns (uint256) {
        return _owners_set.indexes[owner];
    }
}
