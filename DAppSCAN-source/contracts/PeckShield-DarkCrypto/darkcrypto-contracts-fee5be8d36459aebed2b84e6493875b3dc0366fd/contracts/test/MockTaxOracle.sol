// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MockTaxOracle is Ownable {
    using SafeMath for uint256;

    IERC20 public dark;
    IERC20 public wcro;
    address public pair;

    constructor(
        address _dark,
        address _wcro,
        address _pair
    ) public {
        require(_dark != address(0), "dark address cannot be 0");
        require(_wcro != address(0), "wcro address cannot be 0");
        require(_pair != address(0), "pair address cannot be 0");
        dark = IERC20(_dark);
        wcro = IERC20(_wcro);
        pair = _pair;
    }

    function consult(address _token, uint256 _amountIn) external view returns (uint144 amountOut) {
        require(_token == address(dark), "token needs to be dark");
        uint256 darkBalance = dark.balanceOf(pair);
        uint256 wcroBalance = wcro.balanceOf(pair);
        return uint144(darkBalance.div(wcroBalance));
    }

    function setDark(address _dark) external onlyOwner {
        require(_dark != address(0), "dark address cannot be 0");
        dark = IERC20(_dark);
    }

    function setWCro(address _wcro) external onlyOwner {
        require(_wcro != address(0), "wcro address cannot be 0");
        wcro = IERC20(_wcro);
    }

    function setPair(address _pair) external onlyOwner {
        require(_pair != address(0), "pair address cannot be 0");
        pair = _pair;
    }
}
