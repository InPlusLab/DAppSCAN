pragma solidity =0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "../interfaces/IStrongHolder.sol";

contract SHPMock is IStrongHolder {
    using SafeERC20 for IERC20;

    address public rewardToken;

    event Locked(address to, uint256 amount);

    constructor(address _aliumToken) public {
        rewardToken = _aliumToken;
    }

    function lock(address _to, uint256 _amount) external override {
        IERC20(rewardToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        emit Locked(_to, _amount);
    }
}
