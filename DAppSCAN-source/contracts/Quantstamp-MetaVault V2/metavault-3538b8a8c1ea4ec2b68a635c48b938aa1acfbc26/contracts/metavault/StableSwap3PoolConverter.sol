// SPDX-License-Identifier: MIT
// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "./IConverter.sol";
import "./IVaultManager.sol";
import "./IStableSwap3Pool.sol";

contract StableSwap3PoolConverter is IConverter {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20[3] public tokens; // DAI, USDC, USDT
    IERC20 public token3CRV; // 3Crv

    IStableSwap3Pool public stableSwap3Pool;
    IVaultManager public vaultManager;

    mapping(address => bool) public strategies;

    constructor(
        IERC20 _tokenDAI,
        IERC20 _tokenUSDC,
        IERC20 _tokenUSDT,
        IERC20 _token3CRV,
        IStableSwap3Pool _stableSwap3Pool,
        IVaultManager _vaultManager
    ) public {
        tokens[0] = _tokenDAI;
        tokens[1] = _tokenUSDC;
        tokens[2] = _tokenUSDT;
        token3CRV = _token3CRV;
        stableSwap3Pool = _stableSwap3Pool;
        tokens[0].safeApprove(address(stableSwap3Pool), type(uint256).max);
        tokens[1].safeApprove(address(stableSwap3Pool), type(uint256).max);
        tokens[2].safeApprove(address(stableSwap3Pool), type(uint256).max);
        token3CRV.safeApprove(address(stableSwap3Pool), type(uint256).max);
        vaultManager = _vaultManager;
    }

    function setStableSwap3Pool(IStableSwap3Pool _stableSwap3Pool) external onlyGovernance {
        stableSwap3Pool = _stableSwap3Pool;
        tokens[0].safeApprove(address(stableSwap3Pool), type(uint256).max);
        tokens[1].safeApprove(address(stableSwap3Pool), type(uint256).max);
        tokens[2].safeApprove(address(stableSwap3Pool), type(uint256).max);
        token3CRV.safeApprove(address(stableSwap3Pool), type(uint256).max);
    }

    function setVaultManager(IVaultManager _vaultManager) external onlyGovernance {
        vaultManager = _vaultManager;
    }

    function setStrategy(address _strategy, bool _status) external onlyGovernance {
        strategies[_strategy] = _status;
    }

    function approveForSpender(
        IERC20 _token,
        address _spender,
        uint256 _amount
    ) external onlyGovernance {
        _token.safeApprove(_spender, _amount);
    }

    function token() external override returns (address) {
        return address(token3CRV);
    }

    function convert(
        address _input,
        address _output,
        uint256 _inputAmount
    ) external override onlyAuthorized returns (uint256 _outputAmount) {
        if (_output == address(token3CRV)) { // convert to 3CRV
            uint256[3] memory amounts;
            for (uint8 i = 0; i < 3; i++) {
                if (_input == address(tokens[i])) {
                    amounts[i] = _inputAmount;
                    uint256 _before = token3CRV.balanceOf(address(this));
                    stableSwap3Pool.add_liquidity(amounts, 1);
                    uint256 _after = token3CRV.balanceOf(address(this));
                    _outputAmount = _after.sub(_before);
                    token3CRV.safeTransfer(msg.sender, _outputAmount);
                    return _outputAmount;
                }
            }
        } else if (_input == address(token3CRV)) { // convert from 3CRV
            for (uint8 i = 0; i < 3; i++) {
                if (_output == address(tokens[i])) {
                    uint256 _before = tokens[i].balanceOf(address(this));
                    stableSwap3Pool.remove_liquidity_one_coin(_inputAmount, i, 1);
                    uint256 _after = tokens[i].balanceOf(address(this));
                    _outputAmount = _after.sub(_before);
                    tokens[i].safeTransfer(msg.sender, _outputAmount);
                    return _outputAmount;
                }
            }
        }
        return 0;
    }

    function convert_rate(
        address _input,
        address _output,
        uint256 _inputAmount
    ) external override view returns (uint256) {
        if (_output == address(token3CRV)) { // convert to 3CRV
            uint256[3] memory amounts;
            for (uint8 i = 0; i < 3; i++) {
                if (_input == address(tokens[i])) {
                    amounts[i] = _inputAmount;
                    return stableSwap3Pool.calc_token_amount(amounts, true);
                }
            }
        } else if (_input == address(token3CRV)) { // convert from 3CRV
            for (uint8 i = 0; i < 3; i++) {
                if (_output == address(tokens[i])) {
                    // @dev this is for UI reference only, the actual share price
                    // (stable/CRV) will be re-calculated on-chain when we do convert()
                    return stableSwap3Pool.calc_withdraw_one_coin(_inputAmount, i);
                }
            }
        }
        return 0;
    }

    // 0: DAI, 1: USDC, 2: USDT
    function convert_stables(
        uint256[3] calldata amounts
    ) external override onlyAuthorized returns (uint256 _shareAmount) {
        uint256 _before = token3CRV.balanceOf(address(this));
        stableSwap3Pool.add_liquidity(amounts, 1);
        uint256 _after = token3CRV.balanceOf(address(this));
        _shareAmount = _after.sub(_before);
        token3CRV.safeTransfer(msg.sender, _shareAmount);
    }

    function get_dy(int128 i, int128 j, uint256 dx) external override view returns (uint256) {
        return stableSwap3Pool.get_dy(i, j, dx);
    }

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external override onlyAuthorized returns (uint256 dy) {
        IERC20 _output = tokens[uint8(j)];
        uint256 _before = _output.balanceOf(address(this));
        stableSwap3Pool.exchange(i, j, dx, min_dy);
        uint256 _after = _output.balanceOf(address(this));
        dy = _after.sub(_before);
        _output.safeTransfer(msg.sender, dy);
    }

    function calc_token_amount(
        uint256[3] calldata amounts,
        bool deposit
    ) external override view returns (uint256 _shareAmount) {
        _shareAmount = stableSwap3Pool.calc_token_amount(amounts, deposit);
    }

    function calc_token_amount_withdraw(
        uint256 _shares,
        address _output
    ) external override view returns (uint256) {
        for (uint8 i = 0; i < 3; i++) {
            if (_output == address(tokens[i])) {
                return stableSwap3Pool.calc_withdraw_one_coin(_shares, i);
            }
        }
        return 0;
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyGovernance {
        _token.transfer(_to, _amount);
    }

    modifier onlyAuthorized() {
        require(vaultManager.vaults(msg.sender)
            || vaultManager.controllers(msg.sender)
            || strategies[msg.sender]
            || msg.sender == vaultManager.governance(),
            "!authorized"
        );
        _;
    }

    modifier onlyGovernance() {
        require(msg.sender == vaultManager.governance(), "!governance");
        _;
    }
}
