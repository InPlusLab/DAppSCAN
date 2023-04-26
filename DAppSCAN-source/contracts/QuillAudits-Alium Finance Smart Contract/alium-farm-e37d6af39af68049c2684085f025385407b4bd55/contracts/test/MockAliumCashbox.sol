// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockAliumCashbox is Initializable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Calcs {
        uint256 totalLimit;
        uint256 withdrawn;
    }

    mapping(address => Calcs) public allowedList;

    address public almToken;

    address public withdrawAdmin;

    function initialize(address _token, address _aliumCashAdmin)
        public
        initializer
    {
        require(_token != address(0), "token address!");
        require(_aliumCashAdmin != address(0), "admin address!");
        almToken = _token;
    }

    function setWalletLimit(address _wallet, uint256 _newLimit)
        public
    {
        require(_wallet != address(0) && _newLimit >= 0, "check input values!");
        allowedList[_wallet] = Calcs(_newLimit, 0);
    }

    function withdraw(uint256 _amount) external {
        if (
            allowedList[msg.sender].totalLimit == 0 &&
            allowedList[msg.sender].withdrawn == 0
        ) revert("You are not allowed to claim ALMs!");
        require(
            allowedList[msg.sender].totalLimit > 0,
            "Your limit is exhausted!"
        );
        require(
            allowedList[msg.sender].totalLimit >= _amount,
            "Your query exceeds your limit!"
        );

        allowedList[msg.sender].totalLimit = allowedList[msg.sender]
        .totalLimit
        .sub(_amount);
        allowedList[msg.sender].withdrawn = allowedList[msg.sender]
        .withdrawn
        .add(_amount);

        IERC20(almToken).safeTransfer(msg.sender, _amount);
    }
}
