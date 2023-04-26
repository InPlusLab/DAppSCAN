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

contract StrategyAddTwoSidesOptimal is Ownable, ReentrancyGuard, Strategy {
    using SafeToken for address;
    using SafeMath for uint256;

    IUniswapV2Factory public factory;
    IUniswapV2Router02 public router;
    address public weth;
    address public goblin;

    /// @dev Create a new add two-side optimal strategy instance.
    /// @param _router The Uniswap router smart contract.
    constructor(IUniswapV2Router02 _router, address _goblin) public {
        factory = IUniswapV2Factory(_router.factory());
        router = _router;
        weth = _router.WETH();
        goblin = _goblin;
    }
    
    /// @dev Throws if called by any account other than the goblin.
    modifier onlyGoblin() {
        require(isGoblin(), "caller is not the goblin");
        _;
    }

    /// @dev Returns true if the caller is the current goblin.
    function isGoblin() public view returns (bool) {
        return msg.sender == goblin;
    }

    /// @dev Compute optimal deposit amount
    /// @param amtA amount of token A desired to deposit
    /// @param amtB amonut of token B desired to deposit
    /// @param resA amount of token A in reserve
    /// @param resB amount of token B in reserve
    function optimalDeposit(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256 swapAmt, bool isReversed) {
        if (amtA.mul(resB) >= amtB.mul(resA)) {
            swapAmt = _optimalDepositA(amtA, amtB, resA, resB);
            isReversed = false;
        } else {
            swapAmt = _optimalDepositA(amtB, amtA, resB, resA);
            isReversed = true;
        }
    }

    /// @dev Compute optimal deposit amount helper
    /// @param amtA amount of token A desired to deposit
    /// @param amtB amonut of token B desired to deposit
    /// @param resA amount of token A in reserve
    /// @param resB amount of token B in reserve
    function _optimalDepositA(
        uint256 amtA,
        uint256 amtB,
        uint256 resA,
        uint256 resB
    ) internal pure returns (uint256) {
        require(amtA.mul(resB) >= amtB.mul(resA), "Reversed");

        uint256 a = 998;
        uint256 b = uint256(1998).mul(resA);
        uint256 _c = (amtA.mul(resB)).sub(amtB.mul(resA));
        uint256 c = _c.mul(1000).div(amtB.add(resB)).mul(resA);

        uint256 d = a.mul(c).mul(4);
        uint256 e = Math.sqrt(b.mul(b).add(d));

        uint256 numerator = e.sub(b);
        uint256 denominator = a.mul(2);

        return numerator.div(denominator);
    }

    /// @dev Execute worker strategy. Take LP tokens + ETH. Return LP tokens + ETH.
    /// @param user User address
    /// @param data Extra calldata information passed along to this strategy.
    function execute(address user, uint256, /* debt */ bytes calldata data) 
        external         
        payable  
        onlyGoblin       
        nonReentrant 
    {
        // 1. Find out what farming token we are dealing with.
        (address fToken, uint256 fAmount, uint256 minLPAmount) = abi.decode(data, (address, uint256, uint256));
        IUniswapV2Pair lpToken = IUniswapV2Pair(factory.getPair(fToken, weth));        
        // 2. Compute the optimal amount of ETH and fToken to be converted.  
        if (fAmount > 0) {  
            fToken.safeTransferFrom(user, address(this), fAmount);            
        }
        uint256 ethBalance = address(this).balance;
        uint256 swapAmt;
        bool isReversed;
        {
            (uint256 r0, uint256 r1, ) = lpToken.getReserves();
            (uint256 ethReserve, uint256 fReserve) = lpToken.token0() == weth ? (r0, r1) : (r1, r0);
            (swapAmt, isReversed) = optimalDeposit(ethBalance, fToken.myBalance(), ethReserve, fReserve);
        }
        // 3. Convert between ETH and farming tokens
        fToken.safeApprove(address(router), 0);
        fToken.safeApprove(address(router), uint256(-1));
        address[] memory path = new address[](2);
        (path[0], path[1]) = isReversed ? (fToken, weth) : (weth, fToken);
        if (isReversed) {
            router.swapExactTokensForETH(swapAmt, 0, path, address(this), now); // farming tokens to ETH
        } else {
            router.swapExactETHForTokens.value(swapAmt)(0, path, address(this), now); // ETH to farming tokens
        }
        // 4. Mint more LP tokens and return all LP tokens to the sender.
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
