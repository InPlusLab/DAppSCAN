pragma solidity ^0.4.24;

import "../dex/ITokenConverter.sol";


/**
* @title ERC20 Interface with burn
* @dev IERC20 imported in ItokenConverter.sol
*/
contract ERC20 is IERC20 {
    function burn(uint256 _value) public;
}


/**
* @title Interface for contracts conforming to ERC-721
*/
contract LANDRegistry {
    function assignMultipleParcels(int[] x, int[] y, address beneficiary) external;
}


contract LANDAuctionStorage {
    uint256 constant public PERCENTAGE_OF_TOKEN_BALANCE = 5;
    uint256 constant public MAX_DECIMALS = 18;

    enum Status { created, finished }

    struct Func {
        uint256 slope;
        uint256 base;
        uint256 limit;
    }

    struct Token {
        uint256 decimals;
        bool shouldBurnTokens;
        bool shouldForwardTokens;
        address forwardTarget;
        bool isAllowed;
    }

    uint256 public conversionFee = 105;
    uint256 public totalBids = 0;
    Status public status;
    uint256 public gasPriceLimit;
    uint256 public landsLimitPerBid;
    ERC20 public manaToken;
    LANDRegistry public landRegistry;
    ITokenConverter public dex;
    mapping (address => Token) public tokensAllowed;
    uint256 public totalManaBurned = 0;
    uint256 public totalLandsBidded = 0;
    uint256 public startTime;
    uint256 public endTime;
    uint256 public initialPrice;
    uint256 public endPrice;
    uint256 public duration;

    Func[] internal curves;

    event AuctionCreated(
      address indexed _caller,
      uint256 _startTime,
      uint256 _duration,
      uint256 _initialPrice,
      uint256 _endPrice
    );

    event BidConversion(
      uint256 _bidId,
      address indexed _token,
      uint256 _requiredManaAmountToBurn,
      uint256 _amountOfTokenConverted,
      uint256 _requiredTokenBalance
    );

    event BidSuccessful(
      uint256 _bidId,
      address indexed _beneficiary,
      address indexed _token,
      uint256 _pricePerLandInMana,
      uint256 _manaAmountToBurn,
      int[] _xs,
      int[] _ys
    );

    event AuctionFinished(
      address indexed _caller,
      uint256 _time,
      uint256 _pricePerLandInMana
    );

    event TokenBurned(
      uint256 _bidId,
      address indexed _token,
      uint256 _total
    );

    event TokenTransferred(
      uint256 _bidId,
      address indexed _token,
      address indexed _to,
      uint256 _total
    );

    event LandsLimitPerBidChanged(
      address indexed _caller,
      uint256 _oldLandsLimitPerBid, 
      uint256 _landsLimitPerBid
    );

    event GasPriceLimitChanged(
      address indexed _caller,
      uint256 _oldGasPriceLimit,
      uint256 _gasPriceLimit
    );

    event DexChanged(
      address indexed _caller,
      address indexed _oldDex,
      address indexed _dex
    );

    event TokenAllowed(
      address indexed _caller,
      address indexed _address,
      uint256 _decimals,
      bool _shouldBurnTokens,
      bool _shouldForwardTokens,
      address indexed _forwardTarget
    );

    event TokenDisabled(
      address indexed _caller,
      address indexed _address
    );

    event ConversionFeeChanged(
      address indexed _caller,
      uint256 _oldConversionFee,
      uint256 _conversionFee
    );
}
