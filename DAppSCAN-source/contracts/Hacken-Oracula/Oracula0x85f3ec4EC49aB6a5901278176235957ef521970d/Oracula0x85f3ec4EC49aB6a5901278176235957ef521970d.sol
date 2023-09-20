// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;



abstract contract Context {

    function _msgSender() internal view virtual returns (address) {

        return msg.sender;

    }



    function _msgData() internal view virtual returns (bytes calldata) {

        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691

        return msg.data;

    }

}



library Address {

    

    function isContract(address account) internal view returns (bool) {

        uint256 size;

        assembly { size := extcodesize(account) }

        return size > 0;

    }



    function sendValue(address payable recipient, uint256 amount) internal {

        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{ value: amount }("");

        require(success, "Address: unable to send value, recipient may have reverted");

    }

    

    function functionCall(address target, bytes memory data) internal returns (bytes memory) {

      return functionCall(target, data, "Address: low-level call failed");

    }

    

    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {

        return functionCallWithValue(target, data, 0, errorMessage);

    }

    

    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {

        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");

    }

    

    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {

        require(address(this).balance >= value, "Address: insufficient balance for call");

        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{ value: value }(data);

        return _verifyCallResult(success, returndata, errorMessage);

    }

    

    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {

        return functionStaticCall(target, data, "Address: low-level static call failed");

    }

    

    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {

        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);

        return _verifyCallResult(success, returndata, errorMessage);

    }





    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {

        return functionDelegateCall(target, data, "Address: low-level delegate call failed");

    }

    

    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {

        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);

        return _verifyCallResult(success, returndata, errorMessage);

    }



    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {

        if (success) {

            return returndata;

        } else {

            if (returndata.length > 0) {

                 assembly {

                    let returndata_size := mload(returndata)

                    revert(add(32, returndata), returndata_size)

                }

            } else {

                revert(errorMessage);

            }

        }

    }

}



abstract contract Ownable is Context {

    address private _owner;



    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    constructor () {

        _owner = msg.sender;

        emit OwnershipTransferred(address(0), _owner);

    }

    

    function owner() public view virtual returns (address) {

        return _owner;

    }

    

    modifier onlyOwner() {

        require(owner() == _msgSender(), "Ownable: caller is not the owner");

        _;

    }

    

// SWC-100-Function Default Visibility: L206 - L212
    function renounceOwnership() public virtual onlyOwner {

        emit OwnershipTransferred(_owner, address(0));

        _owner = address(0);

    }





// SWC-100-Function Default Visibility: L219 - L227
    function transferOwnership(address newOwner) public virtual onlyOwner {

        require(newOwner != address(0), "Ownable: new owner is the zero address");

        emit OwnershipTransferred(_owner, newOwner);

        _owner = newOwner;

    }

}



interface IBEP20 {

    /**

     * @dev Returns the amount of tokens in existence.

     */

    function totalSupply() external view returns (uint256);



    /**

     * @dev Returns the token decimals.

     */

    function decimals() external view returns (uint8);



    /**

     * @dev Returns the token symbol.

     */

    function symbol() external view returns (string memory);



    /**

     * @dev Returns the token name.

     */

    function name() external view returns (string memory);



    /**

     * @dev Returns the bep token owner.

     */

    function getOwner() external view returns (address);



    /**

     * @dev Returns the amount of tokens owned by `account`.

     */

    function balanceOf(address account) external view returns (uint256);



    /**

     * @dev Moves `amount` tokens from the caller's account to `recipient`.

     *

     * Returns a boolean value indicating whether the operation succeeded.

     *

     * Emits a {Transfer} event.

     */

    function transfer(address recipient, uint256 amount) external returns (bool);



    /**

     * @dev Returns the remaining number of tokens that `spender` will be

     * allowed to spend on behalf of `owner` through {transferFrom}. This is

     * zero by default.

     *

     * This value changes when {approve} or {transferFrom} are called.

     */

    function allowance(address _owner, address spender) external view returns (uint256);



    /**

     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.

     *

     * Returns a boolean value indicating whether the operation succeeded.

     *

     * IMPORTANT: Beware that changing an allowance with this method brings the risk

     * that someone may use both the old and the new allowance by unfortunate

     * transaction ordering. One possible solution to mitigate this race

     * condition is to first reduce the spender's allowance to 0 and set the

     * desired value afterwards:

     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729

     *

     * Emits an {Approval} event.

     */

    function approve(address spender, uint256 amount) external returns (bool);



