// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

contract DepositorCollateral is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice Max number of depositors.
    uint256 public maxSize;

    /**
     * @notice Locked tokens.
     */
    mapping(address => uint256) public totalSupply;

    /**
     * @dev Depositors list.
     */
    mapping(address => EnumerableSet.AddressSet) internal _depositors;

    /**
     * @dev Depositors balances.
     */
    mapping(address => mapping(address => uint256)) internal _balances;

    /// @notice An event emitted when collateral locked.
    event Lock(address token, address depositor, uint256 amount);

    /// @notice An event emitted when collateral withdraw.
    event Withdraw(address token, address depositor, uint256 amount);

    /**
     * @param _maxSize Max number of depositors.
     */
    constructor(uint256 _maxSize) public {
        maxSize = _maxSize;
    }

    /**
     * @notice Get depositors.
     * @param token Collateral token.
     * @return Addresses of all depositors.
     */
    function getDepositors(address token) public view returns (address[] memory) {
        address[] memory result = new address[](_depositors[token].length());

        for (uint256 i = 0; i < _depositors[token].length(); i++) {
            result[i] = _depositors[token].at(i);
        }

        return result;
    }

    /**
     * @notice Get balance of depositor.
     * @param token Target token.
     * @param depositor Target depositor.
     * @return Balance of depositor.
     */
    function balanceOf(address token, address depositor) public view returns (uint256) {
        return _balances[token][depositor];
    }

    /**
     * @notice Lock depositor collateral.
     * @param token Locked token.
     * @param depositor Depositor address.
     * @param amount Locked amount.
     */
    function lock(
        address token,
        address depositor,
        uint256 amount
    ) external onlyOwner {
        require(amount > 0, "DepositorCollateral::lock: empty amount");
        _depositors[token].add(depositor);
        require(_depositors[token].length() <= maxSize, "DepositorCollateral::lock: too many depositors");

        ERC20(token).safeTransferFrom(depositor, address(this), amount);
        _balances[token][depositor] = _balances[token][depositor].add(amount);
        totalSupply[token] = totalSupply[token].add(amount);
        emit Lock(token, depositor, amount);
    }

    /**
     * @notice Withdraw depositor collateral.
     * @param token Withdraw token.
     * @param depositor Depositor address.
     * @param amount Withdraw amount.
     */
    function withdraw(
        address token,
        address depositor,
        uint256 amount
    ) external onlyOwner {
        require(amount > 0, "DepositorCollateral::withdraw: empty amount");
        require(balanceOf(token, depositor) >= amount, "DepositorCollateral::withdraw: negative balance");

        _balances[token][depositor] = _balances[token][depositor].sub(amount);
        if (_balances[token][depositor] == 0) {
            _depositors[token].remove(depositor);
        }
        totalSupply[token] = totalSupply[token].sub(amount);
        ERC20(token).safeTransfer(depositor, amount);
        emit Withdraw(token, depositor, amount);
    }
}
