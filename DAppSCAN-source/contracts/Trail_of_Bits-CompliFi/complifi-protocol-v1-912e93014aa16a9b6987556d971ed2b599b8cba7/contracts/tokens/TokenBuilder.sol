// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./ITokenBuilder.sol";
import "./ERC20PresetMinterPermitted.sol";
import "./IERC20Metadata.sol";
import "../IDerivativeSpecification.sol";
import "./TokenMetadataGenerator.sol";

contract TokenBuilder is ITokenBuilder, TokenMetadataGenerator {
    string public constant PRIMARY_TOKEN_NAME_POSTFIX = " UP";
    string public constant COMPLEMENT_TOKEN_NAME_POSTFIX = " DOWN";
    string public constant PRIMARY_TOKEN_SYMBOL_POSTFIX = "-UP";
    string public constant COMPLEMENT_TOKEN_SYMBOL_POSTFIX = "-DOWN";
    uint8 public constant DECIMALS_DEFAULT = 18;

    event DerivativeTokensCreated(
        address primaryTokenAddress,
        address complementTokenAddress
    );

    function isTokenBuilder() external pure override returns (bool) {
        return true;
    }

    function buildTokens(
        IDerivativeSpecification _derivativeSpecification,
        uint256 _settlement,
        address _collateralToken
    ) external override returns (IERC20MintedBurnable, IERC20MintedBurnable) {
        string memory settlementDate = formatDate(_settlement);

        uint8 decimals = IERC20Metadata(_collateralToken).decimals();
        if (decimals == 0) {
            decimals = DECIMALS_DEFAULT;
        }

        address primaryToken =
            address(
                new ERC20PresetMinterPermitted(
                    makeTokenName(
                        _derivativeSpecification.name(),
                        settlementDate,
                        PRIMARY_TOKEN_NAME_POSTFIX
                    ),
                    makeTokenSymbol(
                        _derivativeSpecification.symbol(),
                        settlementDate,
                        PRIMARY_TOKEN_SYMBOL_POSTFIX
                    ),
                    msg.sender,
                    decimals
                )
            );

        address complementToken =
            address(
                new ERC20PresetMinterPermitted(
                    makeTokenName(
                        _derivativeSpecification.name(),
                        settlementDate,
                        COMPLEMENT_TOKEN_NAME_POSTFIX
                    ),
                    makeTokenSymbol(
                        _derivativeSpecification.symbol(),
                        settlementDate,
                        COMPLEMENT_TOKEN_SYMBOL_POSTFIX
                    ),
                    msg.sender,
                    decimals
                )
            );

        emit DerivativeTokensCreated(primaryToken, complementToken);

        return (
            IERC20MintedBurnable(primaryToken),
            IERC20MintedBurnable(complementToken)
        );
    }
}
