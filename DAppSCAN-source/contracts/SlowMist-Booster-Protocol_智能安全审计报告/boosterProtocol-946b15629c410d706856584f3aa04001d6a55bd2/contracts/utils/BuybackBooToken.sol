// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../../interfaces/IMdexRouter.sol";
import "../interfaces/IBuyback.sol";
import "./TenMath.sol";

contract BuybackBooToken is IBuyback {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IMdexRouter constant router = IMdexRouter(0xED7d5F38C79115ca12fe6C0041abb22F0A06C300);
    address public lockedAddr = address(0xfe5392013a4bA722CAf16FD116baaba8604Bb275);
    address public USDT = address(0xa71EdC38d189767582C38A3145b5873052c3e47a);
    address public booToken;

    mapping(address => uint256) public burnSource;
    mapping(address => uint256) public burnAmount;

    constructor(address _booToken) public {
        booToken = _booToken;
    }

    function setLockedAddr(address _lockedAddr) external {
        require(msg.sender == lockedAddr, 'prev one');
        lockedAddr = _lockedAddr;
    }

    function buyback(address _token, uint256 _value) external override returns (uint256 value) {
        uint256 decimals = uint256(ERC20(_token).decimals());
        if(_value < (10**decimals.div(4))) {
            return 0;
        }

        if(booToken == address(0)) {
            return 0;
        }

        address[] memory path;
        if (USDT != _token) {
            path = new address[](3);
            path[0] = _token;
            path[1] = USDT;
            path[2] = booToken;
        } else {
            path = new address[](2);
            path[0] = _token;
            path[1] = booToken;
        }

        uint256[] memory result;
        result = router.getAmountsOut(_value, path);
        if(result.length == 0 || result[result.length-1] <= 0) {
            return 0;
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _value);
        IERC20(_token).approve(address(router), _value);

        // SWC-114-Transaction Order Dependence: L66
        result = router.swapExactTokensForTokens(_value, 0, path, address(this), block.timestamp.add(60));
        if(result.length == 0) {
            return 0;
        }

        uint256 valueOut = TenMath.min(result[result.length-1],
                                IERC20(booToken).balanceOf(address(this)));

        burnSource[_token] = burnSource[_token].add(_value);
        burnAmount[_token] = burnAmount[_token].add(valueOut);

        IERC20(booToken).transfer(lockedAddr, valueOut);
    }
}