// SPDX-License-Identifier: GPL-3
pragma solidity =0.7.6;

import '../interfaces/IImpossibleRouter01.sol';

contract RouterEventEmitter {
    event Amounts(uint256[] amounts);

    receive() external payable {}

    function swapExactTokensForTokens(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        (bool success, bytes memory returnData) =
            router.call(
                abi.encodeWithSelector(
                    IImpossibleRouter01(router).swapExactTokensForTokens.selector,
                    amountIn,
                    amountOutMin,
                    path,
                    to,
                    deadline
                )
            );
        assert(success);
        emit Amounts(abi.decode(returnData, (uint256[])));
    }

    function swapTokensForExactTokens(
        address router,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        (bool success, bytes memory returnData) =
            router.call(
                abi.encodeWithSelector(
                    IImpossibleRouter01(router).swapTokensForExactTokens.selector,
                    amountOut,
                    amountInMax,
                    path,
                    to,
                    deadline
                )
            );
        assert(success);
        emit Amounts(abi.decode(returnData, (uint256[])));
    }

    function swapExactETHForTokens(
        address router,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable {
        (bool success, bytes memory returnData) =
            router.call(
                abi.encodeWithSelector(
                    IImpossibleRouter01(router).swapExactETHForTokens.selector,
                    amountOutMin,
                    path,
                    to,
                    deadline
                )
            );
        assert(success);
        emit Amounts(abi.decode(returnData, (uint256[])));
    }

    function swapTokensForExactETH(
        address router,
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        (bool success, bytes memory returnData) =
            router.call(
                abi.encodeWithSelector(
                    IImpossibleRouter01(router).swapTokensForExactETH.selector,
                    amountOut,
                    amountInMax,
                    path,
                    to,
                    deadline
                )
            );
        assert(success);
        emit Amounts(abi.decode(returnData, (uint256[])));
    }

    function swapExactTokensForETH(
        address router,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external {
        (bool success, bytes memory returnData) =
            router.call(
                abi.encodeWithSelector(
                    IImpossibleRouter01(router).swapExactTokensForETH.selector,
                    amountIn,
                    amountOutMin,
                    path,
                    to,
                    deadline
                )
            );
        assert(success);
        emit Amounts(abi.decode(returnData, (uint256[])));
    }

    function swapETHForExactTokens(
        address router,
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable {
        (bool success, bytes memory returnData) =
            router.call(
                abi.encodeWithSelector(
                    IImpossibleRouter01(router).swapETHForExactTokens.selector,
                    amountOut,
                    path,
                    to,
                    deadline
                )
            );
        assert(success);
        emit Amounts(abi.decode(returnData, (uint256[])));
    }
}
