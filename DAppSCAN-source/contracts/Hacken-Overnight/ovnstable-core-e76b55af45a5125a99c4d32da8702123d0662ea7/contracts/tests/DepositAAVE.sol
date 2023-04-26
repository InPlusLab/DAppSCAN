// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "../connectors/aave/interfaces/ILendingPool.sol";
import "../connectors/aave/interfaces/ILendingPoolAddressesProvider.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Contract to learn how to deposit to AAVE
 */
contract DepositAAVE {
    function deposit(
        address _asset,
        uint256 _amount,
        address _ben,
        address _LPAP
    ) public payable {
        ILendingPoolAddressesProvider lpap = ILendingPoolAddressesProvider(_LPAP);
        ILendingPool pool = ILendingPool(lpap.getLendingPool());
        IERC20(_asset).transferFrom(msg.sender, address(this), _amount);
        IERC20(_asset).approve(address(pool), _amount);
        pool.deposit(_asset, _amount, _ben, 0);
    }
}
