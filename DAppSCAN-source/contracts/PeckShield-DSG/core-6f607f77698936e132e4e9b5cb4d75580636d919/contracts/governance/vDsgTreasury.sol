// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IDsgToken.sol";
import "../libraries/SwapLibrary.sol";
import "../interfaces/ISwapRouter02.sol";

interface IvDsg {
    function donate(uint256 dsgAmount) external;
}

contract vDsgTreasury is Ownable {
    using SafeERC20 for IERC20;

    event Swap(address token0, address token1, uint256 amountIn, uint256 amountOut);

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private _callers;

    address public factory;
    address public vdsg;
    address public dsg;

    constructor(address _factory, address _dsg, address _vdsg) public {
        factory = _factory;
        dsg = _dsg;
        vdsg = _vdsg;
    }

    function sendToVDSG() external onlyCaller {
        uint256 _amount = IDsgToken(dsg).balanceOf(address(this));

        require(_amount > 0, "vDsgTreasury: amount exceeds balance");

        IDsgToken(dsg).approve(vdsg, _amount);
        IvDsg(vdsg).donate(_amount);
    }

    function _swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        address _to
    ) internal returns (uint256 amountOut) {
        address pair = SwapLibrary.pairFor(factory, _tokenIn, _tokenOut);
        (uint256 reserve0, uint256 reserve1, ) = ISwapPair(pair).getReserves();

        (uint256 reserveInput, uint256 reserveOutput) =
            _tokenIn == ISwapPair(pair).token0() ? (reserve0, reserve1) : (reserve1, reserve0);
        amountOut = SwapLibrary.getAmountOut(_amountIn, reserveInput, reserveOutput);
        IERC20(_tokenIn).safeTransfer(pair, _amountIn);

        _tokenIn == ISwapPair(pair).token0()
            ? ISwapPair(pair).swap(0, amountOut, _to, new bytes(0))
            : ISwapPair(pair).swap(amountOut, 0, _to, new bytes(0));

        emit Swap(_tokenIn, _tokenOut, _amountIn, amountOut);
    }

    function anySwap(address _tokenIn, address _tokenOut, uint256 _amountIn) external onlyCaller {
        _swap(_tokenIn, _tokenOut, _amountIn, address(this));
    }

    function anySwapAll(address _tokenIn, address _tokenOut) public onlyCaller {
        uint256 _amountIn = IERC20(_tokenIn).balanceOf(address(this));
        if(_amountIn == 0) {
            return;
        }
        _swap(_tokenIn, _tokenOut, _amountIn, address(this));
    }

    function batchAnySwapAll(address[] memory _tokenIns, address[] memory _tokenOuts) public onlyCaller {
        require(_tokenIns.length == _tokenOuts.length, "lengths not match");
        for (uint i = 0; i < _tokenIns.length; i++) {
            anySwapAll(_tokenIns[i], _tokenOuts[i]);
        }
    }

    function emergencyWithdraw(address _token) public onlyOwner {
        require(IERC20(_token).balanceOf(address(this)) > 0, "vDsgTreasury: insufficient contract balance");
        IERC20(_token).transfer(msg.sender, IERC20(_token).balanceOf(address(this)));
    }

    function addCaller(address _newCaller) public onlyOwner returns (bool) {
        require(_newCaller != address(0), "vDsgTreasury: address is zero");
        return EnumerableSet.add(_callers, _newCaller);
    }

    function delCaller(address _delCaller) public onlyOwner returns (bool) {
        require(_delCaller != address(0), "vDsgTreasury: address is zero");
        return EnumerableSet.remove(_callers, _delCaller);
    }

    function getCallerLength() public view returns (uint256) {
        return EnumerableSet.length(_callers);
    }

    function isCaller(address _caller) public view returns (bool) {
        return EnumerableSet.contains(_callers, _caller);
    }

    function getCaller(uint256 _index) public view returns (address) {
        require(_index <= getCallerLength() - 1, "vDsgTreasury: index out of bounds");
        return EnumerableSet.at(_callers, _index);
    }

    modifier onlyCaller() {
        require(isCaller(msg.sender), "vDsgTreasury: not the caller");
        _;
    }
}