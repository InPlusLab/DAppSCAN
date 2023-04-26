// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./token/SafeBEP20.sol";
import "./interfaces/IBEP20.sol";
import "./interfaces/IPancakePair.sol";
import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/ISimplichef.sol";
import "./interfaces/IZap.sol";
import "./interfaces/IWBNB.sol";

contract Broker {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    event Deposit(address indexed sender, uint amount, uint balance);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event ZapInTokenAndDeposit(address _from, uint256[] _pid, uint256[] _amounts);
    event ZapInBNBAndDeposit(uint256[] _pid, uint256[] _amounts);
    event WithdrawAndZapOut(address _to, uint256[] _pid, uint256[] _amounts);

    IZap public zap;
    ISimplichef public simplichef;
    address WBNB;

    constructor (IZap _zap, ISimplichef _simplichef, address _wbnb) {
        zap = _zap;
        simplichef = _simplichef;
        WBNB = _wbnb;
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value, address(this).balance);
    }

    function _approveTokenForZap(address token, uint256 wantAmt) private {
        uint256 curAllowance = IBEP20(token).allowance(address(this), address(zap));
        if (curAllowance < wantAmt) {
                IBEP20(token).safeIncreaseAllowance(address(zap), wantAmt.sub(curAllowance));
        }
    }


    function _approveTokenForSimpliChef(address token, uint256 wantAmt) private {
        uint256 curAllowance = IBEP20(token).allowance(address(this), address(simplichef));
        if (curAllowance < wantAmt) {
                IBEP20(token).safeIncreaseAllowance(address(zap), wantAmt.sub(curAllowance));
        }
    }


    // zapAndDeposit
    function zapInTokenAndDeposit(
        address _from,
        uint256[] memory _pid,
        uint256[] memory _amounts
    ) external {
        require(_amounts.length == _pid.length, "Amount and pid lengths don't match");
        uint256 sumAmount = 0;
        for (uint256 i=0; i < _amounts.length; i++){
            sumAmount = sumAmount.add(_amounts[i]);
        }
        _approveTokenForZap(_from, sumAmount);
        IBEP20(_from).safeTransferFrom(msg.sender, address(this), sumAmount);
        for (uint256 i=0; i < _amounts.length; i++) {
            address _to = simplichef.poolAddress(_pid[i]);
            (, , uint256 LPAmount) = zap.zapInToken(_from, _amounts[i], _to);
            _approveTokenForSimpliChef(_to, LPAmount);
            simplichef.depositOnlyBroker(_pid[i], LPAmount, msg.sender);
        }
        emit ZapInTokenAndDeposit(_from, _pid, _amounts);
    }

    function zapInBNBAndDeposit(
        uint256[] memory _pid,
        uint256[] memory _amounts
    ) external payable {
        require(_amounts.length == _pid.length, "Amount and pid lengths don't match");
        uint256 sumAmount = 0;

        for (uint256 i=0; i < _amounts.length; i++) {
            address _to = simplichef.poolAddress(_pid[i]);
            sumAmount = sumAmount.add(_amounts[i]);
            (, , uint256 LPAmount) = zap.zapIn{value : _amounts[i]}(_to);
            _approveTokenForSimpliChef(_to, LPAmount);
            simplichef.depositOnlyBroker(_pid[i], LPAmount, msg.sender);
        }
        require(sumAmount == msg.value, "Amount unmatched");
        emit ZapInBNBAndDeposit(_pid, _amounts);
    }

    function withdrawAndZapOut(
        address _to,
        uint256[] memory _pid,
        uint256[] memory _amounts
    ) external {
        require(_pid.length == _amounts.length, "Address and pid lengths don't match");
        uint256 totalAmount = 0;
        for (uint256 i=0; i < _amounts.length; i++) {
            uint256 LPAmount = simplichef.withdrawOnlyBroker(_pid[i], _amounts[i], msg.sender);
            address from = simplichef.poolAddress(_pid[i]);
            _approveTokenForZap(from, LPAmount);
            totalAmount = totalAmount.add(zap.zapOutToToken(from, LPAmount, _to));
        }
        if (_to == WBNB) {
            IWBNB(_to).withdraw(totalAmount);
            (bool sent, ) = msg.sender.call{ value: totalAmount }("");
            require(sent, "Failed to send BNB");
        } else {
            IBEP20(_to).safeTransfer(msg.sender, totalAmount);
        }
        emit WithdrawAndZapOut(_to, _pid, _amounts);
    }
}
