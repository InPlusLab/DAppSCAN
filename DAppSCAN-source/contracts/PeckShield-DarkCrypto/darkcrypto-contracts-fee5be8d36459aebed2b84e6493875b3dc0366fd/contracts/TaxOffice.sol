// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./owner/Operator.sol";
import "./interfaces/ITaxable.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IERC20.sol";

contract TaxOffice is Operator {
    using SafeMath for uint256;

    address public dark;
    address public uniRouter;

    constructor(
        address _dark,
        address _uniRouter
    ) public {
        require(_dark != address(0), "dark address cannot be 0");
        require(_uniRouter != address(0), "uniRouter address cannot be 0");
        dark = _dark;
        uniRouter = _uniRouter;
    }

    mapping(address => bool) public taxExclusionEnabled;

    function setTaxTiersTwap(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        return ITaxable(dark).setTaxTiersTwap(_index, _value);
    }

    function setTaxTiersRate(uint8 _index, uint256 _value) public onlyOperator returns (bool) {
        require(_value <= 3000, "tax equal or less than 30%");
        return ITaxable(dark).setTaxTiersRate(_index, _value);
    }

    function enableAutoCalculateTax() public onlyOperator {
        ITaxable(dark).enableAutoCalculateTax();
    }

    function disableAutoCalculateTax() public onlyOperator {
        ITaxable(dark).disableAutoCalculateTax();
    }

    function setTaxRate(uint256 _taxRate) public onlyOperator {
        require(_taxRate <= 3000, "tax equal or less than 30%");
        ITaxable(dark).setTaxRate(_taxRate);
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyOperator {
        ITaxable(dark).setBurnThreshold(_burnThreshold);
    }

    function setTaxCollectorAddress(address _taxCollectorAddress) public onlyOperator {
        ITaxable(dark).setTaxCollectorAddress(_taxCollectorAddress);
    }

    function excludeAddressFromTax(address _address) external onlyOperator returns (bool) {
        return _excludeAddressFromTax(_address);
    }

    function _excludeAddressFromTax(address _address) private returns (bool) {
        if (!ITaxable(dark).isAddressExcluded(_address)) {
            return ITaxable(dark).excludeAddress(_address);
        }
    }

    function includeAddressInTax(address _address) external onlyOperator returns (bool) {
        return _includeAddressInTax(_address);
    }

    function _includeAddressInTax(address _address) private returns (bool) {
        if (ITaxable(dark).isAddressExcluded(_address)) {
            return ITaxable(dark).includeAddress(_address);
        }
    }

    function taxRate() external view returns (uint256) {
        return ITaxable(dark).taxRate();
    }

    function addLiquidityTaxFree(
        address token,
        uint256 amtDark,
        uint256 amtToken,
        uint256 amtDarkMin,
        uint256 amtTokenMin
    )
        external
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtDark != 0 && amtToken != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(dark).transferFrom(msg.sender, address(this), amtDark);
        IERC20(token).transferFrom(msg.sender, address(this), amtToken);
        _approveTokenIfNeeded(dark, uniRouter);
        _approveTokenIfNeeded(token, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtDark;
        uint256 resultAmtToken;
        uint256 liquidity;
        (resultAmtDark, resultAmtToken, liquidity) = IUniswapV2Router(uniRouter).addLiquidity(
            dark,
            token,
            amtDark,
            amtToken,
            amtDarkMin,
            amtTokenMin,
            msg.sender,
            block.timestamp
        );

        if(amtDark.sub(resultAmtDark) > 0) {
            IERC20(dark).transfer(msg.sender, amtDark.sub(resultAmtDark));
        }
        if(amtToken.sub(resultAmtToken) > 0) {
            IERC20(token).transfer(msg.sender, amtToken.sub(resultAmtToken));
        }
        return (resultAmtDark, resultAmtToken, liquidity);
    }

    function addLiquidityETHTaxFree(
        uint256 amtDark,
        uint256 amtDarkMin,
        uint256 amtFtmMin
    )
        external
        payable
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(amtDark != 0 && msg.value != 0, "amounts can't be 0");
        _excludeAddressFromTax(msg.sender);

        IERC20(dark).transferFrom(msg.sender, address(this), amtDark);
        _approveTokenIfNeeded(dark, uniRouter);

        _includeAddressInTax(msg.sender);

        uint256 resultAmtDark;
        uint256 resultAmtFtm;
        uint256 liquidity;
        (resultAmtDark, resultAmtFtm, liquidity) = IUniswapV2Router(uniRouter).addLiquidityETH{value: msg.value}(
            dark,
            amtDark,
            amtDarkMin,
            amtFtmMin,
            msg.sender,
            block.timestamp
        );

        if(amtDark.sub(resultAmtDark) > 0) {
            IERC20(dark).transfer(msg.sender, amtDark.sub(resultAmtDark));
        }
        return (resultAmtDark, resultAmtFtm, liquidity);
    }

    function setTaxableDarkOracle(address _darkOracle) external onlyOperator {
        ITaxable(dark).setDarkOracle(_darkOracle);
    }

    function transferTaxOffice(address _newTaxOffice) external onlyOperator {
        ITaxable(dark).setTaxOffice(_newTaxOffice);
    }

    function taxFreeTransferFrom(
        address _sender,
        address _recipient,
        uint256 _amt
    ) external {
        require(taxExclusionEnabled[msg.sender], "Address not approved for tax free transfers");
        _excludeAddressFromTax(_sender);
        IERC20(dark).transferFrom(_sender, _recipient, _amt);
        _includeAddressInTax(_sender);
    }

    function setTaxExclusionForAddress(address _address, bool _excluded) external onlyOperator {
        taxExclusionEnabled[_address] = _excluded;
    }

    function _approveTokenIfNeeded(address _token, address _router) private {
        if (IERC20(_token).allowance(address(this), _router) == 0) {
            IERC20(_token).approve(_router, type(uint256).max);
        }
    }
}
