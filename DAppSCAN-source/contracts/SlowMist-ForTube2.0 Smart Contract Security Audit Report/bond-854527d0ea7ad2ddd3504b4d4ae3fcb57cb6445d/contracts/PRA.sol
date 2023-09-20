pragma solidity >=0.6.0;

import "./SafeERC20.sol";


//professional rater authentication
//专业评级认证

interface IACL {
    function accessible(address sender, address to, bytes4 sig)
        external
        view
        returns (bool);
}


contract PRA {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    event MonitorEvent(
        address indexed who,
        address indexed bond,
        bytes32 indexed name,
        bytes
    );

    address public ACL;
    address public gov;
    uint256 public line;

    struct Lock {
        uint256 amount;
        bool reviewed;
    }

    mapping(address => Lock) public deposits;
    mapping(address => bool) public raters;

    modifier auth {
        IACL _ACL = IACL(ACL);
        require(
            _ACL.accessible(msg.sender, address(this), msg.sig),
            "PRA: access unauthorized"
        );
        _;
    }

    function setACL(address _ACL) external {
        require(msg.sender == ACL, "require ACL");
        ACL = _ACL;
    }

    constructor(address _ACL, address _gov, uint256 _line) public {
        ACL = _ACL;
        gov = _gov;
        line = _line;
    }

    function reline(uint256 _line) external auth {
        line = _line;
    }

    //固定锁仓@line数量的代币
    // SWC-107-Reentrancy: L66 - L80
    function lock() external {
        address who = msg.sender;
        require(deposits[who].amount == 0, "sender already locked");
        require(
            IERC20(gov).allowance(who, address(this)) >= line,
            "insufficient allowance to lock"
        );
        require(
            IERC20(gov).balanceOf(who) >= line,
            "insufficient balance to lock"
        );
        deposits[who].amount = line;
        IERC20(gov).safeTransferFrom(who, address(this), line);
        emit MonitorEvent(who, address(0), "lock", abi.encodePacked(line));
    }

    function set(address who, bool enable) external auth {
        require(deposits[who].amount >= line, "insufficient deposit token");

        if (enable)
            require(
                !raters[who],
                "set account already is a professional rater"
            );
        deposits[who].reviewed = true;
        raters[who] = enable;

        emit MonitorEvent(who, address(0), "set", abi.encodePacked(enable));
    }

    function unlock() external {
        address who = msg.sender;
        require(!raters[who], "raters is not broken");
        require(deposits[who].reviewed, "not submitted for review");
        uint256 amount = deposits[who].amount;
        deposits[who].reviewed = false;
        deposits[who].amount = 0;
        IERC20(gov).safeTransfer(who, amount);
        emit MonitorEvent(who, address(0), "unlock", abi.encodePacked(amount));
    }
}
