// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.12;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IAngleRouter.sol";
import "../interfaces/ICoreBorrow.sol";
import "../interfaces/ISwapper.sol";
import "../interfaces/external/lido/IWStETH.sol";
import "../interfaces/external/uniswap/IUniswapRouter.sol";

/// @title Swapper
/// @author Angle Core Team
/// @notice Swapper contract facilitating interactions with the VaultManager: to liquidate and get leverage
contract Swapper is ISwapper {
    using SafeERC20 for IERC20;

    // ================ Constants and Immutable Variables ==========================

    /// @notice Base used for parameter computation
    uint256 public constant BASE_PARAMS = 10**9;
    /// @notice AngleRouter
    IAngleRouter public immutable angleRouter;
    /// @notice Reference to the `CoreBorrow` contract of the module which handles all AccessControl logic
    ICoreBorrow public immutable core;
    /// @notice Wrapped StETH contract
    IWStETH public immutable wStETH;
    /// @notice Uniswap Router contract
    IUniswapV3Router public immutable uniV3Router;
    /// @notice 1Inch Router
    address public immutable oneInch;

    // =============================== Mappings ====================================

    /// @notice Whether the token was already approved on Uniswap router
    mapping(IERC20 => bool) public uniAllowedToken;
    /// @notice Whether the token was already approved on 1Inch
    mapping(IERC20 => bool) public oneInchAllowedToken;
    /// @notice Whether the token was already approved on AngleRouter
    mapping(IERC20 => bool) public angleRouterAllowedToken;

    // ================================== Enum =====================================

    /// @notice All possible swaps
    enum SwapType {
        UniswapV3,
        oneInch,
        Wrap,
        None
    }

    // ================================== Errors ===================================

    error EmptyReturnMessage();
    error IncompatibleLengths();
    error NotGovernorOrGuardian();
    error TooSmallAmount();
    error ZeroAddress();

    /// @notice Constructor of the contract
    /// @param _core Core address
    /// @param _wStETH wStETH Address
    /// @param _uniV3Router UniswapV3 Router address
    /// @param _oneInch 1Inch Router address
    /// @param _angleRouter Address of the AngleRouter contract
    constructor(
        ICoreBorrow _core,
        IWStETH _wStETH,
        IUniswapV3Router _uniV3Router,
        address _oneInch,
        IAngleRouter _angleRouter
    ) {
        if (
            address(_core) == address(0) ||
            address(_uniV3Router) == address(0) ||
            _oneInch == address(0) ||
            address(_angleRouter) == address(0)
        ) revert ZeroAddress();
        core = _core;
        IERC20 stETH = IERC20(_wStETH.stETH());
        stETH.safeApprove(address(_wStETH), type(uint256).max);
        wStETH = _wStETH;
        uniV3Router = _uniV3Router;
        oneInch = _oneInch;
        angleRouter = _angleRouter;
    }

    receive() external payable {}

    // ======================= External Access Function ============================

    /// @inheritdoc ISwapper
    /// @dev This function swaps the `inToken` to the `outToken` by either doing mint, or burn from the protocol
    /// or/and combining it with a UniV3 or 1Inch swap
    /// @dev No slippage checks are performed at the end of each operation, only one slippage check is performed
    /// at the end of the call
    /// @dev In this implementation, the function tries to make sure that the `outTokenRecipient` address has at the end
    /// of the call `outTokenOwed`, leftover tokens are sent to a `to` address which by default is the `outTokenRecipient`
    function swap(
        IERC20 inToken,
        IERC20 outToken,
        address outTokenRecipient,
        uint256 outTokenOwed,
        uint256 inTokenObtained,
        bytes memory data
    ) external {
        // Optional address that can be given to specify in case of a burn the address of the collateral
        // to get in exchange for the stablecoin or in case of a mint the collateral used to mint
        address intermediateToken;
        // Address to receive the surplus amount of token at the end of the call
        address to;
        // For slippage protection, it is checked at the end of the call
        uint256 minAmountOut;
        // Type of the swap to execute: if `swapType == 3`, then it is optional to swap
        uint128 swapType;
        // Whether a `mint` or `burn` operation should be performed beyond the swap: 1 corresponds
        // to a burn and 2 to a mint. It is optional. If the value is set to 1 or 2 then the value of the
        // `intermediateToken` should be made non null
        uint128 mintOrBurn;
        // We're reusing the `data` variable (it's now either a `path` on UniswapV3 or a payload for 1Inch)
        (intermediateToken, to, minAmountOut, swapType, mintOrBurn, data) = abi.decode(
            data,
            (address, address, uint256, uint128, uint128, bytes)
        );

        to = (to == address(0)) ? outTokenRecipient : to;

        if (mintOrBurn == 1) {
            // First performing burn transactions as you may usually get stablecoins first
            _checkAngleRouterAllowance(inToken);
            // In this case there cannot be any leftover `inToken`
            angleRouter.burn(address(this), inTokenObtained, 0, address(inToken), intermediateToken);
            inToken = IERC20(intermediateToken);
            inTokenObtained = inToken.balanceOf(address(this));
        }
        // Reusing the `inTokenObtained` variable
        inTokenObtained = _swap(inToken, inTokenObtained, SwapType(swapType), data);

        if (mintOrBurn == 2) {
            // Mint transaction is performed last as if you're trying to get stablecoins, it should be the last operation
            _checkAngleRouterAllowance(IERC20(intermediateToken));
            angleRouter.mint(address(this), inTokenObtained, 0, address(outToken), intermediateToken);
        }

        // A final slippage check is performed after the swaps
        uint256 outTokenBalance = outToken.balanceOf(address(this));
        if (outTokenBalance <= minAmountOut) revert TooSmallAmount();

        // The `outTokenRecipient` may already have enough in balance, in which case there's no need to transfer
        // this address the token and everything can be given already to the `to` address
        uint256 outTokenBalanceRecipient = outToken.balanceOf(outTokenRecipient);
        if (outTokenBalanceRecipient >= outTokenOwed || to == outTokenRecipient) outToken.safeTransfer(to, outTokenBalance);
        else {
            // The `outTokenRecipient` should receive the delta to make sure its end balance is equal to `outTokenOwed`
            // Any leftover in this case is sent to the `to` address
            // The function reverts if it did not obtain more than `outTokenOwed - outTokenBalanceRecipient` from the swap
            outToken.safeTransfer(outTokenRecipient, outTokenOwed - outTokenBalanceRecipient);
            outToken.safeTransfer(to, outTokenBalanceRecipient + outTokenBalance - outTokenOwed);
        }
        // Reusing the `inTokenObtained` variable for the `inToken` balance
        // Sending back the remaining amount of inTokens to the `to` address: it is possible that not the full `inTokenObtained`
        // is swapped to `outToken` if we're using the `1Inch` payload
        // If there has been a burn, the whole `inToken` balance is burnt, but in this case the `inToken` variable has the 
        // `intermediateToken` reference and what is sent back to the `to` address is the leftover balance of this token
        inTokenObtained = inToken.balanceOf(address(this));
        if (inTokenObtained > 0) inToken.safeTransfer(to, inTokenObtained);
    }

    // ========================= Governance Function ===============================

    /// @notice Changes allowance for a contract
    /// @param tokens Addresses of the tokens to allow
    /// @param spenders Addresses to allow transfer
    /// @param amounts Amounts to allow
    function changeAllowance(
        IERC20[] calldata tokens,
        address[] calldata spenders,
        uint256[] calldata amounts
    ) external {
        if (!core.isGovernorOrGuardian(msg.sender)) revert NotGovernorOrGuardian();
        if (tokens.length != spenders.length || tokens.length != amounts.length) revert IncompatibleLengths();
        for (uint256 i = 0; i < tokens.length; i++) {
            _changeAllowance(tokens[i], spenders[i], amounts[i]);
        }
    }

    // ======================= Internal Utility Functions ==========================

    /// @notice Internal version of the `_changeAllowance` function
    function _changeAllowance(
        IERC20 token,
        address spender,
        uint256 amount
    ) internal {
        uint256 currentAllowance = token.allowance(address(this), spender);
        if (currentAllowance < amount) {
            token.safeIncreaseAllowance(spender, amount - currentAllowance);
        } else if (currentAllowance > amount) {
            token.safeDecreaseAllowance(spender, currentAllowance - amount);
            // Clean mappings if allowance decreases for Uniswap, 1Inch or Angle routers
            if (spender == address(uniV3Router)) delete uniAllowedToken[token];
            else if (spender == oneInch) delete oneInchAllowedToken[token];
            else if (spender == address(angleRouter)) delete angleRouterAllowedToken[token];
        }
    }

    /// @notice Performs a swap using either Uniswap, 1Inch. This function can also stake stETH to wstETH
    /// @param inToken Token to swap
    /// @param amount Amount of tokens to swap
    /// @param swapType Type of the swap to perform
    /// @param args Extra args for the swap: in the case of Uniswap it should be a path, for 1Inch it should be
    /// a payload
    /// @dev If `swapType` is a wrap, then the `inToken` should be `stETH` otherwise the function will revert
    /// @dev This function does nothing if `swapType` is None and it simply passes on the `amount` it received
    function _swap(
        IERC20 inToken,
        uint256 amount,
        SwapType swapType,
        bytes memory args
    ) internal returns (uint256 amountOut) {
        if (swapType == SwapType.UniswapV3) amountOut = _swapOnUniswapV3(inToken, amount, args);
        else if (swapType == SwapType.oneInch) amountOut = _swapOn1Inch(inToken, args);
        else if (swapType == SwapType.Wrap) amountOut = wStETH.wrap(amount);
        else amountOut = amount;
    }

    /// @notice Checks whether a the AngleRouter was given approval for a token and if yes approves
    /// this token
    /// @param token Token for which the approval to the `AngleRouter` should be checked
    function _checkAngleRouterAllowance(IERC20 token) internal {
        if (!angleRouterAllowedToken[token]) {
            _changeAllowance(token, address(angleRouter), type(uint256).max);
            angleRouterAllowedToken[token] = true;
        }
    }

    /// @notice Performs a UniswapV3 swap
    /// @param inToken Token to swap
    /// @param amount Amount of tokens to swap
    /// @param path Path for the UniswapV3 swap: this encodes the out token that is going to be obtained
    /// @dev We don't specify a slippage here as in the `swap` function a final slippage check
    /// is performed at the end
    /// @dev This function does not check the out token obtained here: if it is wrongly specified, either
    /// the `swap` function could fail or these tokens could stay on the contract
    function _swapOnUniswapV3(
        IERC20 inToken,
        uint256 amount,
        bytes memory path
    ) internal returns (uint256 amountOut) {
        // Approve transfer to the `uniswapV3Router` if it is the first time that the token is used
        if (!uniAllowedToken[inToken]) {
            _changeAllowance(inToken, address(uniV3Router), type(uint256).max);
            uniAllowedToken[inToken] = true;
        }
        amountOut = uniV3Router.exactInput(ExactInputParams(path, address(this), block.timestamp, amount, 0));
    }

    /// @notice Allows to swap any token to an accepted collateral via 1Inch API
    /// @param inToken Token received for the 1Inch swap
    /// @param payload Bytes needed for 1Inch API
    /// @dev Here again, we don't specify a slippage here as in the `swap` function a final slippage check
    /// is performed at the end
    function _swapOn1Inch(IERC20 inToken, bytes memory payload) internal returns (uint256 amountOut) {
        // Approve transfer to the `oneInch` router if it is the first time the token is used
        if (!oneInchAllowedToken[inToken]) {
            _changeAllowance(inToken, oneInch, type(uint256).max);
            oneInchAllowedToken[inToken] = true;
        }

        //solhint-disable-next-line
        (bool success, bytes memory result) = oneInch.call(payload);
        if (!success) _revertBytes(result);

        amountOut = abi.decode(result, (uint256));
    }

    /// @notice Internal function used for error handling
    /// @param errMsg Error message received
    function _revertBytes(bytes memory errMsg) internal pure {
        if (errMsg.length > 0) {
            //solhint-disable-next-line
            assembly {
                revert(add(32, errMsg), mload(errMsg))
            }
        }
        revert EmptyReturnMessage();
    }
}
