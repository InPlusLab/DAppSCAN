pragma solidity ^0.7.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IYVault is IERC20 {
    function token() external view returns (address);

    function deposit() external returns (uint256);

    function deposit(uint256 _amount) external returns (uint256);

    function deposit(uint256 _amount, address recipient)
        external
        returns (uint256);

    function withdraw() external returns (uint256);

    function withdraw(uint256 maxShares) external returns (uint256);

    function withdraw(uint256 maxShares, address recipient)
        external
        returns (uint256);

    function withdraw(
        uint256 maxShares,
        address recipient,
        uint256 maxLoss
    ) external returns (uint256);

    function pricePerShare() external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint256);
}
