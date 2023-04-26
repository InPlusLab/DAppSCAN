pragma solidity ^0.5.16;

import "./ERC20.sol";
import "../../contracts/CCapableErc20.sol";
import "../../contracts/SafeMath.sol";

// FlashloanReceiver is a simple flashloan receiver implementation for testing
contract FlashloanReceiver is IFlashloanReceiver {
    using SafeMath for uint256;

    function doFlashloan(address cToken, uint borrowAmount, uint repayAmount) external {
        uint balanceBefore = ERC20(CCapableErc20(cToken).underlying()).balanceOf(address(this));
        bytes memory data = abi.encode(cToken, borrowAmount, repayAmount);
        CCapableErc20(cToken).flashLoan(address(this), borrowAmount, data);
        uint balanceAfter = ERC20(CCapableErc20(cToken).underlying()).balanceOf(address(this));
        require(balanceAfter == balanceBefore.add(borrowAmount).sub(repayAmount), "Balance inconsistent");
    }

    function executeOperation(address sender, address underlying, uint amount, uint fee, bytes calldata params) external {
      (address cToken, uint borrowAmount, uint repayAmount) = abi.decode(params, (address, uint, uint));
      require(underlying == CCapableErc20(cToken).underlying(), "Params not match");
      require(amount == borrowAmount, "Params not match");
      require(ERC20(underlying).transfer(cToken, repayAmount), "Transfer fund back failed");
    }
}

contract FlashloanAndMint is IFlashloanReceiver {
    using SafeMath for uint256;

    function doFlashloan(address cToken, uint borrowAmount) external {
        bytes memory data = abi.encode(cToken);
        CCapableErc20(cToken).flashLoan(address(this), borrowAmount, data);
    }

    function executeOperation(address sender, address underlying, uint amount, uint fee, bytes calldata params) external {
        address cToken = abi.decode(params, (address));
        CCapableErc20(cToken).mint(amount.add(fee));
    }
}

contract FlashloanAndRepayBorrow is IFlashloanReceiver {
    using SafeMath for uint256;

    function doFlashloan(address cToken, uint borrowAmount) external {
        bytes memory data = abi.encode(cToken);
        CCapableErc20(cToken).flashLoan(address(this), borrowAmount, data);
    }

    function executeOperation(address sender, address underlying, uint amount, uint fee, bytes calldata params) external {
        address cToken = abi.decode(params, (address));
        CCapableErc20(cToken).repayBorrow(amount.add(fee));
    }
}

contract FlashloanTwice is IFlashloanReceiver {
    using SafeMath for uint256;

    function doFlashloan(address cToken, uint borrowAmount) external {
        bytes memory data = abi.encode(cToken);
        CCapableErc20(cToken).flashLoan(address(this), borrowAmount, data);
    }

    function executeOperation(address sender, address underlying, uint amount, uint fee, bytes calldata params) external {
        address cToken = abi.decode(params, (address));
        CCapableErc20(cToken).flashLoan(address(this), amount, params);
    }
}
