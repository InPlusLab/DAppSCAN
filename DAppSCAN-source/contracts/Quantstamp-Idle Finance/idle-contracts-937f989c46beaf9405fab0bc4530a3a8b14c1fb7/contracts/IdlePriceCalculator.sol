/**
 * @title: Idle Price Calculator contract
 * @summary: Used for calculating the current IdleToken price in underlying (eg. DAI)
 *          price is: Net Asset Value / totalSupply
 * @author: William Bergamo, idle.finance
 */
pragma solidity 0.5.11;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./interfaces/iERC20Fulcrum.sol";
import "./interfaces/ILendingProtocol.sol";

contract IdlePriceCalculator {
  using SafeMath for uint256;
  /**
   * IdleToken price calculation, in underlying (eg. DAI)
   *
   * @return : price in underlying token
   */
  function tokenPrice(
    uint256 totalSupply,
    address idleToken,
    address[] calldata currentTokensUsed,
    address[] calldata protocolWrappersAddresses
  )
    external view
    returns (uint256 price) {
      if (totalSupply == 0) {
        return 10**18;
      }

      uint256 currPrice;
      uint256 currNav;
      uint256 totNav;

      for (uint8 i = 0; i < currentTokensUsed.length; i++) {
        currPrice = ILendingProtocol(protocolWrappersAddresses[i]).getPriceInToken();
        // NAV = price * poolSupply
        currNav = currPrice.mul(IERC20(currentTokensUsed[i]).balanceOf(idleToken));
        totNav = totNav.add(currNav);
      }

      price = totNav.div(totalSupply); // idleToken price in token wei
  }

}
