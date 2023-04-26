// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IDetailedERC20} from "../interfaces/IDetailedERC20.sol";
import {ERC20Mock} from "./ERC20Mock.sol";

contract I3ESPoolMock {
    using SafeMath for uint256;

    ERC20Mock public token;

    mapping(uint256 => address) public coins;

    mapping(uint256 => uint256) public liquidity;

    constructor(ERC20Mock _token, uint256[3] memory _indexes, address[3] memory _coins) public {
        require(address(_token) != address(0));
        token = _token;
        for (uint i = 0; i < 3; i++) {
            address _coin = _coins[i];
            require(_coin != address(0), "coin should not be address 0");
            coins[_indexes[i]] = _coin;
        }
    }
    
    function add_liquidity(uint256[3] calldata _amounts, uint256 _minAmount) external {
        uint256 tokenAmount = this.calc_token_amount(_amounts, true);
        require(tokenAmount <= _minAmount);
        for (uint i=0; i<3; i++) {
            if (_amounts[i] > 0) {
                liquidity[i] = liquidity[i].add(_amounts[i]);
                IDetailedERC20(coins[i]).transferFrom(msg.sender, address(this), _amounts[i]);
            }
        }
        token.mint(msg.sender, tokenAmount);
    }

    function remove_liquidity_one_coin(uint256 _share, int128 _index, uint256 _minAmount) external {
        uint256 tokenAmount = this.calc_withdraw_one_coin(_share, _index);
        require(tokenAmount <= _minAmount);
        liquidity[uint256(_index)] = liquidity[uint256(_index)].sub(_share);
        token.burn(msg.sender, _share);
        SafeERC20.safeTransfer(IDetailedERC20(coins[uint256(_index)]), msg.sender, tokenAmount);
    }

    function calc_token_amount(uint256[3] calldata _params, bool _isDeposited) external view returns (uint256) {
        uint256 tokenAmount = 0;
        for (uint i=0; i<3; i++) {
            tokenAmount = tokenAmount.add(_params[i]);
        }
        return tokenAmount;
    }

    function calc_withdraw_one_coin(uint256 _share, int128 _index) external view returns (uint256) {
        if (liquidity[uint256(_index)] == 0) {
            return 0;
        }
        return _share;
    }
}