pragma solidity ^0.5.2;

import './DSToken.sol';

contract DSWrappedToken is DSToken(bytes32(0)) {
    address private srcERC20;
    uint public srcDecimals;
    uint public multiple;
    bool public flag;

    constructor(address _srcERC20, uint _srcDecimals, bytes32 _symbol) public {
        srcERC20 = _srcERC20;
        srcDecimals = _srcDecimals;
        symbol = _symbol;
        _calMultiple();
    }

    function _calMultiple() internal {
        multiple = pow(10, sub(max(srcDecimals, decimals), min(srcDecimals, decimals)));
        flag = (srcDecimals > decimals);
    }

    function wrap(address _dst, uint _amount) public auth returns (uint) {
        uint _xAmount = changeByMultiple(_amount);
        mint(_dst, _xAmount);

        return _xAmount;
    }

    function unwrap(address _dst, uint _xAmount) public auth returns (uint) {
        burn(_dst, _xAmount);

        return _xAmount;
    }

    function changeByMultiple(uint _amount) public view returns (uint) {
        uint _xAmount = _amount;
        uint _multiple = multiple;

        if (flag)
            _xAmount = div(_amount, _multiple);
        else
            _xAmount = mul(_amount, _multiple);

        return _xAmount;
    }

    function reverseByMultiple(uint _xAmount) public view returns (uint) {
        uint _amount = _xAmount;
        uint _multiple = multiple;

        if (flag)
            _amount = mul(_xAmount, _multiple);
        else
            _amount = div(_xAmount, _multiple);

        return _amount;
    }

    function getSrcERC20() public view returns (address) {
        return srcERC20;
    }
}
