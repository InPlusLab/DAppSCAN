pragma solidity ^0.5.0;

import "./DSAuthority.sol";

contract DSAuthEvents {
    event LogSetAuthority(address indexed authority);
    event LogSetOwner(address indexed owner);
}

contract DSAuth is DSAuthEvents {
    DSAuthority public _authority;
    address public _owner;

    constructor() public {
        _owner = msg.sender;
        emit LogSetOwner(msg.sender);
    }

    function setOwner(address owner_) public auth {
        _owner = owner_;
        emit LogSetOwner(_owner);
    }

    function setAuthority(DSAuthority authority_) public auth {
        _authority = authority_;
        emit LogSetAuthority(address(_authority));
    }

    modifier auth {
        require(isAuthorized(msg.sender, msg.sig), "ds-auth-unauthorized");
        _;
    }

    function isAuthorized(address src, bytes4 sig)
        internal
        view
        returns (bool)
    {
        if (src == address(this)) {
            return true;
        } else if (src == _owner) {
            return true;
        } else if (_authority == DSAuthority(address(0))) {
            return false;
        } else {
            return _authority.canCall(src, address(this), sig);
        }
    }
}
