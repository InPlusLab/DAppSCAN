pragma solidity 0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/os/contracts/common/SafeERC20.sol";
import "@aragon/os/contracts/lib/token/ERC20.sol";
import "@ablack/fundraising-shared-interfaces/contracts/IAragonFundraisingController.sol";


contract AragonFundraisingControllerMock is IAragonFundraisingController, AragonApp {
    using SafeERC20 for ERC20;

    event OpenTrading();
    event ResetTokenTap();

    function initialize() external onlyInit {
        initialized();
    }

    function openTrading() external {
        emit OpenTrading();
    }

    function resetTokenTap(address _token) external {
        emit ResetTokenTap();
    }

    function collateralsToBeClaimed(address _collateral) public view returns (uint256) {
        if (_collateral == ETH) {
            return uint256(5);
        } else {
            return uint256(10);
        }
    }

    function balanceOf(address _who, address _token) public view returns (uint256) {
        if (_token == ETH) {
            return _who.balance;
        } else {
            return ERC20(_token).staticBalanceOf(_who);
        }
    }
}
