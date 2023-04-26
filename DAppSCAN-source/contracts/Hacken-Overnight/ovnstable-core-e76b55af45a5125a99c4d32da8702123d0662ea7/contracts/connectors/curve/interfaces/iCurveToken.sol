// SPDX-License-Identifier: MIT
pragma solidity >=0.5 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface iCurveToken is IERC20 {
    function mint(address _sender, uint256 amount) external;

    function burnFrom(address _sender, uint256 amount) external;
}
