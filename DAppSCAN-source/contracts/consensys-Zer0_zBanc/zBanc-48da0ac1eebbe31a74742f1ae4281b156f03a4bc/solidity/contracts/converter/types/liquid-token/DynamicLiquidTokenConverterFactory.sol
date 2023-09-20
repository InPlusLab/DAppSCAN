// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity 0.6.12;
import "./DynamicLiquidTokenConverter.sol";
import "../../../token/interfaces/IDSToken.sol";
import "../../../utility/TokenHolder.sol";
// SWC-135-Code With No Effects: L7
import "../../interfaces/ITypedConverterFactory.sol";
import "../../../token/DSToken.sol";

/*
    DynamicLiquidTokenConverter Factory
*/
contract DynamicLiquidTokenConverterFactory is TokenHolder {
    IERC20Token internal constant ETH_RESERVE_ADDRESS = IERC20Token(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
    event NewConverter(DynamicLiquidTokenConverter indexed _converter, address indexed _owner);
    event NewToken(DSToken indexed _token);

    /**
      * @dev creates a new token & dynamic converter
      *
      * @param _name                token name
      * @param _symbol              token short symbol, minimum 1 character
      * @param _decimals            number of decimals
      * @param _initialSupply       initial token supply - issued to caller
      * @param _reserveToken        token to use as the reserve in the converter
      * @param _reserveBalance      initial balance to give the converter in the
      *                             reserve token. caller must have approved the token
      *                             or sent the value in the case of and ETH reserve
      * @param _registry            address of a contract registry contract
      * @param _maxConversionFee    maximum conversion fee, represented in ppm
      * @param _minimumWeight       minimum that reserve weight can be reduced to. value in PPM
      * @param _stepWeight          amount that weight is reduce with each call. value in PPM
      * @param _marketCapThreshold  value that market cap must increase between weight reductions.
      *
      * @return a new token
    */
    function createToken(
      string memory _name,
      string memory _symbol,
      uint8 _decimals,
      uint256 _initialSupply,
      IERC20Token _reserveToken,
      uint32 _reserveWeight,
      uint256 _reserveBalance,
      IContractRegistry _registry,
      uint32 _maxConversionFee,
      uint32 _minimumWeight,
      uint32 _stepWeight,
      uint256 _marketCapThreshold
    )
      public
      payable
      virtual
      returns (DSToken)
    {
        DSToken token = new DSToken(_name, _symbol, _decimals);

        token.issue(msg.sender, _initialSupply);

        emit NewToken(token);

        createConverter(
          token,
          _reserveToken,
          _reserveWeight,
          _reserveBalance,
          _registry,
          _maxConversionFee,
          _minimumWeight,
          _stepWeight,
          _marketCapThreshold
        );

        return token;
    }

    /**
      * @dev creates a new converter with the given arguments and transfers
      * the ownership to the caller
      *
      * @param _anchor              anchor governed by the converter
      * @param _reserveToken        token to use as the reserve in the converter
      * @param _reserveBalance      initial balance to give the converter in the
      *                             reserve token. caller must have approved the token
      *                             or sent the value in the case of and ETH reserve
      * @param _registry            address of a contract registry contract
      * @param _maxConversionFee    maximum conversion fee, represented in ppm
      * @param _minimumWeight       minimum that reserve weight can be reduced to. value in PPM
      * @param _stepWeight          amount that weight is reduce with each call. value in PPM
      * @param _marketCapThreshold  value that market cap must increase between weight reductions.
      *
      * @return a new converter
    */
    function createConverter(
      IConverterAnchor _anchor,
      IERC20Token _reserveToken,
      uint32 _reserveWeight,
      uint256 _reserveBalance,
      IContractRegistry _registry,
      uint32 _maxConversionFee,
      uint32 _minimumWeight,
      uint32 _stepWeight,
      uint256 _marketCapThreshold
    )
      public
      payable
      virtual
      returns (DynamicLiquidTokenConverter)
    {
        DynamicLiquidTokenConverter converter = new DynamicLiquidTokenConverter(IDSToken(address(_anchor)), _registry, _maxConversionFee);

        require(_reserveToken == ETH_RESERVE_ADDRESS ? msg.value == _reserveBalance : msg.value == 0, "ERR_ETH_AMOUNT_MISMATCH");

        converter.addReserve(_reserveToken, _reserveWeight);

        if (_reserveBalance > 0)
          if (_reserveToken == ETH_RESERVE_ADDRESS)
              address(converter).transfer(msg.value);
          else
              safeTransferFrom(_reserveToken, msg.sender, address(converter), _reserveBalance);

        converter.setMinimumWeight(_minimumWeight);
        converter.setStepWeight(_stepWeight);
        converter.setMarketCapThreshold(_marketCapThreshold);

        if (_anchor.owner() != address(this))
          _anchor.acceptOwnership();

        _anchor.transferOwnership(address(converter));
        converter.acceptAnchorOwnership();

        converter.transferOwnership(msg.sender);

        emit NewConverter(converter, msg.sender);

        return converter;
    }

    function converterType() public pure returns (uint16) {
        return 3;
    }
}
