// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./token/SafeBEP20.sol";
import "./interfaces/IPancakePair.sol";
import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IZap.sol";
import "./interfaces/ISafeSwapBNB.sol";

contract ZapBSC is IZap, Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANT VARIABLES ========== */

    struct TradeInfoETH {
        address token;
        uint256 amountTokenDesired;
        uint256 amountTokenMin;
        uint256 amountETHMin;
        address to;
        uint256 deadline;
    }

    struct TradeInfoTokens {
        address tokenA;
        address tokenB;
        uint256 amountADesired;
        uint256 amountBDesired;
        uint256 amountAMin;
        uint256 amountBMin;
        address to;
        uint256 deadline;
    }

    address private constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c; // mainnet
    address private constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address private constant USDT = 0x55d398326f99059fF775485246999027B3197955;
    address private constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;
    address private constant USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;

    IPancakeRouter02 private constant ROUTER = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

    /* ========== STATE VARIABLES ========== */

    mapping(address => bool) private notFlip;
    mapping(address => address) private routePairAddresses;
    address[] public tokens;
    address public safeSwapBNB;

    event SetRoutePairAddress(address asset, address route);
    event SetNotFlip(address token);
    event RemoveToken(uint256 i);
    event Sweep();
    event Withdraw(address token);
    event SetSafeSwapBNB(address _safeSwapBNB);

    /* ========== INITIALIZER ========== */

    constructor() {
        setNotFlip(WBNB);
        setNotFlip(CAKE);
        setNotFlip(USDT);
        setNotFlip(BUSD);
        setNotFlip(USDC);
    }

    receive() external payable {}


    /* ========== View Functions ========== */

    function isFlip(address _address) public view returns (bool) {
        return !notFlip[_address];
    }

    function routePair(address _address) external view returns(address) {
        return routePairAddresses[_address];
    }

    /* ========== External Functions ========== */

    function zapInToken(address _from, uint256 amount, address _to) public override returns (uint256, uint256, uint256) {
        IBEP20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (isFlip(_to)) {
            IPancakePair pair = IPancakePair(_to);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (_from == token0 || _from == token1) {
                // swap half amount for other
                address other = _from == token0 ? token1 : token0;
                _approveTokenIfNeeded(other);
                uint256 sellAmount = amount.div(2);
                uint256 otherAmount = _swap(_from, sellAmount, other, address(this));
                TradeInfoTokens memory tradeInfo;
                tradeInfo = TradeInfoTokens(
                    _from, other, amount.sub(sellAmount), otherAmount, 0, 0, msg.sender, block.timestamp);
                return ROUTER.addLiquidity(
                    tradeInfo.tokenA,
                    tradeInfo.tokenB,
                    tradeInfo.amountADesired,
                    tradeInfo.amountBDesired,
                    tradeInfo.amountAMin,
                    tradeInfo.amountBMin,
                    tradeInfo.to,
                    tradeInfo.deadline
                );
            } else {
                uint256 bnbAmount = _from == WBNB ? _safeSwapToBNB(amount) : _swapTokenForBNB(_from, amount, address(this));
                return _swapBNBToFlip(_to, bnbAmount, msg.sender);
            }
        } else {
            uint256 swappedAmount = _swap(_from, amount, _to, msg.sender);
            return (0, 0, swappedAmount);
        }
    }

    function batchZapInToken(address _from, uint256[] memory _amounts, address[] memory _to) external {
        require(_amounts.length == _to.length, "Amounts and addresses don't match");
        for (uint256 i=0; i < _amounts.length; i++) {
            _approveTokenIfNeeded(_from);
            zapInToken(_from, _amounts[i], _to[i]);
        }
    }

    function zapIn(address _to) external payable override returns (uint256, uint256, uint256) {
        return _swapBNBToFlip(_to, msg.value, msg.sender);
    }

    function batchZapInBNB(uint256[] memory _amounts, address[] memory _to) external payable {
        require(_amounts.length == _to.length, "Amounts and addresses don't match");
        uint256 sumAmount = 0;

        for (uint256 i=0; i < _amounts.length; i++) {
            sumAmount = sumAmount.add(_amounts[i]);
            _swapBNBToFlip(_to[i], _amounts[i], msg.sender);
        }
        require(sumAmount == msg.value, "Amount unmatched");
    }

    function zapOut(address _from, uint256 amount) external override {
        IBEP20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (!isFlip(_from)) {
            _swapTokenForBNB(_from, amount, msg.sender);
        } else {
            IPancakePair pair = IPancakePair(_from);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WBNB || token1 == WBNB) {
                ROUTER.removeLiquidityETH(token0 != WBNB ? token0 : token1, amount, 0, 0, msg.sender, block.timestamp);
            } else {
                ROUTER.removeLiquidity(token0, token1, amount, 0, 0, msg.sender, block.timestamp);
            }
        }
    }

    function _swapTokenIfNotSame(address _from, uint256 _amount, address _to, address _receiver) private returns (uint256 receivedAmount) {
        if (_from != _to) {
            return _swap(_from, _amount, _to, _receiver);
        } else {
            IBEP20(_from).transfer(_receiver, _amount);
            return _amount;
        }
    }


    function zapOutToToken(address _from, uint256 amount, address _to) external override returns (uint256) {
        IBEP20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from);

        if (!isFlip(_from)) {
            return _swapTokenForBNB(_from, amount, msg.sender);
        } else {
            IPancakePair pair = IPancakePair(_from);
            address token0 = pair.token0();
            address token1 = pair.token1();
            _approveTokenIfNeeded(token0);
            _approveTokenIfNeeded(token1);
            (uint256 amount0, uint256 amount1) = ROUTER.removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp);
            return _swapTokenIfNotSame(token0, amount0, _to, msg.sender) + _swapTokenIfNotSame(token1, amount1, _to, msg.sender);
        }
    }

    /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token) private {
        if (IBEP20(token).allowance(address(this), address(ROUTER)) == 0) {
            IBEP20(token).safeApprove(address(ROUTER), type(uint256).max);
        }
    }

    function _swapBNBToFlip(
        address flip,
        uint256 amount,
        address receiver
    ) private returns (uint256 output0, uint256 output1, uint256 outputLP) {
        if (!isFlip(flip)) {
            _swapBNBForToken(flip, amount, receiver);
        } else {
            // flip
            IPancakePair pair = IPancakePair(flip);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WBNB || token1 == WBNB) {
                address token = token0 == WBNB ? token1 : token0;
                uint256 swapValue = amount.div(2);
                uint256 tokenAmount = _swapBNBForToken(token, swapValue, address(this));

                _approveTokenIfNeeded(token);
                TradeInfoETH memory tradeInfo;
                tradeInfo = TradeInfoETH(
                    token, tokenAmount, 0, 0, receiver, block.timestamp);
                return ROUTER.addLiquidityETH{value : amount.sub(swapValue)}(
                    tradeInfo.token,
                    tradeInfo.amountTokenDesired,
                    tradeInfo.amountTokenMin,
                    tradeInfo.amountETHMin,
                    tradeInfo.to,
                    tradeInfo.deadline
                );
            } else {
                uint256 swapValue = amount.div(2);
                uint256 token0Amount = _swapBNBForToken(token0, swapValue, address(this));
                uint256 token1Amount = _swapBNBForToken(token1, amount.sub(swapValue), address(this));

                _approveTokenIfNeeded(token0);
                _approveTokenIfNeeded(token1);
                TradeInfoTokens memory tradeInfo;
                tradeInfo = TradeInfoTokens(
                    token0, token1, token0Amount, token1Amount, 0, 0, receiver, block.timestamp);
                return ROUTER.addLiquidity(
                    tradeInfo.tokenA,
                    tradeInfo.tokenB,
                    tradeInfo.amountADesired,
                    tradeInfo.amountBDesired,
                    tradeInfo.amountAMin,
                    tradeInfo.amountBMin,
                    tradeInfo.to,
                    tradeInfo.deadline
                );
            }
        }
    }

    function _swapBNBForToken(address token, uint256 value, address receiver) private returns (uint256) {
        address[] memory path;

        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = WBNB;
            path[1] = routePairAddresses[token];
            path[2] = token;
        } else {
            path = new address[](2);
            path[0] = WBNB;
            path[1] = token;
        }

        uint256[] memory amounts = ROUTER.swapExactETHForTokens{value : value}(0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swapTokenForBNB(address token, uint256 amount, address receiver) private returns (uint256) {
        address[] memory path;
        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = token;
            path[1] = routePairAddresses[token];
            path[2] = WBNB;
        } else {
            path = new address[](2);
            path[0] = token;
            path[1] = WBNB;
        }

        uint256[] memory amounts = ROUTER.swapExactTokensForETH(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swap(address _from, uint256 amount, address _to, address receiver) private returns (uint256) {
        address intermediate = routePairAddresses[_from];
        if (intermediate == address(0)) {
            intermediate = routePairAddresses[_to];
        }

        address[] memory path;
        if (intermediate != address(0) && (_from == WBNB || _to == WBNB)) {
            // [WBNB, BUSD, VAI] or [VAI, BUSD, WBNB]
            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        } else if (intermediate != address(0) && (_from == intermediate || _to == intermediate)) {
            // [VAI, BUSD] or [BUSD, VAI]
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_from] == routePairAddresses[_to]) {
            // [VAI, DAI] or [VAI, USDC]
            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        } else if (routePairAddresses[_from] != address(0) && routePairAddresses[_to] != address(0) && routePairAddresses[_from] != routePairAddresses[_to]) {
            // routePairAddresses[xToken] = xRoute
            // [VAI, BUSD, WBNB, xRoute, xToken]
            path = new address[](5);
            path[0] = _from;
            path[1] = routePairAddresses[_from];
            path[2] = WBNB;
            path[3] = routePairAddresses[_to];
            path[4] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_from] != address(0)) {
            // [VAI, BUSD, WBNB, BUNNY]
            path = new address[](4);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = WBNB;
            path[3] = _to;
        } else if (intermediate != address(0) && routePairAddresses[_to] != address(0)) {
            // [BUNNY, WBNB, BUSD, VAI]
            path = new address[](4);
            path[0] = _from;
            path[1] = WBNB;
            path[2] = intermediate;
            path[3] = _to;
        } else if (_from == WBNB || _to == WBNB) {
            // [WBNB, BUNNY] or [BUNNY, WBNB]
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            // [USDT, BUNNY] or [BUNNY, USDT]
            path = new address[](3);
            path[0] = _from;
            path[1] = WBNB;
            path[2] = _to;
        }

        uint256[] memory amounts = ROUTER.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _safeSwapToBNB(uint256 amount) private returns (uint256) {
        require(IBEP20(WBNB).balanceOf(address(this)) >= amount, "Zap: Not enough WBNB balance");
        require(safeSwapBNB != address(0), "Zap: safeSwapBNB is not set");
        uint256 beforeBNB = address(this).balance;
        ISafeSwapBNB(safeSwapBNB).withdraw(amount);
        return (address(this).balance).sub(beforeBNB);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRoutePairAddress(address asset, address route) external onlyOwner {
        routePairAddresses[asset] = route;
        emit SetRoutePairAddress(asset, route);
    }

    function setNotFlip(address token) public onlyOwner {
        bool needPush = notFlip[token] == false;
        notFlip[token] = true;
        if (needPush) {
            tokens.push(token);
        }
        emit SetNotFlip(token);
    }

    function removeToken(uint256 i) external onlyOwner {
        address token = tokens[i];
        notFlip[token] = false;
        tokens[i] = tokens[tokens.length - 1];
        tokens.pop();
        emit RemoveToken(i);
    }

    function sweep() external onlyOwner {
        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(0)) continue;
            uint256 amount = IBEP20(token).balanceOf(address(this));
            if (amount > 0) {
                _swapTokenForBNB(token, amount, owner());
            }
        }
        emit Sweep();
    }

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IBEP20(token).transfer(owner(), IBEP20(token).balanceOf(address(this)));
        emit Withdraw(token);
    }

    function setSafeSwapBNB(address _safeSwapBNB) external onlyOwner {
        require(safeSwapBNB == address(0), "Zap: safeSwapBNB already set!");
        safeSwapBNB = _safeSwapBNB;
        IBEP20(WBNB).approve(_safeSwapBNB, type(uint256).max);
        emit SetSafeSwapBNB(_safeSwapBNB);
    }
}
