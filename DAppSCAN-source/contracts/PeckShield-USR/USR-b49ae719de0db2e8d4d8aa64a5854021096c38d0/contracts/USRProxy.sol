pragma solidity 0.5.12;

contract Proxy {
    function () payable external {
        _fallback();
    }

    function _implementation() internal view returns (address);

    function _delegate(address _implementation) internal {
        assembly {
            calldatacopy(0, 0, calldatasize)

            let _result := delegatecall(gas, _implementation, 0, calldatasize, 0, 0)
            returndatacopy(0, 0, returndatasize)

            switch _result
            case 0 { revert(0, returndatasize) }
            default { return(0, returndatasize) }
        }
    }

    function _willFallback() internal {
    }

    function _fallback() internal {
        _willFallback();
        _delegate(_implementation());
    }
}

library AddressUtils {

    function isContract(address _addr) internal view returns (bool) {
        uint256 _size;

        assembly { _size := extcodesize(_addr) }
        return _size > 0;
    }

}

contract UpgradeabilityProxy is Proxy {
    event Upgraded(address implementation);

    bytes32 private constant IMPLEMENTATION_SLOT = 0x7050c9e0f4ca769c69bd3a8ef740bc37934f8e2c036e5a723fd8ee048ed3f8c3;

    constructor(address _implementation) public {
        assert(IMPLEMENTATION_SLOT == keccak256("org.zeppelinos.proxy.implementation"));

        _setImplementation(_implementation);
    }

    function _implementation() internal view returns (address _impl) {
        bytes32 _slot = IMPLEMENTATION_SLOT;
        assembly {
            _impl := sload(_slot)
        }
    }

    function _upgradeTo(address _newImplementation) internal {
        _setImplementation(_newImplementation);
        emit Upgraded(_newImplementation);
    }

    function _setImplementation(address _newImplementation) private {
        require(AddressUtils.isContract(_newImplementation), "Cannot set a proxy implementation to a non-contract address");

        bytes32 _slot = IMPLEMENTATION_SLOT;

        assembly {
            sstore(_slot, _newImplementation)
        }
    }
}

contract AdminUpgradeabilityProxy is UpgradeabilityProxy {

    event AdminChanged(address previousAdmin, address newAdmin);
    event AdminUpdated(address newAdmin);

    bytes32 private constant ADMIN_SLOT = 0x10d6a54a4754c8869d6886b5f5d7fbfa5b4522237ea5c60d11bc4e7a1ff9390b;
    bytes32 private constant PENDING_ADMIN_SLOT = 0x54ac2bd5363dfe95a011c5b5a153968d77d153d212e900afce8624fdad74525c;

    modifier ifAdmin() {
        if (msg.sender == _admin()) {
            _;
        }/* else {
        _fallback();
        }*/
    }

    constructor(address _implementation) UpgradeabilityProxy(_implementation) public {
        assert(ADMIN_SLOT == keccak256("org.zeppelinos.proxy.admin"));

        _setAdmin(msg.sender);
    }

    function admin() external view ifAdmin returns (address) {
        return _admin();
    }

    function pendingAdmin() external view ifAdmin returns (address) {
        return _pendingAdmin();
    }

    function implementation() external view ifAdmin returns (address) {
        return _implementation();
    }

    function changeAdmin(address _newAdmin) external ifAdmin {
        require(_newAdmin != address(0), "Cannot change the admin of a proxy to the zero address");
        require(_newAdmin != _admin(), "The current and new admin cannot be the same .");
        require(_newAdmin != _pendingAdmin(), "Cannot set the newAdmin of a proxy to the same address .");
        _setPendingAdmin(_newAdmin);
        emit AdminChanged(_admin(), _newAdmin);
    }

    function updateAdmin() external {
        address _newAdmin = _pendingAdmin();
        require(_newAdmin != address(0), "Cannot change the admin of a proxy to the zero address");
        require(msg.sender == _newAdmin, "msg.sender and newAdmin must be the same .");
        _setAdmin(_newAdmin);
        _setPendingAdmin(address(0));
        emit AdminUpdated(_newAdmin);
    }

    function upgradeTo(address _newImplementation) external ifAdmin {
        _upgradeTo(_newImplementation);
    }

    function upgradeToAndCall(address _newImplementation, bytes calldata _data) payable external ifAdmin {
        _upgradeTo(_newImplementation);
        (bool _success,) = address(this).call.value(msg.value)(_data);
        require(_success, "upgradeToAndCall-error");
    }

    function _admin() internal view returns (address _adm) {
        bytes32 _slot = ADMIN_SLOT;
        assembly {
            _adm := sload(_slot)
        }
    }

    function _pendingAdmin() internal view returns (address _pendingAdm) {
        bytes32 _slot = PENDING_ADMIN_SLOT;
        assembly {
            _pendingAdm := sload(_slot)
        }
    }

    function _setAdmin(address _newAdmin) internal {
        bytes32 _slot = ADMIN_SLOT;

        assembly {
            sstore(_slot, _newAdmin)
        }
    }

    function _setPendingAdmin(address _pendingAdm) internal {
        bytes32 _slot = PENDING_ADMIN_SLOT;

        assembly {
            sstore(_slot, _pendingAdm)
        }
    }

    function _willFallback() internal {
        // require(msg.sender != _admin(), "Cannot call fallback function from the proxy admin");
        super._willFallback();
    }
}

contract USRProxy is AdminUpgradeabilityProxy {
    constructor(address _implementation) public AdminUpgradeabilityProxy(_implementation) {
    }
}
