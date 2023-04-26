pragma solidity ^0.4.24;

import "openzeppelin-eth/contracts/ownership/Ownable.sol";
import "openzeppelin-eth/contracts/math/SafeMath.sol";
import "openzeppelin-eth/contracts/utils/Address.sol";

import "../libs/SafeERC20.sol";
import "./LANDAuctionStorage.sol";


contract LANDAuction is Ownable, LANDAuctionStorage {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for ERC20;

    /**
    * @dev Constructor of the contract.
    * Note that the last value of _xPoints will be the total duration and
    * the first value of _yPoints will be the initial price and the last value will be the endPrice
    * @param _xPoints - uint256[] of seconds
    * @param _yPoints - uint256[] of prices
    * @param _startTime - uint256 timestamp in seconds when the auction will start
    * @param _landsLimitPerBid - uint256 LAND limit for a single bid
    * @param _gasPriceLimit - uint256 gas price limit for a single bid
    * @param _manaToken - address of the MANA token
    * @param _landRegistry - address of the LANDRegistry
    * @param _dex - address of the Dex to convert ERC20 tokens allowed to MANA
    */
    constructor(
        uint256[] _xPoints, 
        uint256[] _yPoints, 
        uint256 _startTime,
        uint256 _landsLimitPerBid,
        uint256 _gasPriceLimit,
        ERC20 _manaToken,
        LANDRegistry _landRegistry,
        address _dex
    ) public {
        require(
            PERCENTAGE_OF_TOKEN_BALANCE == 5, 
            "Balance of tokens required should be equal to 5%"
        );
        // Initialize owneable
        Ownable.initialize(msg.sender);

        // Schedule auction
        require(_startTime > block.timestamp, "Started time should be after now");
        startTime = _startTime;

        // Set LANDRegistry
        require(
            address(_landRegistry).isContract(),
            "The LANDRegistry token address must be a deployed contract"
        );
        landRegistry = _landRegistry;

        setDex(_dex);

        // Set MANAToken
        allowToken(
            address(_manaToken), 
            18,
            true, 
            false, 
            address(0)
        );
        manaToken = _manaToken;

        // Set total duration of the auction
        duration = _xPoints[_xPoints.length - 1];
        require(duration > 1 days, "The duration should be greater than 1 day");

        // Set Curve
        _setCurve(_xPoints, _yPoints);

        // Set limits
        setLandsLimitPerBid(_landsLimitPerBid);
        setGasPriceLimit(_gasPriceLimit);
        
        // Initialize status
        status = Status.created;      

        emit AuctionCreated(
            msg.sender,
            startTime,
            duration,
            initialPrice, 
            endPrice
        );
    }

    /**
    * @dev Make a bid for LANDs
    * @param _xs - uint256[] x values for the LANDs to bid
    * @param _ys - uint256[] y values for the LANDs to bid
    * @param _beneficiary - address beneficiary for the LANDs to bid
    * @param _fromToken - token used to bid
    */
    function bid(
        int[] _xs, 
        int[] _ys, 
        address _beneficiary, 
        ERC20 _fromToken
    )
        external 
    {
        _validateBidParameters(
            _xs, 
            _ys, 
            _beneficiary, 
            _fromToken
        );
        
        uint256 bidId = _getBidId();
        uint256 bidPriceInMana = _xs.length.mul(getCurrentPrice());
        uint256 manaAmountToBurn = bidPriceInMana;

        if (address(_fromToken) != address(manaToken)) {
            require(
                address(dex).isContract(), 
                "Paying with other tokens has been disabled"
            );
            // Convert from the other token to MANA. The amount to be burned might be smaller
            // because 5% will be burned or forwarded without converting it to MANA.
            manaAmountToBurn = _convertSafe(bidId, _fromToken, bidPriceInMana);
        } else {
            // Transfer MANA to this contract
            require(
                _fromToken.safeTransferFrom(msg.sender, address(this), bidPriceInMana),
                "Insuficient balance or unauthorized amount (transferFrom failed)"
            );
        }

        // Process funds (burn or forward them)
        _processFunds(bidId, _fromToken);

        // Assign LANDs to the beneficiary user
        landRegistry.assignMultipleParcels(_xs, _ys, _beneficiary);

        emit BidSuccessful(
            bidId,
            _beneficiary,
            _fromToken,
            getCurrentPrice(),
            manaAmountToBurn,
            _xs,
            _ys
        );  

        // Update stats
        _updateStats(_xs.length, manaAmountToBurn);        
    }

    /** 
    * @dev Validate bid function params
    * @param _xs - int[] x values for the LANDs to bid
    * @param _ys - int[] y values for the LANDs to bid
    * @param _beneficiary - address beneficiary for the LANDs to bid
    * @param _fromToken - token used to bid
    */
    function _validateBidParameters(
        int[] _xs, 
        int[] _ys, 
        address _beneficiary, 
        ERC20 _fromToken
    ) internal view 
    {
        require(startTime <= block.timestamp, "The auction has not started");
        require(
            status == Status.created && 
            block.timestamp.sub(startTime) <= duration, 
            "The auction has finished"
        );
        require(tx.gasprice <= gasPriceLimit, "Gas price limit exceeded");
        require(_beneficiary != address(0), "The beneficiary could not be the 0 address");
        require(_xs.length > 0, "You should bid for at least one LAND");
        require(_xs.length <= landsLimitPerBid, "LAND limit exceeded");
        require(_xs.length == _ys.length, "X values length should be equal to Y values length");
        require(tokensAllowed[address(_fromToken)].isAllowed, "Token not allowed");
        for (uint256 i = 0; i < _xs.length; i++) {
            require(
                -150 <= _xs[i] && _xs[i] <= 150 && -150 <= _ys[i] && _ys[i] <= 150,
                "The coordinates should be inside bounds -150 & 150"
            );
        }
    }

    /**
    * @dev Current LAND price. 
    * Note that if the auction has not started returns the initial price and when
    * the auction is finished return the endPrice
    * @return uint256 current LAND price
    */
    function getCurrentPrice() public view returns (uint256) { 
        // If the auction has not started returns initialPrice
        if (startTime == 0 || startTime >= block.timestamp) {
            return initialPrice;
        }

        // If the auction has finished returns endPrice
        uint256 timePassed = block.timestamp - startTime;
        if (timePassed >= duration) {
            return endPrice;
        }

        return _getPrice(timePassed);
    }

    /**
    * @dev Convert allowed token to MANA and transfer the change in the original token
    * Note that we will use the slippageRate cause it has a 3% buffer and a deposit of 5% to cover
    * the conversion fee.
    * @param _bidId - uint256 of the bid Id
    * @param _fromToken - ERC20 token to be converted
    * @param _bidPriceInMana - uint256 of the total amount in MANA
    * @return uint256 of the total amount of MANA to burn
    */
    function _convertSafe(
        uint256 _bidId,
        ERC20 _fromToken,
        uint256 _bidPriceInMana
    ) internal returns (uint256 requiredManaAmountToBurn)
    {
        requiredManaAmountToBurn = _bidPriceInMana;
        Token memory fromToken = tokensAllowed[address(_fromToken)];

        uint256 bidPriceInManaPlusSafetyMargin = _bidPriceInMana.mul(conversionFee).div(100);

        // Get rate
        uint256 tokenRate = getRate(manaToken, _fromToken, bidPriceInManaPlusSafetyMargin);

        // Check if contract should burn or transfer some tokens
        uint256 requiredTokenBalance = 0;
        
        if (fromToken.shouldBurnTokens || fromToken.shouldForwardTokens) {
            requiredTokenBalance = _calculateRequiredTokenBalance(requiredManaAmountToBurn, tokenRate);
            requiredManaAmountToBurn = _calculateRequiredManaAmount(_bidPriceInMana);
        }

        // Calculate the amount of _fromToken to be converted
        uint256 tokensToConvertPlusSafetyMargin = bidPriceInManaPlusSafetyMargin
            .mul(tokenRate)
            .div(10 ** 18);

        // Normalize to _fromToken decimals
        if (MAX_DECIMALS > fromToken.decimals) {
            requiredTokenBalance = _normalizeDecimals(
                fromToken.decimals, 
                requiredTokenBalance
            );
            tokensToConvertPlusSafetyMargin = _normalizeDecimals(
                fromToken.decimals,
                tokensToConvertPlusSafetyMargin
            );
        }

        // Retrieve tokens from the sender to this contract
        require(
            _fromToken.safeTransferFrom(msg.sender, address(this), tokensToConvertPlusSafetyMargin),
            "Transfering the totalPrice in token to LANDAuction contract failed"
        );
        
        // Calculate the total tokens to convert
        uint256 finalTokensToConvert = tokensToConvertPlusSafetyMargin.sub(requiredTokenBalance);

        // Approve amount of _fromToken owned by contract to be used by dex contract
        require(_fromToken.safeApprove(address(dex), finalTokensToConvert), "Error approve");

        // Convert _fromToken to MANA
        uint256 change = dex.convert(
                _fromToken,
                manaToken,
                finalTokensToConvert,
                requiredManaAmountToBurn
        );

       // Return change in _fromToken to sender
        if (change > 0) {
            // Return the change of src token
            require(
                _fromToken.safeTransfer(msg.sender, change),
                "Transfering the change to sender failed"
            );
        }

        // Remove approval of _fromToken owned by contract to be used by dex contract
        require(_fromToken.clearApprove(address(dex)), "Error clear approval");

        emit BidConversion(
            _bidId,
            address(_fromToken),
            requiredManaAmountToBurn,
            tokensToConvertPlusSafetyMargin.sub(change),
            requiredTokenBalance
        );
    }

    /**
    * @dev Get exchange rate
    * @param _srcToken - IERC20 token
    * @param _destToken - IERC20 token 
    * @param _srcAmount - uint256 amount to be converted
    * @return uint256 of the rate
    */
    function getRate(
        IERC20 _srcToken, 
        IERC20 _destToken, 
        uint256 _srcAmount
    ) public view returns (uint256 rate) 
    {
        (rate,) = dex.getExpectedRate(_srcToken, _destToken, _srcAmount);
    }

    /** 
    * @dev Calculate the amount of tokens to process
    * @param _totalPrice - uint256 price to calculate percentage to process
    * @param _tokenRate - rate to calculate the amount of tokens
    * @return uint256 of the amount of tokens required
    */
    function _calculateRequiredTokenBalance(
        uint256 _totalPrice,
        uint256 _tokenRate
    ) 
    internal pure returns (uint256) 
    {
        return _totalPrice.mul(_tokenRate)
            .div(10 ** 18)
            .mul(PERCENTAGE_OF_TOKEN_BALANCE)
            .div(100);
    }

    /** 
    * @dev Calculate the total price in MANA
    * Note that PERCENTAGE_OF_TOKEN_BALANCE will be always less than 100
    * @param _totalPrice - uint256 price to calculate percentage to keep
    * @return uint256 of the new total price in MANA
    */
    function _calculateRequiredManaAmount(
        uint256 _totalPrice
    ) 
    internal pure returns (uint256)
    {
        return _totalPrice.mul(100 - PERCENTAGE_OF_TOKEN_BALANCE).div(100);
    }

    /**
    * @dev Burn or forward the MANA and other tokens earned
    * Note that as we will transfer or burn tokens from other contracts.
    * We should burn MANA first to avoid a possible re-entrancy
    * @param _bidId - uint256 of the bid Id
    * @param _token - ERC20 token
    */
    function _processFunds(uint256 _bidId, ERC20 _token) internal {
        // Burn MANA
        _burnTokens(_bidId, manaToken);

        // Burn or forward token if it is not MANA
        Token memory token = tokensAllowed[address(_token)];
        if (_token != manaToken) {
            if (token.shouldBurnTokens) {
                _burnTokens(_bidId, _token);
            }
            if (token.shouldForwardTokens) {
                _forwardTokens(_bidId, token.forwardTarget, _token);
            }   
        }
    }

    /**
    * @dev LAND price based on time
    * Note that will select the function to calculate based on the time
    * It should return endPrice if _time < duration
    * @param _time - uint256 time passed before reach duration
    * @return uint256 price for the given time
    */
    function _getPrice(uint256 _time) internal view returns (uint256) {
        for (uint256 i = 0; i < curves.length; i++) {
            Func storage func = curves[i];
            if (_time < func.limit) {
                return func.base.sub(func.slope.mul(_time));
            }
        }
        revert("Invalid time");
    }

    /** 
    * @dev Burn tokens
    * @param _bidId - uint256 of the bid Id
    * @param _token - ERC20 token
    */
    function _burnTokens(uint256 _bidId, ERC20 _token) private {
        uint256 balance = _token.balanceOf(address(this));

        // Check if balance is valid
        require(balance > 0, "Balance to burn should be > 0");
        
        _token.burn(balance);

        emit TokenBurned(_bidId, address(_token), balance);

        // Check if balance of the auction contract is empty
        balance = _token.balanceOf(address(this));
        require(balance == 0, "Burn token failed");
    }

    /** 
    * @dev Forward tokens
    * @param _bidId - uint256 of the bid Id
    * @param _address - address to send the tokens to
    * @param _token - ERC20 token
    */
    function _forwardTokens(uint256 _bidId, address _address, ERC20 _token) private {
        uint256 balance = _token.balanceOf(address(this));

        // Check if balance is valid
        require(balance > 0, "Balance to burn should be > 0");
        
        _token.safeTransfer(_address, balance);

        emit TokenTransferred(
            _bidId, 
            address(_token), 
            _address,balance
        );

        // Check if balance of the auction contract is empty
        balance = _token.balanceOf(address(this));
        require(balance == 0, "Transfer token failed");
    }

    /**
    * @dev Set conversion fee rate
    * @param _fee - uint256 for the new conversion rate
    */
    function setConversionFee(uint256 _fee) external onlyOwner {
        require(_fee < 200 && _fee >= 100, "Conversion fee should be >= 100 and < 200");
        emit ConversionFeeChanged(msg.sender, conversionFee, _fee);
        conversionFee = _fee;
    }

    /**
    * @dev Finish auction 
    */
    function finishAuction() public onlyOwner {
        require(status != Status.finished, "The auction is finished");

        uint256 currentPrice = getCurrentPrice();

        status = Status.finished;
        endTime = block.timestamp;

        emit AuctionFinished(msg.sender, block.timestamp, currentPrice);
    }

    /**
    * @dev Set LAND for the auction
    * @param _landsLimitPerBid - uint256 LAND limit for a single id
    */
    function setLandsLimitPerBid(uint256 _landsLimitPerBid) public onlyOwner {
        require(_landsLimitPerBid > 0, "The LAND limit should be greater than 0");
        emit LandsLimitPerBidChanged(msg.sender, landsLimitPerBid, _landsLimitPerBid);
        landsLimitPerBid = _landsLimitPerBid;
    }

    /**
    * @dev Set gas price limit for the auction
    * @param _gasPriceLimit - uint256 gas price limit for a single bid
    */
    function setGasPriceLimit(uint256 _gasPriceLimit) public onlyOwner {
        require(_gasPriceLimit > 0, "The gas price should be greater than 0");
        emit GasPriceLimitChanged(msg.sender, gasPriceLimit, _gasPriceLimit);
        gasPriceLimit = _gasPriceLimit;
    }

    /**
    * @dev Set dex to convert ERC20
    * @param _dex - address of the token converter
    */
    function setDex(address _dex) public onlyOwner {
        require(_dex != address(dex), "The dex is the current");
        if (_dex != address(0)) {
            require(_dex.isContract(), "The dex address must be a deployed contract");
        }
        emit DexChanged(msg.sender, dex, _dex);
        dex = ITokenConverter(_dex);
    }

    /**
    * @dev Allow ERC20 to to be used for bidding
    * Note that if _shouldBurnTokens and _shouldForwardTokens are false, we 
    * will convert the total amount of the ERC20 to MANA
    * @param _address - address of the ERC20 Token
    * @param _decimals - uint256 of the number of decimals
    * @param _shouldBurnTokens - boolean whether we should burn funds
    * @param _shouldForwardTokens - boolean whether we should transferred funds
    * @param _forwardTarget - address where the funds will be transferred
    */
    function allowToken(
        address _address,
        uint256 _decimals,
        bool _shouldBurnTokens,
        bool _shouldForwardTokens,
        address _forwardTarget
    ) 
    public onlyOwner 
    {
        require(
            _address.isContract(),
            "Tokens allowed should be a deployed ERC20 contract"
        );
        require(
            _decimals > 0 && _decimals <= MAX_DECIMALS,
            "Decimals should be greather than 0 and less or equal to 18"
        );
        require(
            !(_shouldBurnTokens && _shouldForwardTokens),
            "The token should be either burned or transferred"
        );
        require(
            !_shouldForwardTokens || 
            (_shouldForwardTokens && _forwardTarget != address(0)),
            "The token should be transferred to a deployed contract"
        );
        require(
            _forwardTarget != address(this) && _forwardTarget != _address, 
            "The forward target should be different from  this contract and the erc20 token"
        );
        
        require(!tokensAllowed[_address].isAllowed, "The ERC20 token is already allowed");

        tokensAllowed[_address] = Token({
            decimals: _decimals,
            shouldBurnTokens: _shouldBurnTokens,
            shouldForwardTokens: _shouldForwardTokens,
            forwardTarget: _forwardTarget,
            isAllowed: true
        });

        emit TokenAllowed(
            msg.sender, 
            _address, 
            _decimals,
            _shouldBurnTokens,
            _shouldForwardTokens,
            _forwardTarget
        );
    }

    /**
    * @dev Disable ERC20 to to be used for bidding
    * @param _address - address of the ERC20 Token
    */
    function disableToken(address _address) public onlyOwner {
        require(
            tokensAllowed[_address].isAllowed,
            "The ERC20 token is already disabled"
        );
        delete tokensAllowed[_address];
        emit TokenDisabled(msg.sender, _address);
    }

    /** 
    * @dev Create a combined function.
    * note that we will set N - 1 function combinations based on N points (x,y)
    * @param _xPoints - uint256[] of x values
    * @param _yPoints - uint256[] of y values
    */
    function _setCurve(uint256[] _xPoints, uint256[] _yPoints) internal {
        uint256 pointsLength = _xPoints.length;
        require(pointsLength == _yPoints.length, "Points should have the same length");
        for (uint256 i = 0; i < pointsLength - 1; i++) {
            uint256 x1 = _xPoints[i];
            uint256 x2 = _xPoints[i + 1];
            uint256 y1 = _yPoints[i];
            uint256 y2 = _yPoints[i + 1];
            require(x1 < x2, "X points should increase");
            require(y1 > y2, "Y points should decrease");
            (uint256 base, uint256 slope) = _getFunc(
                x1, 
                x2, 
                y1, 
                y2
            );
            curves.push(Func({
                base: base,
                slope: slope,
                limit: x2
            }));
        }

        initialPrice = _yPoints[0];
        endPrice = _yPoints[pointsLength - 1];
    }

    /**
    * @dev Calculate base and slope for the given points
    * It is a linear function y = ax - b. But The slope should be negative.
    * As we want to avoid negative numbers in favor of using uints we use it as: y = b - ax
    * Based on two points (x1; x2) and (y1; y2)
    * base = (x2 * y1) - (x1 * y2) / (x2 - x1)
    * slope = (y1 - y2) / (x2 - x1) to avoid negative maths
    * @param _x1 - uint256 x1 value
    * @param _x2 - uint256 x2 value
    * @param _y1 - uint256 y1 value
    * @param _y2 - uint256 y2 value
    * @return uint256 for the base
    * @return uint256 for the slope
    */
    function _getFunc(
        uint256 _x1,
        uint256 _x2,
        uint256 _y1, 
        uint256 _y2
    ) internal pure returns (uint256 base, uint256 slope) 
    {
        base = ((_x2.mul(_y1)).sub(_x1.mul(_y2))).div(_x2.sub(_x1));
        slope = (_y1.sub(_y2)).div(_x2.sub(_x1));
    }

    /**
    * @dev Return bid id
    * @return uint256 of the bid id
    */
    function _getBidId() private view returns (uint256) {
        return totalBids;
    }

    /** 
    * @dev Normalize to _fromToken decimals
    * @param _decimals - uint256 of _fromToken decimals
    * @param _value - uint256 of the amount to normalize
    */
    function _normalizeDecimals(
        uint256 _decimals, 
        uint256 _value
    ) 
    internal pure returns (uint256 _result) 
    {
        _result = _value.div(10**MAX_DECIMALS.sub(_decimals));
    }

    /** 
    * @dev Update stats. It will update the following stats:
    * - totalBids
    * - totalLandsBidded
    * - totalManaBurned
    * @param _landsBidded - uint256 of the number of LAND bidded
    * @param _manaAmountBurned - uint256 of the amount of MANA burned
    */
    function _updateStats(uint256 _landsBidded, uint256 _manaAmountBurned) private {
        totalBids = totalBids.add(1);
        totalLandsBidded = totalLandsBidded.add(_landsBidded);
        totalManaBurned = totalManaBurned.add(_manaAmountBurned);
    }
}
