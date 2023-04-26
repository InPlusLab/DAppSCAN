pragma solidity ^0.5.2;

interface UniswapV2Library {
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
}

contract Oracle {
    function read() external view returns (bytes32) {
        address _router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

        uint256 _amountIn = 1e18;

        address[] memory _path = new address[](2);
        _path[0] = 0x431ad2ff6a9C365805eBaD47Ee021148d6f7DBe0; // DF
        _path[1] = 0xeb269732ab75A6fD61Ea60b06fE994cD32a83549; // USDx
        // Rinkeby:
        // _path[0] = 0x5d378961e9D31C0ee394d34741fa1A18144f6Fb5; // DF
        // _path[1] = 0xdBCFff49D5F48DDf6e6df1f2C9B96E1FC0F31371; // USDx

        uint[] memory amounts = UniswapV2Library(_router).getAmountsOut(_amountIn, _path);
        if (amounts[1] != uint256(0)) {
            return bytes32(amounts[1]);
        }
        return bytes32(uint256(0.1e15));
    }
}
