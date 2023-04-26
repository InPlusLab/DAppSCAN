// SPDX-License-Identifier: GPL-3.0
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/MatrixPoolInterface.sol";
import "./interfaces/MatrixPoolFactoryInterface.sol";

contract MatrixPoolActions {
  struct Args {
    uint256 minWeightPerSecond;
    uint256 maxWeightPerSecond;
    uint256 swapFee;
    uint256 communitySwapFee;
    uint256 communityJoinFee;
    uint256 communityExitFee;
    address communityFeeReceiver;
    bool finalize;
  }

  struct TokenConfig {
    address token;
    uint256 balance;
    uint256 targetDenorm;
    uint256 fromTimestamp;
    uint256 targetTimestamp;
  }

  function create(
    MatrixPoolFactoryInterface factory,
    string calldata name,
    string calldata symbol,
    Args calldata args,
    TokenConfig[] calldata tokens
  ) external returns (MatrixPoolInterface pool) {
    pool = factory.newPool(name, symbol, address(this), args.minWeightPerSecond, args.maxWeightPerSecond);
    pool.setSwapFee(args.swapFee);
    pool.setCommunityFeeAndReceiver(
      args.communitySwapFee,
      args.communityJoinFee,
      args.communityExitFee,
      args.communityFeeReceiver
    );

    for (uint256 i = 0; i < tokens.length; i++) {
      TokenConfig memory tokenConfig = tokens[i];
      IERC20 token = IERC20(tokenConfig.token);
      require(token.transferFrom(msg.sender, address(this), tokenConfig.balance), "ERR_TRANSFER_FAILED");
      if (token.allowance(address(this), address(pool)) > 0) {
        token.approve(address(pool), 0);
      }
      token.approve(address(pool), tokenConfig.balance);
      pool.bind(
        tokenConfig.token,
        tokenConfig.balance,
        tokenConfig.targetDenorm,
        tokenConfig.fromTimestamp,
        tokenConfig.targetTimestamp
      );
    }

    if (args.finalize) {
      pool.finalize();
      require(pool.transfer(msg.sender, pool.balanceOf(address(this))), "ERR_TRANSFER_FAILED");
    }

    pool.setController(msg.sender);
  }
}