    /**

     * @dev Moves `amount` tokens from `sender` to `recipient` using the

     * allowance mechanism. `amount` is then deducted from the caller's

     * allowance.

     *

     * Returns a boolean value indicating whether the operation succeeded.

     *

     * Emits a {Transfer} event.

     */

    function transferFrom(

        address sender,

        address recipient,

        uint256 amount

    ) external returns (bool);



    /**

     * @dev Emitted when `value` tokens are moved from one account (`from`) to

     * another (`to`).

     *

     * Note that `value` may be zero.

     */

    event Transfer(address indexed from, address indexed to, uint256 value);



    /**

     * @dev Emitted when the allowance of a `spender` for an `owner` is set by

     * a call to {approve}. `value` is the new allowance.

     */

    event Approval(address indexed owner, address indexed spender, uint256 value);

}



interface IPancakeFactory {

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);



    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);



    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function allPairs(uint) external view returns (address pair);

    function allPairsLength() external view returns (uint);



    function createPair(address tokenA, address tokenB) external returns (address pair);



    function setFeeTo(address) external;

    function setFeeToSetter(address) external;

}



interface IPancakePair {

    event Approval(address indexed owner, address indexed spender, uint value);

    event Transfer(address indexed from, address indexed to, uint value);



    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function allowance(address owner, address spender) external view returns (uint);



    function approve(address spender, uint value) external returns (bool);

    function transfer(address to, uint value) external returns (bool);

    function transferFrom(address from, address to, uint value) external returns (bool);



    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint);



    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;



    event Mint(address indexed sender, uint amount0, uint amount1);

    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);

    event Swap(

        address indexed sender,

        uint amount0In,

        uint amount1In,

        uint amount0Out,

        uint amount1Out,

        address indexed to

    );

    event Sync(uint112 reserve0, uint112 reserve1);



    function MINIMUM_LIQUIDITY() external pure returns (uint);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);

    function price0CumulativeLast() external view returns (uint);

    function price1CumulativeLast() external view returns (uint);

    function kLast() external view returns (uint);



    function mint(address to) external returns (uint liquidity);

    function burn(address to) external returns (uint amount0, uint amount1);

    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;

    function skim(address to) external;

    function sync() external;



    function initialize(address, address) external;

}



interface IPancakeRouter01 {

    function factory() external pure returns (address);

    function WETH() external pure returns (address);



    function addLiquidity(

        address tokenA,

        address tokenB,

        uint amountADesired,

        uint amountBDesired,

        uint amountAMin,

        uint amountBMin,

        address to,

        uint deadline

    ) external returns (uint amountA, uint amountB, uint liquidity);

    function addLiquidityETH(

        address token,

        uint amountTokenDesired,

        uint amountTokenMin,

        uint amountETHMin,

        address to,

        uint deadline

    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function removeLiquidity(

        address tokenA,

        address tokenB,

        uint liquidity,

        uint amountAMin,

        uint amountBMin,

        address to,

        uint deadline

    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETH(

        address token,

        uint liquidity,

        uint amountTokenMin,

        uint amountETHMin,

        address to,

        uint deadline

    ) external returns (uint amountToken, uint amountETH);

    function removeLiquidityWithPermit(

        address tokenA,

        address tokenB,

        uint liquidity,

        uint amountAMin,

        uint amountBMin,

        address to,

        uint deadline,

        bool approveMax, uint8 v, bytes32 r, bytes32 s

    ) external returns (uint amountA, uint amountB);

    function removeLiquidityETHWithPermit(

        address token,

        uint liquidity,

        uint amountTokenMin,

        uint amountETHMin,

        address to,

        uint deadline,

        bool approveMax, uint8 v, bytes32 r, bytes32 s

    ) external returns (uint amountToken, uint amountETH);

    function swapExactTokensForTokens(

        uint amountIn,

        uint amountOutMin,

        address[] calldata path,

        address to,

        uint deadline

    ) external returns (uint[] memory amounts);

    function swapTokensForExactTokens(

        uint amountOut,

        uint amountInMax,

        address[] calldata path,

        address to,

        uint deadline

    ) external returns (uint[] memory amounts);

    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)

        external

        payable

        returns (uint[] memory amounts);

    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)

        external

        returns (uint[] memory amounts);

    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)

        external

        returns (uint[] memory amounts);

    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)

        external

        payable

        returns (uint[] memory amounts);



    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);

    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);

    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);

    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);

    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);

}



interface IPancakeRouter02 is IPancakeRouter01 {

