// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import '../../interfaces/IErc20InterfaceETH.sol';
import '../../interfaces/ICTokenInterface.sol';
import '../../interfaces/IWHT.sol';
import '../interfaces/ISafeBox.sol';

// Safebox vault, deposit, withdrawal, borrowing, repayment
contract SafeBoxCTokenImplETH is ERC20 {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IErc20InterfaceETH public eToken;
    ICTokenInterface public cToken;

    IWHT public iWHT = IWHT(0x5545153CCFcA01fbd7Dd11C0b23ba694D9509A6F);
    
    constructor (
        address _cToken
    ) public 
        ERC20(string(abi.encodePacked("bo-", iWHT.name())),
            string(abi.encodePacked("bo", iWHT.symbol()))) {
        _setupDecimals(ERC20(_cToken).decimals());
        eToken = IErc20InterfaceETH(_cToken);
        cToken = ICTokenInterface(_cToken);
        require(cToken.isCToken(), 'not ctoken address');
        require(eToken.isNativeToken(), 'not native token address');
        IERC20(baseToken()).approve(_cToken, uint256(-1));
    }

    receive() external payable {
    }

    function baseToken() public virtual view returns (address) {
        return address(iWHT);
    }

    function ctokenSupplyRatePerBlock() public virtual view returns (uint256) {
        return cToken.supplyRatePerBlock();
    }

    function ctokenBorrowRatePerBlock() public virtual view returns (uint256) {
        return cToken.borrowRatePerBlock();
    }

    function call_balanceOf(address _token, address _account) public virtual view returns (uint256 balance) {
        balance = IERC20(_token).balanceOf(_account);
    }
    
    function call_balanceOfCToken_this() public virtual view returns (uint256 balance) {
        balance = call_balanceOf(address(cToken), address(this));
    }    
    
    function call_balanceOfBaseToken_this() public virtual returns (uint256) {
        return call_balanceOfCToken_this().mul(cToken.exchangeRateCurrent()).div(1e18);
    }

    function call_borrowBalanceCurrent_this() public virtual returns (uint256) {
        return cToken.borrowBalanceCurrent(address(this));
    }

    function getBaseTokenPerCToken() public virtual view returns (uint256) {
        return cToken.exchangeRateStored();
    }

    function ctokenDeposit(uint256 _value) internal virtual returns (uint256 lpAmount) {
        iWHT.withdraw(_value);
        require(address(this).balance >= _value, 'wht deposit withdraw error');
        uint256 cBalanceBefore = call_balanceOf(address(cToken), address(this));
        eToken.mint{value:_value}();
        uint256 cBalanceAfter = call_balanceOf(address(cToken), address(this));
        lpAmount = cBalanceAfter.sub(cBalanceBefore);
    }
    
    function ctokenWithdraw(uint256 _lpAmount) internal virtual returns (uint256 amount) {
        uint256 cBalanceBefore = address(this).balance;
        require(eToken.redeem(_lpAmount) == 0, 'withdraw supply ctoken error');
        uint256 cBalanceAfter = address(this).balance;
        amount = cBalanceAfter.sub(cBalanceBefore);
        iWHT.deposit{value:amount}();
    }

    function ctokenClaim(uint256 _lpAmount) internal virtual returns (uint256 value) {
        return ctokenWithdraw(_lpAmount);
    }

    function ctokenBorrow(uint256 _value) internal virtual {
        require(eToken.borrow(_value) == 0, 'borrow error');
        iWHT.deposit{value:_value}();
    }

    function ctokenRepayBorrow(uint256 _value) internal virtual {
        iWHT.withdraw(_value);
        require(address(this).balance >= _value, 'wht repayborrow withdraw error');
        eToken.repayBorrow{value:_value}();
    }
}
