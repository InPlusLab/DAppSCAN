pragma solidity 0.5.16;
import "openzeppelin-solidity-2.3.0/contracts/ownership/Ownable.sol";
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";
import "openzeppelin-solidity-2.3.0/contracts/utils/ReentrancyGuard.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-core/contracts/libraries/Math.sol";
import "./uniswap/IUniswapV2Router02.sol";
import "./SafeToken.sol";
import "./Strategy.sol";


contract StrategyAllETHOnly is Ownable, ReentrancyGuard, Strategy {
    using SafeToken for address;
    using SafeMath for uint256;

    IUniswapV2Factory public factory;
    IUniswapV2Router02 public router;
    address public weth;

    /// @dev Create a new add ETH only strategy instance.
    /// @param _router The Uniswap router smart contract.
    constructor(IUniswapV2Router02 _router) public {
        factory = IUniswapV2Factory(_router.factory());
        router = _router;
        weth = _router.WETH();
    }

    /// @dev Execute worker strategy. Take LP tokens + ETH. Return LP tokens + ETH.
    /// @param data Extra calldata information passed along to this strategy.
    function execute(address /* user */, uint256 /* debt */, bytes calldata data)
        external
        payable
        nonReentrant
    {
        // 1. Find out what farming token we are dealing with and min additional LP tokens.
        (address fToken, uint256 minLPAmount) = abi.decode(data, (address, uint256));
        IUniswapV2Pair lpToken = IUniswapV2Pair(factory.getPair(fToken, weth));
        // 2. Compute the optimal amount of ETH to be converted to farming tokens.
        uint256 balance = address(this).balance;
        (uint256 r0, uint256 r1, ) = lpToken.getReserves();
        uint256 rIn = lpToken.token0() == weth ? r0 : r1;
        uint256 aIn = Math.sqrt(rIn.mul(balance.mul(3988000).add(rIn.mul(3988009)))).sub(rIn.mul(1997)) / 1994;
        // 3. Convert that portion of ETH to farming tokens.
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = fToken;
        router.swapExactETHForTokens.value(aIn)(0, path, address(this), now);
        // 4. Mint more LP tokens and return all LP tokens to the sender.
        fToken.safeApprove(address(router), 0);
        fToken.safeApprove(address(router), uint(-1));
        (,, uint256 moreLPAmount) = router.addLiquidityETH.value(address(this).balance)(
            fToken, fToken.myBalance(), 0, 0, address(this), now
        );
        require(moreLPAmount >= minLPAmount, "insufficient LP tokens received");
        lpToken.transfer(msg.sender, lpToken.balanceOf(address(this)));
    }

    /// @dev Recover ERC20 tokens that were accidentally sent to this smart contract.
    /// @param token The token contract. Can be anything. This contract should not hold ERC20 tokens.
    /// @param to The address to send the tokens to.
    /// @param value The number of tokens to transfer to `to`.
    function recover(address token, address to, uint256 value) external onlyOwner nonReentrant {
        token.safeTransfer(to, value);
    }

    function() external payable {}
}