    function removeLiquidityETHSupportingFeeOnTransferTokens(

        address token,

        uint liquidity,

        uint amountTokenMin,

        uint amountETHMin,

        address to,

        uint deadline

    ) external returns (uint amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(

        address token,

        uint liquidity,

        uint amountTokenMin,

        uint amountETHMin,

        address to,

        uint deadline,

        bool approveMax, uint8 v, bytes32 r, bytes32 s

    ) external returns (uint amountETH);



    function swapExactTokensForTokensSupportingFeeOnTransferTokens(

        uint amountIn,

        uint amountOutMin,

        address[] calldata path,

        address to,

        uint deadline

    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(

        uint amountOutMin,

        address[] calldata path,

        address to,

        uint deadline

    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(

        uint amountIn,

        uint amountOutMin,

        address[] calldata path,

        address to,

        uint deadline

    ) external;

}



contract Oracula is Context, IBEP20, Ownable {



    uint256 private _totalSupply = 50 * 10 ** (6 + 18);

    string private _name = "Oracula";

    string private _symbol = "ORACULA";

    uint8 private _decimals = 18;



    IPancakeRouter02 public pancakeRouter;

    

    mapping(address => uint256) private _balances;



    mapping(address => mapping(address => uint256)) private _allowances;



    mapping(address => bool) public _isExcludedFromFees;



    mapping(address => bool) public exchangePairs;



// SWC-108-State Variable Default Visibility: L860 - L884
    uint256 burnFee;

    uint256 devFee;

    uint256 rewardFee;

    uint256 immutable maxBurnFee = 20;

    uint256 immutable maxDevFee = 20;

    uint256 immutable maxRewardFee = 20;

    uint256 immutable maximumFee = 60;

    uint256 immutable denominator = 1000;

    address immutable burnAddress = 0x000000000000000000000000000000000000dEaD;

    address devAddress;

    address rewardAddress;



    uint256 public nextBurn;



    constructor(

        address _devAddress, 

        address _rewardAddress, 

        uint256 _burnFee, 

        uint256 _devFee, 

        uint256 _rewardFee

        ){

        _changeFeeAddresses(_devAddress, _rewardAddress);

        _changeAllFees(_burnFee, _devFee, _rewardFee);



        IPancakeRouter02 _pancakeRouter = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);

        address _pancakePair = IPancakeFactory(_pancakeRouter.factory())

        .createPair(address(this), _pancakeRouter.WETH());



        pancakeRouter = _pancakeRouter;



		_setExchangePairs(_pancakePair, true);



        _changeFeeStatus(owner(), true);



        nextBurn = block.timestamp + 30 days;



        _balances[owner()] += _totalSupply;

        emit Transfer(address(0), owner(), _totalSupply);

    }



    /// @return ERC20 Total Supply

    function totalSupply() external override view returns (uint256) {

        return _totalSupply;

    }



    function getOwner() external view override returns (address) {

        return owner();

    }



    /// @return ERC20 decimals

    function decimals() external override view returns (uint8){

        return _decimals;

    }



    /// @return ERC20 symbol

    function symbol() external override view returns (string memory) {

        return _symbol;

    }



    /// @return ERC20 name

    function name() external override view returns (string memory) {

        return _name;

    }



    function getFees() external view returns (uint256 burn, uint256 dev, uint256 reward) {

        return (burnFee, devFee, rewardFee);

    }



    /// @return Sum of Fees

    function getSumOfFees() public view returns (uint256) {

        return burnFee + devFee + rewardFee;

    }



    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {

        _transfer(_msgSender(), recipient, amount);

        return true;

    }



    /// @return ERC20 allowance

    function allowance(address owner, address spender) public view virtual override returns (uint256) {

        return _allowances[owner][spender];

    }



    function approve(address spender, uint256 amount) public virtual override returns (bool) {

        _approve(_msgSender(), spender, amount);

        return true;

    }



    function transferFrom(

        address sender,

        address recipient,

        uint256 amount

    ) public virtual override returns (bool) {

        _transfer(sender, recipient, amount);



        uint256 currentAllowance = _allowances[sender][_msgSender()];

        require(currentAllowance >= amount, "BEP20: transfer amount exceeds allowance");

        unchecked {

            _approve(sender, _msgSender(), currentAllowance - amount);

        }



        return true;

    }



    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {

        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);

        return true;

    }



    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {

        uint256 currentAllowance = _allowances[_msgSender()][spender];

        require(currentAllowance >= subtractedValue, "BEP20: decreased allowance below zero");

        unchecked {

            _approve(_msgSender(), spender, currentAllowance - subtractedValue);

        }



        return true;

    }



    /// @dev main transfer function

    function _transfer(address _from, address _to, uint256 _amount) internal {

        require(_from != address(0), "BEP20: transfer from the zero address");

        require(_to != address(0), "BEP20: transfer to the zero address");



        uint256 senderBalance = _balances[_from];

        require(senderBalance >= _amount, "BEP20: transfer amount exceeds balance");



        /// @dev if to/from market pair -> take fee

        bool takeFee = exchangePairs[_to] || exchangePairs[_from];

        if (_isExcludedFromFees[_from] || _isExcludedFromFees[_to]) {

            takeFee = false;

        }



        if (takeFee) {

            /// @dev Burn tokens once a month if balance of token contract > 0

            if (block.timestamp >= nextBurn && _balances[address(this)] > 0) {

                uint256 burnAmount = _balances[address(this)];

                _balances[address(this)] = 0;

                _balances[burnAddress] += burnAmount;

                emit Transfer(address(this), burnAddress, burnAmount);

                nextBurn = block.timestamp + 30 days;

            }



            uint256 fees = _amount * (burnFee + devFee + rewardFee) / denominator;

            _balances[_from] = senderBalance - _amount;

            _amount -= fees;

            distributeFees(_from, fees);

            _balances[_to] += _amount;

        } else {

            _balances[_from] = senderBalance - _amount;

            _balances[_to] += _amount;

        }

        emit Transfer(_from, _to, _amount);

    }



    function _approve(

        address owner,

        address spender,

        uint256 amount

    ) internal virtual {

        require(owner != address(0), "BEP20: approve from the zero address");

        require(spender != address(0), "BEP20: approve to the zero address");



        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);

    }



