pragma solidity 0.4.25;

import "./helpers/ManagerRole.sol";


/// @title TimviSettings
contract TimviSettings is ManagerRole {

    event MinDepositUpdated(uint256 _value);
    event SysFeeUpdated(uint256 _value);
    event UserFeeUpdated(uint256 _value);
    event TotalFeeUpdated(uint256 _value);
    event GlobalSafetyBagUpdated(uint256 _value);
    event GasPriceLimitUpdated(uint256 _value);

    uint256 public minDeposit;
    uint256 public sysFee;
    uint256 public userFee;

    uint256 public gasPriceLimit;

    uint256 public globalSafetyBag;

    uint256 public totalFee;
    address public oracleAddress;
    address public tmvAddress;

    constructor() public {
        minDeposit = 50 finney;
        sysFee = 3000; // 3%
        userFee = 3000; // 3%
        globalSafetyBag = 34783; // 34,783%
        totalFee = 6000; //6%
        gasPriceLimit = 0.02 szabo; // 20 GWei

        emit MinDepositUpdated(minDeposit);
        emit SysFeeUpdated(sysFee);
        emit UserFeeUpdated(userFee);
        emit TotalFeeUpdated(totalFee);
        emit GlobalSafetyBagUpdated(globalSafetyBag);
        emit GasPriceLimitUpdated(gasPriceLimit);
    }

    function setMinDepo(uint256 _value) external onlyFeeManager {
        require(_value > 0 && _value < 10 ether, "Value out of range");
        minDeposit = _value;
        emit MinDepositUpdated(minDeposit);
    }

    function setSysCom(uint256 _value) external onlyFeeManager {
        require(_value <= totalFee / 2, "Value out of range");
        sysFee = _value;
        userFee = totalFee - _value;
        emit SysFeeUpdated(sysFee);
        emit UserFeeUpdated(userFee);
    }

    function setFeeTotal(uint256 _totalFee, uint256 _sysFee) external onlyFeeManager {
        require(_totalFee > 1000 && _totalFee <= 6000, "Value out of range");
        require(_sysFee <= _totalFee / 2, "Value out of range");
        totalFee = _totalFee;
        sysFee = _sysFee;
        userFee = totalFee - _sysFee;
        emit TotalFeeUpdated(totalFee);
        emit SysFeeUpdated(sysFee);
        emit UserFeeUpdated(userFee);
    }

    function setOracleAddress(address _addr) external onlyFeeManager {
        require(_addr != address(0), "Zero address");
        oracleAddress = _addr;
    }

    function setGasPriceLimit(uint256 _limit) external onlyFeeManager {
        require(_limit > 0.005 szabo, "Gas price limit must be greater than 5 GWei");
        gasPriceLimit = _limit;
        emit GasPriceLimitUpdated(gasPriceLimit);
    }

    function setSafetyBag(uint256 _bag) external onlyFeeManager {
        require(_bag <= 100000, "Value out of range");
        globalSafetyBag = _bag;
        emit GlobalSafetyBagUpdated(globalSafetyBag);
    }

    function setTmvAddress(address _addr) external onlySettingsManager {
        require(_addr != address(0), "Zero address");
        tmvAddress = _addr;
    }

    function minStability() public view returns(uint256) {
        return 100000 + totalFee;
    }

    function maxStability() public view returns(uint256) {
        return minStability() * 150 / 23 / 100 + minStability();
    }

    function ratio() public view returns(uint256) {
        return minStability() * 50 / 23 / 100 + maxStability();
    }

    function globalTargetCollateralization() public view returns(uint256) {
        return ratio() + globalSafetyBag;
    }
}
