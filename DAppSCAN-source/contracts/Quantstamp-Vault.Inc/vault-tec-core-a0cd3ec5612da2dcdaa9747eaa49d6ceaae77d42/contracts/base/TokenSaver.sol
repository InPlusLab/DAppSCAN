// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";

contract TokenSaver is AccessControlEnumerable {
    using SafeERC20 for IERC20;

    bytes32 public constant TOKEN_SAVER_ROLE = keccak256("TOKEN_SAVER_ROLE");

    event TokenSaved(address indexed by, address indexed receiver, address indexed token, uint256 amount);

    modifier onlyTokenSaver() {
        require(hasRole(TOKEN_SAVER_ROLE, _msgSender()), "TokenSaver.onlyTokenSaver: permission denied");
        _;
    }

    constructor() {
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
    }

    function saveToken(address _token, address _receiver, uint256 _amount) external onlyTokenSaver {
        IERC20(_token).safeTransfer(_receiver, _amount);
        emit TokenSaved(_msgSender(), _receiver, _token, _amount);
    }

}