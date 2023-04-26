pragma solidity >=0.5.0;

contract Setter {
    function file(address) public;
    function file(uint) public;
    function file(bytes32, address) public;
    function file(bytes32, uint) public;
    function file(bytes32, bytes32) public;
    function file(bytes32, bytes32, uint) public;
    function file(bytes32, bytes32, address) public;
    function rely(address) public;
    function deny(address) public;
    function init(bytes32) public;
}

contract EndLike {
    function cage() public;
    function cage(bytes32) public;
}

contract PauseLike {
    function setAuthority(address) public;
    function setDelay(uint) public;
}

contract GovActions {
    function file(address who, address data) public {
        Setter(who).file(data);
    }

    function file(address who, uint data) public {
        Setter(who).file(data);
    }

    function file(address who, bytes32 what, address data) public {
        Setter(who).file(what, data);
    }

    function file(address who, bytes32 what, uint data) public {
        Setter(who).file(what, data);
    }

    function file(address who, bytes32 what, bytes32 data) public {
        Setter(who).file(what, data);
    }

    function file(address who, bytes32 ilk, bytes32 what, uint data) public {
        Setter(who).file(ilk, what, data);
    }

    function file(address who, bytes32 ilk, bytes32 what, address data) public {
        Setter(who).file(ilk, what, data);
    }

    function rely(address who, address to) public {
        Setter(who).rely(to);
    }

    function deny(address who, address to) public {
        Setter(who).deny(to);
    }

    function init(address who, bytes32 ilk) public {
        Setter(who).init(ilk);
    }

    function cage(address end) public {
        EndLike(end).cage();
    }

    function cage(address end, bytes32 ilk) public {
        EndLike(end).cage(ilk);
    }

    function setAuthority(address pause, address newAuthority) public {
        PauseLike(pause).setAuthority(newAuthority);
    }

    function setDelay(address pause, uint newDelay) public {
        PauseLike(pause).setDelay(newDelay);
    }

    function setAuthorityAndDelay(address pause, address newAuthority, uint newDelay) public {
        PauseLike(pause).setAuthority(newAuthority);
        PauseLike(pause).setDelay(newDelay);
    }
}
