pragma solidity ^0.6.6;

import "../interfaces/IWETH.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Callee.sol";
import "../interfaces/IUniswapV2Factory.sol";
import "../libs/UniswapV2Library.sol";
import "../interfaces/IACOToken.sol";

/**
 * @title ACOFlashExercise
 * @dev Contract to exercise ACO tokens using Uniswap Flash Swap.
 */
contract ACOFlashExercise is IUniswapV2Callee {
    
    /**
     * @dev The Uniswap factory address.
     */
    address immutable public uniswapFactory;

    /**
     * @dev The WETH address used on Uniswap.
     */
    address immutable public weth;
    
    /**
     * @dev Selector for ERC20 approve function.
     */
    bytes4 immutable internal _approveSelector;
    
    /**
     * @dev Selector for ERC20 transfer function.
     */
    bytes4 immutable internal _transferSelector;
    
    constructor(address _uniswapFactory, address _weth) public {
        uniswapFactory = _uniswapFactory;
        weth = _weth;
        
        _approveSelector = bytes4(keccak256(bytes("approve(address,uint256)")));
        _transferSelector = bytes4(keccak256(bytes("transfer(address,uint256)")));
    }
    
    /**
     * @dev To accept ether from the WETH.
     */
    receive() external payable {}
    
    /**
     * @dev Function to get the Uniswap pair for an ACO token.
     * @param acoToken Address of the ACO token.
     * @return The Uniswap pair for the ACO token.
     */
    function getUniswapPair(address acoToken) public view returns(address) {
        address underlying = _getUniswapToken(IACOToken(acoToken).underlying());
        address strikeAsset = _getUniswapToken(IACOToken(acoToken).strikeAsset());
        return IUniswapV2Factory(uniswapFactory).getPair(underlying, strikeAsset);
    }
    
    /**
     * @dev Function to get the required amount of collateral to be paid to Uniswap and the expected amount to exercise the ACO token.
     * @param acoToken Address of the ACO token.
     * @param tokenAmount Amount of tokens to be exercised.
     * @return The required amount of collateral to be paid to Uniswap and the expected amount to exercise the ACO token.
     */
    function getExerciseData(address acoToken, uint256 tokenAmount) public view returns(uint256, uint256) {
        if (tokenAmount > 0) {
            address pair = getUniswapPair(acoToken);
            if (pair != address(0)) {
                address token0 = IUniswapV2Pair(pair).token0();
                address token1 = IUniswapV2Pair(pair).token1();
                (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(pair).getReserves();
                
                (address exerciseAddress, uint256 expectedAmount) = IACOToken(acoToken).getExerciseData(tokenAmount);
                exerciseAddress = _getUniswapToken(exerciseAddress);
                
                uint256 reserveIn = 0; 
                uint256 reserveOut = 0;
                if (exerciseAddress == token0 && expectedAmount < reserve0) {
                    reserveIn = reserve1;
                    reserveOut = reserve0;
                } else if (exerciseAddress == token1 && expectedAmount < reserve1) {
                    reserveIn = reserve0;
                    reserveOut = reserve1;
                }
                
                if (reserveIn > 0 && reserveOut > 0) {
                    uint256 amountRequired = UniswapV2Library.getAmountIn(expectedAmount, reserveIn, reserveOut);
                    return (amountRequired, expectedAmount);
                }
            }
        }
        return (0, 0);
    }
    
    /**
     * @dev Function to get the estimated collateral to be received through a flash exercise.
     * @param acoToken Address of the ACO token.
     * @param tokenAmount Amount of tokens to be exercised.
     * @return The estimated collateral to be received through a flash exercise.
     */
    function getEstimatedReturn(address acoToken, uint256 tokenAmount) public view returns(uint256) {
        (uint256 amountRequired,) = getExerciseData(acoToken, tokenAmount);
        if (amountRequired > 0) {
            (uint256 collateralAmount,) = IACOToken(acoToken).getCollateralOnExercise(tokenAmount);
            if (amountRequired < collateralAmount) {
                return collateralAmount - amountRequired;
            }
        }
        return 0;
    }
    
    /**
     * @dev Function to flash exercise ACO tokens.
     * The flash exercise uses the flash swap functionality on Uniswap.
     * No asset is required to exercise the ACO token because the own collateral redeemed is used to fulfill the terms of the contract.
     * The account will receive the remaining difference.
     * @param acoToken Address of the ACO token.
     * @param tokenAmount Amount of tokens to be exercised.
     * @param minimumCollateral The minimum amount of collateral accepted to be received on the flash exercise.
     */
    function flashExercise(address acoToken, uint256 tokenAmount, uint256 minimumCollateral) public {
        _flashExercise(acoToken, tokenAmount, minimumCollateral, new address[](0));
    }
    
    /**
     * @dev Function to flash exercise ACO tokens.
     * The flash exercise uses the flash swap functionality on Uniswap.
     * No asset is required to exercise the ACO token because the own collateral redeemed is used to fulfill the terms of the contract.
     * The account will receive the remaining difference.
     * @param acoToken Address of the ACO token.
     * @param tokenAmount Amount of tokens to be exercised.
     * @param minimumCollateral The minimum amount of collateral accepted to be received on the flash exercise.
     * @param accounts The array of addresses to get the deposited collateral. 
     */
    function flashExerciseAccounts(
        address acoToken, 
        uint256 tokenAmount, 
        uint256 minimumCollateral, 
        address[] memory accounts
    ) public {
        require(accounts.length > 0, "ACOFlashExercise::flashExerciseAccounts: Accounts are required");
        _flashExercise(acoToken, tokenAmount, minimumCollateral, accounts);
    }
    
     /**
     * @dev External function to called by the Uniswap pair on flash swap transaction.
     * @param sender Address of the sender of the Uniswap swap. It must be the ACOFlashExercise contract.
     * @param amount0Out Amount of token0 on Uniswap pair to be received on the flash swap.
     * @param amount1Out Amount of token1 on Uniswap pair to be received on the flash swap.
     * @param data The ABI encoded with ACO token flash exercise data.
     */
    function uniswapV2Call(
        address sender, 
        uint256 amount0Out, 
        uint256 amount1Out, 
        bytes calldata data
    ) external override {
        require(sender == address(this), "ACOFlashExercise::uniswapV2Call: Invalid sender");
        
        uint256 amountRequired;
        {
        address token0 = IUniswapV2Pair(msg.sender).token0();
        address token1 = IUniswapV2Pair(msg.sender).token1();
        require(msg.sender == IUniswapV2Factory(uniswapFactory).getPair(token0, token1), "ACOFlashExercise::uniswapV2Call: Invalid transaction sender"); 
        require(amount0Out == 0 || amount1Out == 0, "ACOFlashExercise::uniswapV2Call: Invalid out amounts"); 
        
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(msg.sender).getReserves();
        uint256 reserveIn = amount0Out == 0 ? reserve0 : reserve1; 
        uint256 reserveOut = amount0Out == 0 ? reserve1 : reserve0; 
        amountRequired = UniswapV2Library.getAmountIn((amount0Out + amount1Out), reserveIn, reserveOut);
        }
        
        address acoToken;
        uint256 tokenAmount; 
        uint256 ethValue = 0;
        uint256 remainingAmount;
        address from;
        address[] memory accounts;
        {
        uint256 minimumCollateral;
        (from, acoToken, tokenAmount, minimumCollateral, accounts) = abi.decode(data, (address, address, uint256, uint256, address[]));
        (address exerciseAddress, uint256 expectedAmount) = IACOToken(acoToken).getExerciseData(tokenAmount);
        
        require(expectedAmount == (amount1Out + amount0Out), "ACOFlashExercise::uniswapV2Call: Invalid expected amount");
        
        (uint256 collateralAmount,) = IACOToken(acoToken).getCollateralOnExercise(tokenAmount);
        require(amountRequired <= collateralAmount, "ACOFlashExercise::uniswapV2Call: Insufficient collateral amount");
        
        remainingAmount = collateralAmount - amountRequired;
        require(remainingAmount >= minimumCollateral, "ACOFlashExercise::uniswapV2Call: Minimum amount not satisfied");
        
        if (_isEther(exerciseAddress)) {
            ethValue = expectedAmount;
            IWETH(weth).withdraw(expectedAmount);
        } else {
            _callApproveERC20(exerciseAddress, acoToken, expectedAmount);
        }
        }
        
        if (accounts.length == 0) {
            IACOToken(acoToken).exerciseFrom{value: ethValue}(from, tokenAmount);
        } else {
            IACOToken(acoToken).exerciseAccountsFrom{value: ethValue}(from, tokenAmount, accounts);
        }
        
        address collateral = IACOToken(acoToken).collateral();
        address uniswapPayment;
        if (_isEther(collateral)) {
            payable(from).transfer(remainingAmount);
            IWETH(weth).deposit{value: amountRequired}();
            uniswapPayment = weth;
        } else {
            _callTransferERC20(collateral, from, remainingAmount); 
            uniswapPayment = collateral;
        }
        
        _callTransferERC20(uniswapPayment, msg.sender, amountRequired); 
    }
    
    /**
     * @dev Internal function to flash exercise ACO tokens.
     * @param acoToken Address of the ACO token.
     * @param tokenAmount Amount of tokens to be exercised.
     * @param minimumCollateral The minimum amount of collateral accepted to be received on the flash exercise.
     * @param accounts The array of addresses to get the deposited collateral. Whether the array is empty the exercise will be executed using the standard method.
     */
    function _flashExercise(
        address acoToken, 
        uint256 tokenAmount, 
        uint256 minimumCollateral, 
        address[] memory accounts
    ) internal {
        address pair = getUniswapPair(acoToken);
        require(pair != address(0), "ACOFlashExercise::_flashExercise: Invalid Uniswap pair");
        
        (address exerciseAddress, uint256 expectedAmount) = IACOToken(acoToken).getExerciseData(tokenAmount);
        
        uint256 amount0Out = 0;
        uint256 amount1Out = 0;
        if (_getUniswapToken(exerciseAddress) == IUniswapV2Pair(pair).token0()) {
            amount0Out = expectedAmount;
        } else {
            amount1Out = expectedAmount;  
        }
        
        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), abi.encode(msg.sender, acoToken, tokenAmount, minimumCollateral, accounts));
    }
    
    /**
     * @dev Internal function to get Uniswap token address.
     * The Ethereum address on ACO must be swapped to WETH to be used on Uniswap.
     * @param token Address of the token on ACO.
     * @return Uniswap token address.
     */
    function _getUniswapToken(address token) internal view returns(address) {
        if (_isEther(token)) {
            return weth;
        } else {
            return token;
        }
    }
    
    /**
     * @dev Internal function to get if the token is for Ethereum (0x0).
     * @param token Address to be checked.
     * @return Whether the address is for Ethereum.
     */ 
    function _isEther(address token) internal pure returns(bool) {
        return token == address(0);
    }
    
    /**
     * @dev Internal function to approve ERC20 tokens.
     * @param token Address of the token.
     * @param spender Authorized address.
     * @param amount Amount to transfer.
     */
    function _callApproveERC20(address token, address spender, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(_approveSelector, spender, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "ACOTokenExercise::_callApproveERC20");
    }
    
    /**
     * @dev Internal function to transfer ERC20 tokens.
     * @param token Address of the token.
     * @param recipient Address of the transfer destination.
     * @param amount Amount to transfer.
     */
    function _callTransferERC20(address token, address recipient, uint256 amount) internal {
        (bool success, bytes memory returndata) = token.call(abi.encodeWithSelector(_transferSelector, recipient, amount));
        require(success && (returndata.length == 0 || abi.decode(returndata, (bool))), "ACOTokenExercise::_callTransferERC20");
    }
}
