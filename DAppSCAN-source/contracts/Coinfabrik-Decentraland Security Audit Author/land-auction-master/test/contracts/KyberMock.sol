pragma solidity ^0.4.24;

import "contracts/dex/IKyberNetwork.sol";

contract KyberMock is IKyberNetwork {
    uint256 constant public rate_MANA_NCH = 1262385660474240000; // 1.262 - 18 decimals
    uint256 constant public rate_MANA_DCL = 2562385660474240000; // 2.562 - 18 decimals
    uint256 public rate_NCH_MANA = 792150949832820000; // 100 / rate_NCH_MANA
    uint256 public rate_DCL_MANA = 390261316017091100; // 100 / rate_DCL_MANA

    address public nchToken;
    address public dclToken;
    mapping(address => uint256) public decimals;

    constructor(address[] _erc20, uint256[] _decimals) public {
        for (uint i = 0; i < _erc20.length; i++ ) {
            if (i == 0) {
                nchToken = _erc20[i];
            } else {
                dclToken = _erc20[i];
            }
            decimals[_erc20[i]] = _decimals[i];
        }
    }

    function trade(
        IERC20 _srcToken,
        uint /* _srcAmount */,
        IERC20 _destToken,
        address _destAddress, 
        uint _maxDestAmount,	
        uint _minConversionRate,	
        address /*_walletId*/
    ) public payable returns(uint256) {
        uint256 rate;
        (, rate) = getExpectedRate(_destToken, _srcToken, _maxDestAmount);
        require(rate >= _minConversionRate, "Rate is to low");
        uint256 destAmount = convertRate(
            _maxDestAmount, 
            rate, 
            _destToken, 
            _srcToken
        );
        _srcToken.transferFrom(msg.sender, this, destAmount);
        _destToken.transfer(_destAddress, _maxDestAmount);
        return _maxDestAmount;
    }

    function convertRate(
        uint256 _amount, 
        uint256 _rate, 
        address _srcToken, 
        address _destToken
    )
    internal view returns (uint256) 
    {
        uint256 srcDecimals = decimals[_srcToken];
        uint256 toDecimals = 18; // Default decimal

        if (_destToken == nchToken || _destToken == dclToken) {
            toDecimals = decimals[_destToken];
            srcDecimals = 18;
        }

        if (toDecimals >= srcDecimals) {
            return (_amount * (_rate * 10**(toDecimals - srcDecimals))) / 10**18;
        } else {
            return ((_amount * _rate / 10**18) / 10**(srcDecimals - toDecimals)) ;
        }
    }

    function getExpectedRate(IERC20 _srcToken, IERC20 _destToken, uint256 /*_srcAmount*/) 
        public view returns(uint256, uint256) 
    {
        if (_srcToken == nchToken) {
            return (rate_NCH_MANA, rate_NCH_MANA);
        } else if (_srcToken == dclToken) {
            return (rate_DCL_MANA, rate_DCL_MANA);
        } else if (_destToken == nchToken) {
            return (rate_MANA_NCH, rate_MANA_NCH);
        } else if (_destToken == dclToken) {
            return (rate_MANA_DCL, rate_MANA_DCL);
        }
        revert("invalid rate");
    }

    function getReturn(IERC20 _srcToken, IERC20 _destToken, uint256 _srcAmount) 
    public view returns (uint256) 
    {
        uint256 rate;
        (, rate) = getExpectedRate(_srcToken, _destToken, _srcAmount);
        return convertRate(_srcAmount, rate, _srcToken, _destToken);
    }
}