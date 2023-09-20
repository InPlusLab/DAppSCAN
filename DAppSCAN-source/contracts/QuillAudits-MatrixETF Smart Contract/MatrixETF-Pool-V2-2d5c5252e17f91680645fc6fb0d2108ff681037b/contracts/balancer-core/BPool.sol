// SPDX-License-Identifier: GPL-3.0
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.6.12;

import "./BToken.sol";
import "./BMath.sol";
import "../interfaces/IPoolRestrictions.sol";
import "../interfaces/BPoolInterface.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

contract BPool is BToken, BMath, BPoolInterface {
    using SafeERC20 for IERC20;

    struct Record {
        bool bound;   // is token bound to pool
        uint index;   // private
        uint denorm;  // denormalized weight
        uint balance;
    }

  /* ==========  EVENTS  ========== */

    /** @dev Emitted when tokens are swapped. */
    event LOG_SWAP(
        address indexed caller,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256         tokenAmountIn,
        uint256         tokenAmountOut
    );

    /** @dev Emitted when underlying tokens are deposited for pool tokens. */
    event LOG_JOIN(
        address indexed caller,
        address indexed tokenIn,
        uint256         tokenAmountIn
    );

    /** @dev Emitted when pool tokens are burned for underlying. */
    event LOG_EXIT(
        address indexed caller,
        address indexed tokenOut,
        uint256         tokenAmountOut
    );

    /** @dev Emitted on calling any method with `_logs_` modifier. */
    event LOG_CALL(
        bytes4  indexed sig,
        address indexed caller,
        bytes           data
    ) anonymous;

    /** @dev Emitted on calling external voting contract. */
    event LOG_CALL_VOTING(
        address indexed voting,
        bool    indexed success,
        bytes4  indexed inputSig,
        bytes           inputData,
        bytes           outputData
    );

    /** @dev Emitted on taking community fee. */
    event LOG_COMMUNITY_FEE(
        address indexed caller,
        address indexed receiver,
        address indexed token,
        uint256         tokenAmount
    );

  /* ==========  Modifiers  ========== */

    modifier _logs_() {
        emit LOG_CALL(msg.sig, msg.sender, msg.data);
        _;
    }

    modifier _lock_() {
        _preventReentrancy();
        _mutex = true;
        _;
        _mutex = false;
    }

    modifier _viewlock_() {
        _preventReentrancy();
        _;
    }

  /* ==========  Storage  ========== */

    bool private _mutex;

    // CONTROLLER contract. Able to modify swap fee, swap community fee,
    // community entree fee, community exit fee,
    // change token weights, bind, unbind and rebind tokens,
    // set wrapper contract, enable wrapper mode, change CONTROLLER.
    address internal _controller;

    // True if PUBLIC can call SWAP & JOIN functions
    bool private _swapsDisabled;

    // Address of contract which wraps pool operations:
    // join, exit and swaps.
    address private _wrapper;
    // Restriction to execute pool operations only from wrapper contract.
    // True if only wrapper can execute pool operations.
    bool private _wrapperMode;

    // Contract for getting restrictions:
    // Max total supply and voting calls.
    IPoolRestrictions private _restrictions;

    // `setSwapFee` require CONTROLLER
    uint private _swapFee;
    // `_communitySwapFee`, `_communityJoinFee`, `_communityExitFee`
    // defines the commissions sent to `_communityFeeReceiver`
    uint private _communitySwapFee;
    uint private _communityJoinFee;
    uint private _communityExitFee;
    // Community commission contract. Collects
    // `_communitySwapFee`, `_communityJoinFee`, `_communityExitFee`
    // for voting in underlying protocols, receiving rewards.
    address private _communityFeeReceiver;
    // `finalize` require CONTROLLER
    // `finalize` sets `PUBLIC can SWAP`, `PUBLIC can JOIN`
    bool private _finalized;

    // Array of underlying pool tokens.
    address[] internal _tokens;
    // Pool's underlying tokens Internal records.
    mapping(address => Record) internal _records;
    // Total pool's denormalized weight.
    uint internal _totalWeight;

    // Last block when account address made a swap.
    mapping(address => uint256) internal _lastSwapBlock;

    constructor(string memory name, string memory symbol) public {
        _name = name;
        _symbol = symbol;
        _controller = msg.sender;
        _swapFee = MIN_FEE;
        _communitySwapFee = 0;
        _communityJoinFee = 0;
        _communityExitFee = 0;
        _swapsDisabled = false;
        _finalized = false;
    }

  /* ==========  Token Queries  ========== */

    /**
     * @notice Check if a token is bound to the pool.
     * @param t Token contracts address.
     * @return TRUE if the token is bounded, FALSE - if not.
     */
    function isBound(address t)
        external view override
        returns (bool)
    {
        return _records[t].bound;
    }

    /**
     * @notice Get the number of tokens bound to the pool.
     * @return bound tokens number.
     */
    function getNumTokens()
        external view
        returns (uint)
    {
        return _tokens.length;
    }

    /**
      * @notice Get all bound tokens.
      * @return tokens - bound token address array.
     */
    function getCurrentTokens()
        external view override
        _viewlock_
        returns (address[] memory tokens)
    {
        return _tokens;
    }

    /**
      * @notice Get all bound tokens with a finalization check.
      * @return tokens - bound token address array.
     */
    function getFinalTokens()
        external view override
        _viewlock_
        returns (address[] memory tokens)
    {
        _requireContractIsFinalized();
        return _tokens;
    }

    /**
      * @notice Returns the denormalized weight of a bound token.
      * @param token Token contract address.
      * @return Bound token denormalized weight.
     */
    function getDenormalizedWeight(address token)
        external view override
        _viewlock_
        returns (uint)
    {

        _requireTokenIsBound(token);
        return _getDenormWeight(token);
    }

    /**
     * @notice Get the total denormalized weight of the pool.
     * @return Total denormalized weight of all bound tokens.
     */
    function getTotalDenormalizedWeight()
        external view override
        _viewlock_
        returns (uint)
    {
        return _getTotalWeight();
    }

    /**
     * @notice Returns the normalized weight of a bound token.
     * @param token Token contract address.
     * @return Bound token normalized weight.
     */
    function getNormalizedWeight(address token)
        external view
        _viewlock_
        returns (uint)
    {

        _requireTokenIsBound(token);
        return bdiv(_getDenormWeight(token), _getTotalWeight());
    }

    /**
     * @notice Returns the stored balance of a bound token.
     * @param token Token contract address.
     * @return Bound token balance
     */
    function getBalance(address token)
        external view override
        _viewlock_
        returns (uint)
    {

        _requireTokenIsBound(token);
        return _records[token].balance;
    }

  /* ==========  Config Queries  ========== */

    /**
     * @notice Check if tokens swap and joining the pool allowed.
     * @return TRUE if allowed, FALSE if not.
     */
    function isSwapsDisabled()
        external view override
        returns (bool)
    {
        return _swapsDisabled;
    }

    /**
     * @notice Check if pool is finalized.
     * @return TRUE if finalized, FALSE if not.
     */
    function isFinalized()
        external view override
        returns (bool)
    {
        return _finalized;
    }

    /**
     * @notice Returns the swap fee rate.
     * @return pool's swap fee rate.
     */
    function getSwapFee()
        external view override
        _viewlock_
        returns (uint)
    {
        return _swapFee;
    }

    /**
     * @notice Returns the community fee rate and community fee receiver.
     * @return communitySwapFee - community swap fee rate.
     * @return communityJoinFee - community join fee rate.
     * @return communityExitFee - community exit fee rate.
     * @return communityFeeReceiver - community fee receiver address.
     */
    function getCommunityFee()
        external view override
        _viewlock_
        returns (uint communitySwapFee, uint communityJoinFee, uint communityExitFee, address communityFeeReceiver)
    {
        return (_communitySwapFee, _communityJoinFee, _communityExitFee, _communityFeeReceiver);
    }

    /**
     * @notice Returns the controller address.
     * @return controller contract address.
     */
    function getController()
        external view
        _viewlock_
        returns (address)
    {
        return _controller;
    }

    /**
     * @notice Returns the wrapper address.
     * @return pool wrapper contract address.
     */
    function getWrapper()
        external view
        _viewlock_
        returns (address)
    {
        return _wrapper;
    }

    /**
     * @notice Check if wrapper mode is enabled.
     * @return TRUE if wrapper mode enabled, FALSE if not.
     */
    function getWrapperMode()
        external view
        _viewlock_
        returns (bool)
    {
        return _wrapperMode;
    }

    /**
     * @notice Returns the restrictions contract address.
     * @return pool restrictions contract address.
     */
    function getRestrictions()
        external view override
        _viewlock_
        returns (address)
    {
        return address(_restrictions);
    }

  /* ==========  Configuration Actions  ========== */

    /**
     * @notice Set the swap fee.
     * @dev Swap fee must be between 0.0001% and 10%.
     * @param swapFee swap fee left in the pool.
     */
    function setSwapFee(uint swapFee)
        external override
        _logs_
        _lock_
    {
        _onlyController();
        _requireFeeInBounds(swapFee);
        _swapFee = swapFee;
    }

    /**
     * @notice Set the community fee and community fee receiver.
     * @dev Community fee must be between 0.0001% and 10%.
     * @param communitySwapFee Fee for Community treasury from each swap
     * @param communityJoinFee Fee for Community treasury from each join.
     * @param communityExitFee Fee for Community treasury from each exit.
     * @param communityFeeReceiver Community treasury contract address.
     */
    function setCommunityFeeAndReceiver(
        uint communitySwapFee,
        uint communityJoinFee,
        uint communityExitFee,
        address communityFeeReceiver
    )
        external override
        _logs_
        _lock_
    {
        _onlyController();
        _requireFeeInBounds(communitySwapFee);
        _requireFeeInBounds(communityJoinFee);
        _requireFeeInBounds(communityExitFee);
        _communitySwapFee = communitySwapFee;
        _communityJoinFee = communityJoinFee;
        _communityExitFee = communityExitFee;
        _communityFeeReceiver = communityFeeReceiver;
    }

    /**
     * @notice Set the restrictions contract address.
     * @param restrictions Pool's restrictions contract.
     */
    function setRestrictions(IPoolRestrictions restrictions)
        external
        _logs_
        _lock_
    {
        _onlyController();
        _restrictions = restrictions;
    }

    /**
     * @notice Set the controller address.
     * @param manager New controller contract address.
     */
    function setController(address manager)
        external override
        _logs_
        _lock_
    {
        _onlyController();
        _controller = manager;
    }

    /**
     * @notice Enable or disable swaps.
     * @param disabled_ boolean variable, TRUE if disable, FALSE if not.
     */
    function setSwapsDisabled(bool disabled_)
        external override
        _logs_
        _lock_
    {
        _onlyController();
        _swapsDisabled = disabled_;
    }

    /**
     * @notice Set the wrapper contract address and mode.
     * @param wrapper Wrapper contract address.
     * @param wrapperMode TRUE if enabled, FALSE if disabled.
     */
    function setWrapper(address wrapper, bool wrapperMode)
        external
        _logs_
        _lock_
    {
        _onlyController();
        _wrapper = wrapper;
        _wrapperMode = wrapperMode;
    }

    /**
     * @notice Finalize the pool, enable swaps, mint pool share token.
     */
    function finalize()
        external override
        _logs_
        _lock_
    {
        _onlyController();
        _requireContractIsNotFinalized();
        require(_tokens.length >= MIN_BOUND_TOKENS, "MIN_TOKENS");

        _finalized = true;

        _mintPoolShare(INIT_POOL_SUPPLY);
        _pushPoolShare(msg.sender, INIT_POOL_SUPPLY);
    }

    /* ==========  Voting Management Actions  ========== */

        /**
       * @notice Call target external contract with provided signature and data.
       * @param voting Destination contract address.
       * @param signature Destination contract method signature.
       * @param args Arguments of the called method.
       * @param value Transaction value.
       * @dev Can call only controller contract. Checks if destination address and signature allowed.
       */


    function callVoting(address voting, bytes4 signature, bytes calldata args, uint256 value)
        external override
        _logs_
        _lock_
    {
        require(_restrictions.isVotingSignatureAllowed(voting, signature), "NOT_ALLOWED_SIG");
        _onlyController();

        (bool success, bytes memory data) = voting.call{ value: value }(abi.encodePacked(signature, args));
        require(success, "NOT_SUCCESS");
        emit LOG_CALL_VOTING(voting, success, signature, args, data);
    }

    /* ==========  Token Management Actions  ========== */

    /**
     * @notice Bind a token with depositing initial balance.
     * @param token Address of the token to bind.
     * @param balance Initial token balance.
     * @param denorm Token denormalized weight.
     */
    function bind(address token, uint balance, uint denorm)
        public override
        virtual
        _logs_
        // _lock_  Bind does not lock because it jumps to `rebind`, which does
    {
        _onlyController();
        require(!_records[token].bound, "IS_BOUND");

        require(_tokens.length < MAX_BOUND_TOKENS, "MAX_TOKENS");

        _records[token] = Record({
            bound: true,
            index: _tokens.length,
            denorm: 0,    // balance and denorm will be validated
            balance: 0   // and set by `rebind`
        });
        _tokens.push(token);
        rebind(token, balance, denorm);
    }

    /**
     * @notice Rebind token with changing balance and denormalized weight.
     * @param token Address of the token to rebind.
     * @param balance New token balance.
     * @param denorm Desired weight for the token.
     */
    function rebind(address token, uint balance, uint denorm)
        public override
        virtual
        _logs_
        _lock_
    {
        _onlyController();
        _requireTokenIsBound(token);

        require(denorm >= MIN_WEIGHT && denorm <= MAX_WEIGHT, "WEIGHT_BOUNDS");
        require(balance >= MIN_BALANCE, "MIN_BALANCE");

        // Adjust the denorm and totalWeight
        // SWC-135-Code With No Effects: L559 - L565
        uint oldWeight = _records[token].denorm;
        if (denorm > oldWeight) {
            _addTotalWeight(bsub(denorm, oldWeight));
        } else if (denorm < oldWeight) {
            _subTotalWeight(bsub(oldWeight, denorm));
        }
        _records[token].denorm = denorm;

        // Adjust the balance record and actual token balance
        uint oldBalance = _records[token].balance;
        _records[token].balance = balance;
        if (balance > oldBalance) {
            _pullUnderlying(token, msg.sender, bsub(balance, oldBalance));
        } else if (balance < oldBalance) {
            uint tokenBalanceWithdrawn = bsub(oldBalance, balance);
            _pushUnderlying(token, msg.sender, tokenBalanceWithdrawn);
        }
    }

    /**
     * @notice Remove a token from the pool.
     * @dev Replaces the address in the tokens array with the last address, then removes it from the array.
     * @param token Bound token address.
     */
    function unbind(address token)
        public override
        virtual
        _logs_
        _lock_
    {
        _onlyController();
        _requireTokenIsBound(token);

        uint tokenBalance = _records[token].balance;

        _subTotalWeight(_records[token].denorm);

        // Swap the token-to-unbind with the last token,
        // then delete the last token
        uint index = _records[token].index;
        uint last = _tokens.length - 1;
        _tokens[index] = _tokens[last];
        _records[_tokens[index]].index = index;
        _tokens.pop();
        _records[token] = Record({
            bound: false,
            index: 0,
            denorm: 0,
            balance: 0
        });

        _pushUnderlying(token, msg.sender, tokenBalance);
    }

    /**
     * @notice Absorb any tokens that have been sent to this contract into the pool.
     * @param token Bound token address.
     */
    function gulp(address token)
        external override
    {
    }

    /* ==========  Price Queries  ========== */

    /**
     * @notice Returns the spot price for `tokenOut` in terms of `tokenIn`.
     * @param tokenIn Bound tokenIn address.
     * @param tokenOut Bound tokenOut address.
     * @return spotPrice - amount of tokenIn in wei for 1 ether of tokenOut.
     */

    function getSpotPrice(address tokenIn, address tokenOut)
        external view
        _viewlock_
        returns (uint spotPrice)
    {
        require(_records[tokenIn].bound && _records[tokenOut].bound, "NOT_BOUND");
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return calcSpotPrice(inRecord.balance, _getDenormWeight(tokenIn), outRecord.balance, _getDenormWeight(tokenOut), _swapFee);
    }

    /**
     * @notice Returns the spot price for `tokenOut` in terms of `tokenIn` without swapFee.
     * @param tokenIn Bound tokenIn address.
     * @param tokenOut Bound tokenOut address.
     * @return spotPrice - amount of tokenIn in wei for 1 ether of tokenOut.
     */
    function getSpotPriceSansFee(address tokenIn, address tokenOut)
        external view
        _viewlock_
        returns (uint spotPrice)
    {
        _requireTokenIsBound(tokenIn);
        _requireTokenIsBound(tokenOut);
        Record storage inRecord = _records[tokenIn];
        Record storage outRecord = _records[tokenOut];
        return calcSpotPrice(inRecord.balance, _getDenormWeight(tokenIn), outRecord.balance, _getDenormWeight(tokenOut), 0);
    }

  function calcTokensForAmount(uint256 _amount) external view returns (address[] memory tokens, uint256[] memory amounts)
  {
    tokens = _tokens;
    amounts = new uint256[](tokens.length);
    uint poolTotal = totalSupply();
    uint256 ratio = bdiv(_amount, poolTotal);

    for (uint256 i = 0; i < tokens.length; i++) {
      address t = tokens[i];
      uint256 bal = _records[t].balance;
      uint256 amount = bmul(ratio, bal);
      amounts[i] = amount;
    }
  }

    /* ==========  Liquidity Provider Actions and Token Swaps  ========== */

    /**
     * @notice Mint new pool tokens by providing the proportional amount of each
     * underlying token's balance relative to the proportion of pool tokens minted.
     * @param poolAmountOut Amount of pool tokens to mint
     * @param maxAmountsIn Maximum amount of each token to pay in the same order as the pool's _tokens list.
     */
    function joinPool(uint poolAmountOut, uint[] calldata maxAmountsIn)
        external override
        _logs_
        _lock_
    {
        _preventSameTxOrigin();
        _onlyWrapperOrNotWrapperMode();
        _requireContractIsFinalized();

        uint poolTotal = totalSupply();
        uint ratio = bdiv(poolAmountOut, poolTotal);
        _requireMathApprox(ratio);

        for (uint i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint bal = _records[t].balance;
            uint tokenAmountIn = bmul(ratio, bal);
            _requireMathApprox(tokenAmountIn);
            require(tokenAmountIn < maxAmountsIn[i], "LIMIT_IN");
            _records[t].balance = badd(_records[t].balance, tokenAmountIn);
            emit LOG_JOIN(msg.sender, t, tokenAmountIn);
            _pullUnderlying(t, msg.sender, tokenAmountIn);
        }

//        (uint poolAmountOutAfterFee, uint poolAmountOutFee) = calcAmountWithCommunityFee(
//            poolAmountOut,
//            _communityJoinFee,
//            msg.sender
//        );

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
//        _pushPoolShare(_communityFeeReceiver, poolAmountOutFee);
//        emit LOG_COMMUNITY_FEE(msg.sender, _communityFeeReceiver, address(this), poolAmountOutFee);
    }

    /**
     * @notice Burns `poolAmountIn` pool tokens in exchange for the amounts of each
     * underlying token's balance proportional to the ratio of tokens burned to
     * total pool supply. The amount of each token transferred to the caller must
     * be greater than or equal to the associated minimum output amount from the
     * `minAmountsOut` array.
     *
     * @param poolAmountIn Exact amount of pool tokens to burn
     * @param minAmountsOut Minimum amount of each token to receive, in the same
     * order as the pool's _tokens list.
     */
    function exitPool(uint poolAmountIn, uint[] calldata minAmountsOut)
        external override
        _logs_
        _lock_
    {
        _preventSameTxOrigin();
        _onlyWrapperOrNotWrapperMode();
        _requireContractIsFinalized();

        (uint poolAmountInAfterFee, uint poolAmountInFee) = calcAmountWithCommunityFee(
            poolAmountIn,
            _communityExitFee,
            msg.sender
        );

        uint poolTotal = totalSupply();
        uint ratio = bdiv(poolAmountInAfterFee, poolTotal);
        _requireMathApprox(ratio);

        _pullPoolShare(msg.sender, poolAmountIn);
        _pushPoolShare(_communityFeeReceiver, poolAmountInFee);
        _burnPoolShare(poolAmountInAfterFee);

        for (uint i = 0; i < _tokens.length; i++) {
            address t = _tokens[i];
            uint bal = _records[t].balance;
            uint tokenAmountOut = bmul(ratio, bal);
            _requireMathApprox(tokenAmountOut);
            require(tokenAmountOut > minAmountsOut[i], "LIMIT_OUT");
            _records[t].balance = bsub(_records[t].balance, tokenAmountOut);
            emit LOG_EXIT(msg.sender, t, tokenAmountOut);
            _pushUnderlying(t, msg.sender, tokenAmountOut);
        }

        emit LOG_COMMUNITY_FEE(msg.sender, _communityFeeReceiver, address(this), poolAmountInFee);
    }

    /**
    * @notice Execute a token swap with a specified amount of input
    * tokens and a minimum amount of output tokens.
    * @dev Will revert if `tokenOut` is uninitialized.
    * @param tokenIn Token to swap in.
    * @param tokenAmountIn Exact amount of `tokenIn` to swap in.
    * @param tokenOut Token to swap out.
    * @param minAmountOut Minimum amount of `tokenOut` to receive.
    * @param maxPrice Maximum ratio of input to output tokens.
    * @return tokenAmountOut
    * @return spotPriceAfter
    */
    function swapExactAmountIn(
        address tokenIn,
        uint tokenAmountIn,
        address tokenOut,
        uint minAmountOut,
        uint maxPrice
    )
        external override
        _logs_
        _lock_
        returns (uint tokenAmountOut, uint spotPriceAfter)
    {
        _checkSwapsDisabled();
        _preventSameTxOrigin();
        _onlyWrapperOrNotWrapperMode();
        _requireTokenIsBound(tokenIn);
        _requireTokenIsBound(tokenOut);

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        uint spotPriceBefore = calcSpotPrice(
                                    inRecord.balance,
                                    _getDenormWeight(tokenIn),
                                    outRecord.balance,
                                    _getDenormWeight(tokenOut),
                                    _swapFee
                                );
        require(spotPriceBefore <= maxPrice, "LIMIT_PRICE");

        (uint tokenAmountInAfterFee, uint tokenAmountInFee) = calcAmountWithCommunityFee(
                                                                tokenAmountIn,
                                                                _communitySwapFee,
                                                                msg.sender
                                                            );

        require(tokenAmountInAfterFee <= bmul(inRecord.balance, MAX_IN_RATIO), "MAX_IN_RATIO");

        tokenAmountOut = calcOutGivenIn(
                            inRecord.balance,
                            _getDenormWeight(tokenIn),
                            outRecord.balance,
                            _getDenormWeight(tokenOut),
                            tokenAmountInAfterFee,
                            _swapFee
                        );
        require(tokenAmountOut >= minAmountOut, "LIMIT_OUT");

        inRecord.balance = badd(inRecord.balance, tokenAmountInAfterFee);
        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
                                inRecord.balance,
                                _getDenormWeight(tokenIn),
                                outRecord.balance,
                                _getDenormWeight(tokenOut),
                                _swapFee
                            );
        require(
            spotPriceAfter >= spotPriceBefore &&
            spotPriceBefore <= bdiv(tokenAmountInAfterFee, tokenAmountOut),
            "MATH_APPROX"
        );
        require(spotPriceAfter <= maxPrice, "LIMIT_PRICE");

        emit LOG_SWAP(msg.sender, tokenIn, tokenOut, tokenAmountInAfterFee, tokenAmountOut);

        _pullCommunityFeeUnderlying(tokenIn, msg.sender, tokenAmountInFee);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountInAfterFee);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOut);

        emit LOG_COMMUNITY_FEE(msg.sender, _communityFeeReceiver, tokenIn, tokenAmountInFee);

        return (tokenAmountOut, spotPriceAfter);
    }
    /**
    * @dev Trades at most `maxAmountIn` of `tokenIn` for exactly `tokenAmountOut`
    * of `tokenOut`.
    *
    * Returns the actual input amount and the new spot price after the swap,
    * which can not exceed `maxPrice`.
    *
    * @param tokenIn Token to swap in
    * @param maxAmountIn Maximum amount of `tokenIn` to pay
    * @param tokenOut Token to swap out
    * @param tokenAmountOut Exact amount of `tokenOut` to receive
    * @param maxPrice Maximum ratio of input to output tokens
    * @return tokenAmountIn
    * @return spotPriceAfter
    */
    function swapExactAmountOut(
        address tokenIn,
        uint maxAmountIn,
        address tokenOut,
        uint tokenAmountOut,
        uint maxPrice
    )
        external override
        _logs_
        _lock_
        returns (uint tokenAmountIn, uint spotPriceAfter)
    {
        _checkSwapsDisabled();
        _preventSameTxOrigin();
        _onlyWrapperOrNotWrapperMode();
        _requireTokenIsBound(tokenIn);
        _requireTokenIsBound(tokenOut);

        Record storage inRecord = _records[address(tokenIn)];
        Record storage outRecord = _records[address(tokenOut)];

        require(tokenAmountOut <= bmul(outRecord.balance, MAX_OUT_RATIO), "OUT_RATIO");

        uint spotPriceBefore = calcSpotPrice(
                                    inRecord.balance,
                                    _getDenormWeight(tokenIn),
                                    outRecord.balance,
                                    _getDenormWeight(tokenOut),
                                    _swapFee
                                );
        require(spotPriceBefore <= maxPrice, "LIMIT_PRICE");

        (uint tokenAmountOutAfterFee, uint tokenAmountOutFee) = calcAmountWithCommunityFee(
            tokenAmountOut,
            _communitySwapFee,
            msg.sender
        );

        tokenAmountIn = calcInGivenOut(
                            inRecord.balance,
                            _getDenormWeight(tokenIn),
                            outRecord.balance,
                            _getDenormWeight(tokenOut),
                            tokenAmountOut,
                            _swapFee
                        );
        require(tokenAmountIn <= maxAmountIn, "LIMIT_IN");

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);
        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        spotPriceAfter = calcSpotPrice(
                                inRecord.balance,
                                _getDenormWeight(tokenIn),
                                outRecord.balance,
                                _getDenormWeight(tokenOut),
                                _swapFee
                            );
        require(
            spotPriceAfter >= spotPriceBefore &&
            spotPriceBefore <= bdiv(tokenAmountIn, tokenAmountOutAfterFee),
            "MATH_APPROX"
        );
        require(spotPriceAfter <= maxPrice, "LIMIT_PRICE");

        emit LOG_SWAP(msg.sender, tokenIn, tokenOut, tokenAmountIn, tokenAmountOutAfterFee);

        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOutAfterFee);
        _pushUnderlying(tokenOut, _communityFeeReceiver, tokenAmountOutFee);

        emit LOG_COMMUNITY_FEE(msg.sender, _communityFeeReceiver, tokenOut, tokenAmountOutFee);

        return (tokenAmountIn, spotPriceAfter);
    }

    /**
     * @dev Pay `tokenAmountIn` of `tokenIn` to mint at least `minPoolAmountOut`
     * pool tokens.
     *
     * The pool implicitly swaps `(1- weightTokenIn) * tokenAmountIn` to the other
     * underlying tokens. Thus a swap fee is charged against the input tokens.
     *
     * @param tokenIn Token to send the pool
     * @param tokenAmountIn Exact amount of `tokenIn` to pay
     * @param minPoolAmountOut Minimum amount of pool tokens to mint
     * @return poolAmountOut - Amount of pool tokens minted
     */
    function joinswapExternAmountIn(address tokenIn, uint tokenAmountIn, uint minPoolAmountOut)
        external override
        _logs_
        _lock_
        returns (uint poolAmountOut)

    {
        _checkSwapsDisabled();
        _preventSameTxOrigin();
        _requireContractIsFinalized();
        _onlyWrapperOrNotWrapperMode();
        _requireTokenIsBound(tokenIn);
        require(tokenAmountIn <= bmul(_records[tokenIn].balance, MAX_IN_RATIO), "MAX_IN_RATIO");

        (uint tokenAmountInAfterFee, uint tokenAmountInFee) = calcAmountWithCommunityFee(
            tokenAmountIn,
            _communityJoinFee,
            msg.sender
        );

        Record storage inRecord = _records[tokenIn];

        poolAmountOut = calcPoolOutGivenSingleIn(
                            inRecord.balance,
                            _getDenormWeight(tokenIn),
                            _totalSupply,
                            _getTotalWeight(),
                            tokenAmountInAfterFee,
                            _swapFee
                        );

        require(poolAmountOut >= minPoolAmountOut, "LIMIT_OUT");

        inRecord.balance = badd(inRecord.balance, tokenAmountInAfterFee);

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountInAfterFee);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOut);
        _pullCommunityFeeUnderlying(tokenIn, msg.sender, tokenAmountInFee);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountInAfterFee);

        emit LOG_COMMUNITY_FEE(msg.sender, _communityFeeReceiver, tokenIn, tokenAmountInFee);

        return poolAmountOut;
    }

    /**
     * @dev Pay up to `maxAmountIn` of `tokenIn` to mint exactly `poolAmountOut`.
     *
     * The pool implicitly swaps `(1- weightTokenIn) * tokenAmountIn` to the other
     * underlying tokens. Thus a swap fee is charged against the input tokens.
     *
     * @param tokenIn Token to send the pool
     * @param poolAmountOut Exact amount of pool tokens to mint
     * @param maxAmountIn Maximum amount of `tokenIn` to pay
     * @return tokenAmountIn - Amount of `tokenIn` paid
     */
    function joinswapPoolAmountOut(address tokenIn, uint poolAmountOut, uint maxAmountIn)
        external override
        _logs_
        _lock_
        returns (uint tokenAmountIn)
    {
        _checkSwapsDisabled();
        _preventSameTxOrigin();
        _requireContractIsFinalized();
        _onlyWrapperOrNotWrapperMode();
        _requireTokenIsBound(tokenIn);

        Record storage inRecord = _records[tokenIn];

        (uint poolAmountOutAfterFee, uint poolAmountOutFee) = calcAmountWithCommunityFee(
            poolAmountOut,
            _communityJoinFee,
            msg.sender
        );

        tokenAmountIn = calcSingleInGivenPoolOut(
                            inRecord.balance,
                            _getDenormWeight(tokenIn),
                            _totalSupply,
                            _getTotalWeight(),
                            poolAmountOut,
                            _swapFee
                        );

        _requireMathApprox(tokenAmountIn);
        require(tokenAmountIn <= maxAmountIn, "LIMIT_IN");

        require(tokenAmountIn <= bmul(_records[tokenIn].balance, MAX_IN_RATIO), "MAX_IN_RATIO");

        inRecord.balance = badd(inRecord.balance, tokenAmountIn);

        emit LOG_JOIN(msg.sender, tokenIn, tokenAmountIn);

        _mintPoolShare(poolAmountOut);
        _pushPoolShare(msg.sender, poolAmountOutAfterFee);
        _pushPoolShare(_communityFeeReceiver, poolAmountOutFee);
        _pullUnderlying(tokenIn, msg.sender, tokenAmountIn);

        emit LOG_COMMUNITY_FEE(msg.sender, _communityFeeReceiver, address(this), poolAmountOutFee);

        return tokenAmountIn;
    }

    /**
     * @dev Burns `poolAmountIn` pool tokens in exchange for at least `minAmountOut`
     * of `tokenOut`. Returns the number of tokens sent to the caller.
     *
     * The pool implicitly burns the tokens for all underlying tokens and swaps them
     * to the desired output token. A swap fee is charged against the output tokens.
     *
     * @param tokenOut Token to receive
     * @param poolAmountIn Exact amount of pool tokens to burn
     * @param minAmountOut Minimum amount of `tokenOut` to receive
     * @return tokenAmountOut - Amount of `tokenOut` received
     */
    function exitswapPoolAmountIn(address tokenOut, uint poolAmountIn, uint minAmountOut)
        external override
        _logs_
        _lock_
        returns (uint tokenAmountOut)
    {
        _checkSwapsDisabled();
        _preventSameTxOrigin();
        _requireContractIsFinalized();
        _onlyWrapperOrNotWrapperMode();
        _requireTokenIsBound(tokenOut);

        Record storage outRecord = _records[tokenOut];

        tokenAmountOut = calcSingleOutGivenPoolIn(
                            outRecord.balance,
                            _getDenormWeight(tokenOut),
                            _totalSupply,
                            _getTotalWeight(),
                            poolAmountIn,
                            _swapFee
                        );

        require(tokenAmountOut >= minAmountOut, "LIMIT_OUT");

        require(tokenAmountOut <= bmul(_records[tokenOut].balance, MAX_OUT_RATIO), "OUT_RATIO");

        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        (uint tokenAmountOutAfterFee, uint tokenAmountOutFee) = calcAmountWithCommunityFee(
            tokenAmountOut,
            _communityExitFee,
            msg.sender
        );

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOutAfterFee);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOutAfterFee);
        _pushUnderlying(tokenOut, _communityFeeReceiver, tokenAmountOutFee);

        emit LOG_COMMUNITY_FEE(msg.sender, _communityFeeReceiver, tokenOut, tokenAmountOutFee);

        return tokenAmountOutAfterFee;
    }

    /**
    * @dev Burn up to `maxPoolAmountIn` for exactly `tokenAmountOut` of `tokenOut`.
    * Returns the number of pool tokens burned.
    *
    * The pool implicitly burns the tokens for all underlying tokens and swaps them
    * to the desired output token. A swap fee is charged against the output tokens.
    *
    * @param tokenOut Token to receive
    * @param tokenAmountOut Exact amount of `tokenOut` to receive
    * @param maxPoolAmountIn Maximum amount of pool tokens to burn
    * @return poolAmountIn - Amount of pool tokens burned
    */
    function exitswapExternAmountOut(address tokenOut, uint tokenAmountOut, uint maxPoolAmountIn)
        external override
        _logs_
        _lock_
        returns (uint poolAmountIn)
    {
        _checkSwapsDisabled();
        _preventSameTxOrigin();
        _requireContractIsFinalized();
        _onlyWrapperOrNotWrapperMode();
        _requireTokenIsBound(tokenOut);
        require(tokenAmountOut <= bmul(_records[tokenOut].balance, MAX_OUT_RATIO), "OUT_RATIO");

        Record storage outRecord = _records[tokenOut];

        (uint tokenAmountOutAfterFee, uint tokenAmountOutFee) = calcAmountWithCommunityFee(
            tokenAmountOut,
            _communityExitFee,
            msg.sender
        );

        poolAmountIn = calcPoolInGivenSingleOut(
                            outRecord.balance,
                            _getDenormWeight(tokenOut),
                            _totalSupply,
                            _getTotalWeight(),
                            tokenAmountOut,
                            _swapFee
                        );

        _requireMathApprox(poolAmountIn);
        require(poolAmountIn <= maxPoolAmountIn, "LIMIT_IN");

        outRecord.balance = bsub(outRecord.balance, tokenAmountOut);

        emit LOG_EXIT(msg.sender, tokenOut, tokenAmountOutAfterFee);

        _pullPoolShare(msg.sender, poolAmountIn);
        _burnPoolShare(poolAmountIn);
        _pushUnderlying(tokenOut, msg.sender, tokenAmountOutAfterFee);
        _pushUnderlying(tokenOut, _communityFeeReceiver, tokenAmountOutFee);

        emit LOG_COMMUNITY_FEE(msg.sender, _communityFeeReceiver, tokenOut, tokenAmountOutFee);

        return poolAmountIn;
    }

    /* ==========  Underlying Token Internal Functions  ========== */

    // 'Underlying' token-manipulation functions make external calls but are NOT locked
    // You must `_lock_` or otherwise ensure reentry-safety

    function _pullUnderlying(address erc20, address from, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transferFrom(from, address(this), amount);
        require(xfer, "ERC20_FALSE");
    }

    function _pushUnderlying(address erc20, address to, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transfer(to, amount);
        require(xfer, "ERC20_FALSE");
    }

    function _pullCommunityFeeUnderlying(address erc20, address from, uint amount)
        internal
    {
        bool xfer = IERC20(erc20).transferFrom(from, _communityFeeReceiver, amount);
        require(xfer, "ERC20_FALSE");
    }

    function _pullPoolShare(address from, uint amount)
        internal
    {
        _pull(from, amount);
    }

    function _pushPoolShare(address to, uint amount)
        internal
    {
        _push(to, amount);
    }

    function _mintPoolShare(uint amount)
        internal
    {
        if(address(_restrictions) != address(0)) {
            uint maxTotalSupply = _restrictions.getMaxTotalSupply(address(this));
            require(badd(_totalSupply, amount) <= maxTotalSupply, "MAX_SUPPLY");
        }
        _mint(amount);
    }

    function _burnPoolShare(uint amount)
        internal
    {
        _burn(amount);
    }

    /* ==========  Require Checks Functions  ========== */

    function _requireTokenIsBound(address token)
        internal view
    {
        require(_records[token].bound, "NOT_BOUND");
    }

    function _onlyController()
        internal view
    {
        require(msg.sender == _controller, "NOT_CONTROLLER");
    }

    function _requireContractIsNotFinalized()
        internal view
    {
        require(!_finalized, "IS_FINALIZED");
    }

    function _requireContractIsFinalized()
        internal view
    {
        require(_finalized, "NOT_FINALIZED");
    }

    function _requireFeeInBounds(uint256 _fee)
        internal pure
    {
        require(_fee >= MIN_FEE && _fee <= MAX_FEE, "FEE_BOUNDS");
    }

    function _requireMathApprox(uint256 _value)
        internal pure
    {
        require(_value != 0, "MATH_APPROX");
    }

    function _preventReentrancy()
        internal view
    {
        require(!_mutex, "REENTRY");
    }

    function _onlyWrapperOrNotWrapperMode()
        internal view
    {
        require(!_wrapperMode || msg.sender == _wrapper, "ONLY_WRAPPER");
    }

    function _preventSameTxOrigin()
        internal
    {
      require(block.number > _lastSwapBlock[tx.origin], "SAME_TX_ORIGIN");
      _lastSwapBlock[tx.origin] = block.number;
    }

    function _checkSwapsDisabled()
        internal
    {
      require(!_swapsDisabled, "SWAPS_DISABLED");
    }

    /* ==========  Token Query Internal Functions  ========== */

    function _getDenormWeight(address token)
        internal view virtual
        returns (uint)
    {
        return _records[token].denorm;
    }

    function _getTotalWeight()
        internal view virtual
        returns (uint)
    {
        return _totalWeight;
    }

    function _addTotalWeight(uint _amount) internal virtual {
    }

    function _subTotalWeight(uint _amount) internal virtual {
    }

    /* ==========  Other Public getters  ========== */
    /**
    * @dev Calculate result amount after taking community fee.
    * @param tokenAmountIn Token amount.
    * @param communityFee Community fee amount.
    * @return tokenAmountInAfterFee Amount after taking fee.
    * @return tokenAmountFee Result fee amount.
    */
    function calcAmountWithCommunityFee(
        uint tokenAmountIn,
        uint communityFee,
        address operator
    )
        public view override
        returns (uint tokenAmountInAfterFee, uint tokenAmountFee)
    {
        if (address(_restrictions) != address(0) && _restrictions.isWithoutFee(operator)) {
            return (tokenAmountIn, 0);
        }
        uint adjustedIn = bsub(BONE, communityFee);
        tokenAmountInAfterFee = bmul(tokenAmountIn, adjustedIn);
        tokenAmountFee = bsub(tokenAmountIn, tokenAmountInAfterFee);
        return (tokenAmountInAfterFee, tokenAmountFee);
    }

    /**
    * @dev Returns MIN_WEIGHT constant.
    * @return MIN_WEIGHT.
    */
    function getMinWeight()
        external view override
        returns (uint)
    {
        return MIN_WEIGHT;
    }

    /**
    * @dev Returns MAX_BOUND_TOKENS constant.
    * @return MAX_BOUND_TOKENS.
    */
    function getMaxBoundTokens()
        external view override
        returns (uint)
    {
      return MAX_BOUND_TOKENS;
    }
}
