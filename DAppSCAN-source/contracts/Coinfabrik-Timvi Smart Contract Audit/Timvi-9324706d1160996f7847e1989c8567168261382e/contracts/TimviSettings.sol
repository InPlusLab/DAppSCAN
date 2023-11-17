pragma solidity 0.5.11;

import "./helpers/ManagerRole.sol";


/// @title TimviSettings
contract TimviSettings is ManagerRole {

    event MIN_DEPO_UPDATED(uint256 _value);
    event SYS_COMM_UPDATED(uint256 _value);
    event USER_COMM_UPDATED(uint256 _value);
    event FEE_TOTAL_UPDATED(uint256 _value);
    event GLOBAL_SAFETY_BAG_UPDATED(uint256 _value);

    uint256 public MIN_DEPO;
    uint256 public SYS_COMM;
    uint256 public USER_COMM;
    uint256 public COMM_DIVIDER;

    uint256 public GLOBAL_SAFETY_BAG;

    uint256 public FEE_TOTAL;
    address public oracleAddress;
    address public tmvAddress;

    constructor() public {
        MIN_DEPO = 50 finney;
        SYS_COMM = 3000; // 3%
        USER_COMM = 3000; // 3%
        COMM_DIVIDER = 100000;
        GLOBAL_SAFETY_BAG = 34783; // 34,783%
        FEE_TOTAL = 6000; //6%

        emit MIN_DEPO_UPDATED(MIN_DEPO);
        emit SYS_COMM_UPDATED(SYS_COMM);
        emit USER_COMM_UPDATED(USER_COMM);
        emit FEE_TOTAL_UPDATED(FEE_TOTAL);
        emit GLOBAL_SAFETY_BAG_UPDATED(GLOBAL_SAFETY_BAG);
    }

    function setMinDepo(uint256 _value) external onlyFeeManager {
        require(_value > 0 && _value < 10 ether, "Value out of range");
        MIN_DEPO = _value;
        emit MIN_DEPO_UPDATED(MIN_DEPO);
    }

    function setSysCom(uint256 _value) external onlyFeeManager {
        require(_value <= FEE_TOTAL / 2, "Value out of range");
        SYS_COMM = _value;
        USER_COMM = FEE_TOTAL - _value;
        emit SYS_COMM_UPDATED(SYS_COMM);
        emit USER_COMM_UPDATED(USER_COMM);
    }

    function setFeeTotal(uint256 _totalFee, uint256 _sysFee) external onlyFeeManager {
        require(_totalFee > 1000 && _totalFee <= 6000, "Value out of range");
        require(_sysFee <= _totalFee / 2, "Value out of range");
        FEE_TOTAL = _totalFee;
        SYS_COMM = _sysFee;
        USER_COMM = FEE_TOTAL - _sysFee;
        emit FEE_TOTAL_UPDATED(FEE_TOTAL);
        emit SYS_COMM_UPDATED(SYS_COMM);
        emit USER_COMM_UPDATED(USER_COMM);
    }

    function setOracleAddress(address _addr) external onlyFeeManager {
        require(_addr != address(0), "Zero address");
        oracleAddress = _addr;
    }

    function setSafetyBag(uint256 _bag) external onlyFeeManager {
        require(_bag <= 100000, "Value out of range");
        GLOBAL_SAFETY_BAG = _bag;
        emit GLOBAL_SAFETY_BAG_UPDATED(GLOBAL_SAFETY_BAG);
    }

    function setTmvAddress(address _addr) external onlySettingsManager {
        require(_addr != address(0), "Zero address");
        tmvAddress = _addr;
    }

    function minStability() public view returns(uint256) {
        return 100000 + FEE_TOTAL;
    }

    function maxStability() public view returns(uint256) {
        return minStability() * 150 / 23 / 100 + minStability();
    }

    function ratio() public view returns(uint256) {
        return minStability() * 50 / 23 / 100 + maxStability();
    }

    function globalTargetCollateralization() public view returns(uint256) {
        return ratio() + GLOBAL_SAFETY_BAG;
    }
}
