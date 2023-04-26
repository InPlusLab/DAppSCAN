// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IDetailedERC20} from "../interfaces/IDetailedERC20.sol";

contract IbBUSDMock is ERC20 {
    using SafeERC20 for IDetailedERC20;
    using SafeMath for uint256;

    uint256 public vaultDebtVal;
    uint256 public reservePool;
    uint256 public lastAccrueTime;

    IDetailedERC20 public token;

    constructor(IDetailedERC20 _token) public ERC20("ibBUSD Mock", "ibBUSDMOCK") {
        token = _token;
    }

    /// @dev Return the total token entitled to the token holders. Be careful of unaccrued interests.
    function totalToken() public view returns (uint256) {
        return token.balanceOf(address(this)).add(vaultDebtVal).sub(reservePool);
    }

    function deposit(uint256 _amount) external returns (uint256) {
        uint256 total = totalToken() == 0 ? 0 : totalToken().sub(_amount);
        uint256 share = total == 0 ? _amount : _amount.mul(totalSupply()).div(total);
        _mint(msg.sender, share);
        token.safeTransferFrom(msg.sender, address(this), _amount);
        require(totalSupply() > 1e17, "no tiny shares");
    }

    function withdraw(uint256 _shares) external returns (uint256) {
        uint256 _r = _shares.mul(totalToken()).div(totalSupply());
        _burn(msg.sender, _shares);

        // Check balance
        uint256 _b = token.balanceOf(address(this));
        if (_b <= _r) {
            uint256 _withdraw = _r.sub(_b);
            SafeERC20.safeTransfer(token, msg.sender, _r);
            uint256 _after = token.balanceOf(address(this));
            if (_after > _b) {
                uint256 _diff = _after.sub(_b);
                if (_diff < _withdraw) {
                    _r = _b.add(_diff);
                }
            }
        }
    }
}
