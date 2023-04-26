// SPDX-License-Identifier: MIT

pragma solidity 0.8.12;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockKeeperMulticall is Initializable, AccessControlUpgradeable {
    using SafeERC20 for IERC20;

    bytes32 public constant KEEPER_ROLE = keccak256("KEEPER_ROLE");

    //solhint-disable-next-line
    address private constant _oneInch = 0x1111111254fb6c44bAC0beD2854e76F90643097d;

    struct Action {
        address target;
        bytes data;
        bool isDelegateCall;
    }

    event LogAction(address indexed target, bytes data);
    event SentToMiner(uint256 indexed value);
    event Recovered(address indexed tokenAddress, address indexed to, uint256 amount);

    error AmountOutTooLow(uint256 amount, uint256 min);
    error BalanceTooLow();
    error FlashbotsErrorPayingMiner(uint256 value);
    error IncompatibleLengths();
    error RevertBytes();
    error ZeroAddress();

    constructor() initializer {}

    function initialize(address keeper) public initializer {
        __AccessControl_init();

        _setupRole(KEEPER_ROLE, keeper);
        _setRoleAdmin(KEEPER_ROLE, KEEPER_ROLE);
    }
}
