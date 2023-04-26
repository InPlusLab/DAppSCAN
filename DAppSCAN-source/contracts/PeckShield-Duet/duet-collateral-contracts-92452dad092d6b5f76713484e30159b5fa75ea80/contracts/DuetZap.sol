// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import { IERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import "./interfaces/IPair.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IRouter02.sol";
import "./interfaces/IPancakeFactory.sol";
import "./interfaces/IController.sol";
import "./interfaces/IDYToken.sol";


contract DuetZap is OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    IRouter02 private router;
    IPancakeFactory private factory;
    address private wbnb;
    IController public controller;

    event ZapToLP(address token, uint amount, address lp, uint liquidity);

    /* ========== STATE VARIABLES ========== */
    mapping(address => address) private routePairAddresses;

    /* ========== INITIALIZER ========== */
    function initialize(address _controller, address _factory, address _router, address _wbnb) external initializer {
        __Ownable_init();
        require(owner() != address(0), "Zap: owner must be set");
        controller = IController(_controller);
        factory = IPancakeFactory(_factory);
        router = IRouter02(_router);
        wbnb = _wbnb;
    }

    receive() external payable {}

    /* ========== View Functions ========== */

    function routePair(address _address) external view returns(address) {
        return routePairAddresses[_address];
    }

    /* ========== External Functions ========== */
    function tokenToLp(address _token, uint amount, address _lp, bool needDeposit) external {
        address receiver = msg.sender;
        if (needDeposit) {
          receiver = address(this);
        }
        IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_token, address(router), amount);

        IPair pair = IPair(_lp);
        address token0 = pair.token0();
        address token1 = pair.token1();
        require(factory.getPair(token0, token1) == _lp, "NO_PAIR");

        uint liquidity;

        if (_token == token0 || _token == token1) {
            // swap half amount for other
            address other = _token == token0 ? token1 : token0;
            _approveTokenIfNeeded(other, address(router), amount);
            uint sellAmount = amount / 2;

            uint otherAmount = _swap(_token, sellAmount, other, address(this));
            pair.skim(address(this));

            (, , liquidity) = router.addLiquidity(_token, other, amount - sellAmount, otherAmount, 0, 0, receiver, block.timestamp);
        } else {
            uint bnbAmount = _token == wbnb ? _safeSwapToBNB(amount) : _swapTokenForBNB(_token, amount, address(this));
            liquidity = _swapBNBToLp(_lp, bnbAmount, receiver);
        }

        emit ZapToLP(_token, amount, _lp, liquidity);
        if (needDeposit) {
          deposit(_lp, liquidity, msg.sender);
        }

    }

    function coinToLp(address _lp, bool needDeposit) external payable returns (uint liquidity){
        if (!needDeposit) {
          liquidity = _swapBNBToLp(_lp, msg.value, msg.sender);
          emit ZapToLP(address(0), msg.value, _lp, liquidity);
        } else {
          liquidity = _swapBNBToLp(_lp, msg.value, address(this));
          emit ZapToLP(address(0), msg.value, _lp, liquidity);
          deposit(_lp, liquidity, msg.sender);
        }
    }

    function tokenToToken(address _token, uint _amount, address _to, bool needDeposit) external returns (uint amountOut){
      IERC20Upgradeable(_token).safeTransferFrom(msg.sender, address(this), _amount);
      _approveTokenIfNeeded(_token, address(router), _amount);
      
      if (needDeposit) {
        amountOut = _swap(_token, _amount, _to, address(this));
        deposit(_to, amountOut, msg.sender);
      } else {
        amountOut = _swap(_token, _amount, _to, msg.sender);
      }
    }

    // unpack lp 
    function zapOut(address _from, uint _amount) external {
        IERC20Upgradeable(_from).safeTransferFrom(msg.sender, address(this), _amount);
        _approveTokenIfNeeded(_from, address(router), _amount);

        IPair pair = IPair(_from);
        address token0 = pair.token0();
        address token1 = pair.token1();

        if (pair.balanceOf(_from) > 0) {
            pair.burn(address(this));
        }

        if (token0 == wbnb || token1 == wbnb) {
            router.removeLiquidityETH(token0 != wbnb ? token0 : token1, _amount, 0, 0, msg.sender, block.timestamp);
        } else {
            router.removeLiquidity(token0, token1, _amount, 0, 0, msg.sender, block.timestamp);
        }
    }

    /* ========== Private Functions ========== */
    function deposit(address token, uint amount, address toUser) private {
        address dytoken = controller.dyTokens(token);
        require(dytoken != address(0), "NO_DYTOKEN");
        address vault = controller.dyTokenVaults(dytoken);
        require(vault != address(0), "NO_VAULT");

        _approveTokenIfNeeded(token, dytoken, amount);
        IDYToken(dytoken).depositTo(toUser, amount, vault);
    }

    function _approveTokenIfNeeded(address token, address spender, uint amount) private {
        uint allowed = IERC20Upgradeable(token).allowance(address(this), spender);
        if (allowed == 0) {
            IERC20Upgradeable(token).safeApprove(spender, type(uint).max);
        } else if (allowed < amount) {
          IERC20Upgradeable(token).safeApprove(spender, 0);
          IERC20Upgradeable(token).safeApprove(spender, type(uint).max);
        }
                    
    }

    function _swapBNBToLp(address lp, uint amount, address receiver) private returns (uint liquidity) {
        IPair pair = IPair(lp);
        address token0 = pair.token0();
        address token1 = pair.token1();
        if (token0 == wbnb || token1 == wbnb) {
            address token = token0 == wbnb ? token1 : token0;
            uint swapValue = amount / 2;
            uint tokenAmount = _swapBNBForToken(token, swapValue, address(this));

            _approveTokenIfNeeded(token, address(router), tokenAmount);
            pair.skim(address(this));
            (, , liquidity) = router.addLiquidityETH{value : amount -swapValue }(token, tokenAmount, 0, 0, receiver, block.timestamp);
        } else {
            uint swapValue = amount / 2;
            uint token0Amount = _swapBNBForToken(token0, swapValue, address(this));
            uint token1Amount = _swapBNBForToken(token1, amount - swapValue, address(this));

            _approveTokenIfNeeded(token0, address(router), token0Amount);
            _approveTokenIfNeeded(token1, address(router), token1Amount);
            pair.skim(address(this));
            (, , liquidity) = router.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, receiver, block.timestamp);
        }
    }

    function _swapBNBForToken(address token, uint value, address receiver) private returns (uint) {
        address[] memory path;

        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = wbnb;
            path[1] = routePairAddresses[token];
            path[2] = token;
        } else {
            path = new address[](2);
            path[0] = wbnb;
            path[1] = token;
        }

        uint[] memory amounts = router.swapExactETHForTokens{value : value}(0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swapTokenForBNB(address token, uint amount, address receiver) private returns (uint) {
        address[] memory path;
        if (routePairAddresses[token] != address(0)) {
            path = new address[](3);
            path[0] = token;
            path[1] = routePairAddresses[token];
            path[2] = wbnb;
        } else {
            path = new address[](2);
            path[0] = token;
            path[1] = wbnb;
        }

        uint[] memory amounts = router.swapExactTokensForETH(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swap(address _from, uint amount, address _to, address receiver) private returns (uint) {
        address intermediate = routePairAddresses[_from];
        if (intermediate == address(0)) {
            intermediate = routePairAddresses[_to];
        }

        address[] memory path;

        if (intermediate == address(0) || _from == intermediate || _to == intermediate ) {
            // [DUET, BUSD] or [BUSD, DUET]
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            path = new address[](3);
            path[0] = _from;
            path[1] = intermediate;
            path[2] = _to;
        }

        uint[] memory amounts = router.swapExactTokensForTokens(amount, 0, path, receiver, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _safeSwapToBNB(uint amount) private returns (uint) {
        require(IERC20Upgradeable(wbnb).balanceOf(address(this)) >= amount, "Zap: Not enough wbnb balance");
        uint beforeBNB = address(this).balance;
        IWETH(wbnb).withdraw(amount);
        return address(this).balance - beforeBNB;
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setRoutePairAddress(address asset, address route) public onlyOwner {
        routePairAddresses[asset] = route;
    }

    function sweep(address[] memory tokens) external onlyOwner {
        for (uint i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            if (token == address(0)) continue;
            uint amount = IERC20Upgradeable(token).balanceOf(address(this));
            if (amount > 0) {
                _swapTokenForBNB(token, amount, owner());
            }
        }
    }

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20Upgradeable(token).transfer(owner(), IERC20Upgradeable(token).balanceOf(address(this)));
    }

}