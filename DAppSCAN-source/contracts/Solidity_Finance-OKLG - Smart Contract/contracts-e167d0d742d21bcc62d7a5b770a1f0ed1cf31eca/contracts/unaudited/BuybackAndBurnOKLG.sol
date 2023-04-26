// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';
import '../OKLGWithdrawable.sol';

contract BuybackAndBurnOKLG is OKLGWithdrawable {
  address public constant DEAD = 0x000000000000000000000000000000000000dEaD;
  address public receiver = DEAD;
  address public oklg = 0x5dBB9F64cd96E2DbBcA58d14863d615B67B42f2e;
  IUniswapV2Router02 private router;

  constructor() {
    // PancakeSwap: 0x10ED43C718714eb63d5aA57B78B54704E256024E
    // Uniswap V2: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
    router = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
  }

  function buyAndBurn() external payable {
    require(msg.value > 0, 'Must send ETH to buy and burn OKLG');

    address[] memory path = new address[](2);
    path[0] = router.WETH();
    path[1] = oklg;

    router.swapExactETHForTokensSupportingFeeOnTransferTokens{
      value: msg.value
    }(
      0, // accept any amount of tokens
      path,
      receiver,
      block.timestamp
    );
  }

  function setOklg(address _oklg) external onlyOwner {
    oklg = _oklg;
  }

  function setReceiver(address _receiver) external onlyOwner {
    receiver = _receiver;
  }
}