    function balanceOf(address account) external view override returns (uint256) {

        return _balances[account];

    }



    function distributeFees(address _from, uint256 _amount) internal {

        if (burnFee != 0) {

            uint256 burn = _amount * burnFee / getSumOfFees();

            _balances[address(this)] += burn;

            emit Transfer(_from, address(this), burn);

        }

        if (devFee != 0) {

            uint256 dev = _amount * devFee / getSumOfFees();

            _balances[devAddress] += dev;

            emit Transfer(_from, devAddress, dev);

        }

        if (rewardFee != 0) {

            uint256 reward = _amount * rewardFee / getSumOfFees();

            _balances[rewardAddress] += reward;

            emit Transfer(_from, rewardAddress, reward);

        }

    }



    /// @dev Update Uniswap Router

    function updateUniswapV2Router(address newAddress) external onlyOwner {

		require(newAddress != address(pancakeRouter), "MemeKing: The router already has that address");

		pancakeRouter = IPancakeRouter02(newAddress);

		address _pancakePair = IPancakeFactory(pancakeRouter.factory())

		.createPair(address(this), pancakeRouter.WETH());

        _setExchangePairs(_pancakePair, true);

	}



    function changeAllFees(uint256 _burnFee, uint256 _devFee, uint256 _rewardFee) external onlyOwner {

        _changeAllFees(_burnFee, _devFee, _rewardFee);

    }



    /// @dev changes fees, checks that each is not bigger than 2%

    function _changeAllFees(uint256 _burnFee, uint256 _devFee, uint256 _rewardFee) internal {

        require(_burnFee + _devFee + _rewardFee <= maximumFee, "Maximum fee would be exceeded");

        require(_burnFee <= maxBurnFee, "Burn fee exceeds 2%");

        require(_devFee <= maxDevFee, "Dev fee exceeds 2%");

        require(_rewardFee <= maxRewardFee, "Reward fee exceeds 2%");

        burnFee = _burnFee;

        devFee = _devFee;

        rewardFee = _rewardFee;

    }



    function changeFeeAddresses(address _devAddress, address _rewardAddress) external onlyOwner {

        _changeFeeAddresses(_devAddress, _rewardAddress);

    }



    function _changeFeeAddresses(address _devAddress, address _rewardAddress) internal {

        devAddress = _devAddress;

        rewardAddress = _rewardAddress;

    }



    function changeFeeStatus(address account, bool excluded) external onlyOwner {

        _changeFeeStatus(account, excluded);

    }



    function _changeFeeStatus(address account, bool excluded) internal {

        _isExcludedFromFees[account] = excluded;

    }



    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {

		_setExchangePairs(pair, value);

	}



    function _setExchangePairs(address pair, bool value) internal {

		require(exchangePairs[pair] != value, "MemeKing: Automated market maker pair is already set to that value");

		exchangePairs[pair] = value;

	}



    function isExcludedFromFees(address account) external view returns(bool){

        return _isExcludedFromFees[account];

    }



    receive() external payable {

        revert("Sending BNB to the contract is not smart");

    }



}