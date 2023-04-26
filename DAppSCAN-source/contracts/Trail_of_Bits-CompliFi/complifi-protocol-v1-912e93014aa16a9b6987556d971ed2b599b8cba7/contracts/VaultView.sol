// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

import "./IVault.sol";
import "./tokens/IERC20Metadata.sol";

/// @title Reading key data from specified Vault
contract VaultView {
    /// @notice Contains key information about a Vault
    struct Vault {
        address self;
        uint256 liveTime;
        uint256 settleTime;
        int256 underlyingStart;
        int256 underlyingEnd;
        uint256 primaryConversion;
        uint256 complementConversion;
        uint256 protocolFee;
        uint256 authorFeeLimit;
        uint256 state;
        address oracle;
        uint256 oracleDecimals;
        address oracleIterator;
        address collateralSplit;
        bool isPaused;
    }

    /// @notice Contains key information about a derivative token
    struct Token {
        address self;
        string name;
        string symbol;
        uint8 decimals;
        uint256 userBalance;
    }

    /// @notice Contains key information from Derivative Specification
    struct DerivativeSpecification {
        address self;
        string name;
        string symbol;
        uint256 denomination;
        uint256 authorFee;
        uint256 primaryNominalValue;
        uint256 complementNominalValue;
        bytes32[] oracleSymbols;
    }

    // Using vars to avoid stack do deep error
    struct Vars {
        IVault vault;
        IDerivativeSpecification specification;
        IERC20Metadata collateral;
        IERC20 collateralToken;
        IERC20Metadata primary;
        IERC20Metadata complement;
    }

    /// @notice Getting information about a Vault, its derivative tokens and specification
    /// @param _vault vault address
    /// @return vaultData vault-specific information
    /// @return derivativeSpecificationData vault's derivative specification
    /// @return collateralData vault's collateral token metadata
    /// @return lockedCollateralAmount vault's total locked collateral amount
    /// @return primaryData vault's primary token metadata
    /// @return complementData vault's complement token metadata
    function getVaultInfo(address _vault, address _sender)
        external
        view
        returns (
            Vault memory vaultData,
            DerivativeSpecification memory derivativeSpecificationData,
            Token memory collateralData,
            uint256 lockedCollateralAmount,
            Token memory primaryData,
            Token memory complementData
        )
    {
        Vars memory vars;
        vars.vault = IVault(_vault);

        int256 underlyingStarts = 0;
        if (uint256(vars.vault.state()) > 0) {
            underlyingStarts = vars.vault.underlyingStarts(0);
        }

        int256 underlyingEnds = 0;
        if (
            vars.vault.primaryConversion() > 0 ||
            vars.vault.complementConversion() > 0
        ) {
            underlyingEnds = vars.vault.underlyingEnds(0);
        }

        vaultData = Vault(
            _vault,
            vars.vault.liveTime(),
            vars.vault.settleTime(),
            underlyingStarts,
            underlyingEnds,
            vars.vault.primaryConversion(),
            vars.vault.complementConversion(),
            vars.vault.protocolFee(),
            vars.vault.authorFeeLimit(),
            uint256(vars.vault.state()),
            vars.vault.oracles(0),
            AggregatorV3Interface(vars.vault.oracles(0)).decimals(),
            vars.vault.oracleIterators(0),
            vars.vault.collateralSplit(),
            vars.vault.paused()
        );

        vars.specification = vars.vault.derivativeSpecification();
        derivativeSpecificationData = DerivativeSpecification(
            address(vars.specification),
            vars.specification.name(),
            vars.specification.symbol(),
            vars.specification.primaryNominalValue() +
                vars.specification.complementNominalValue(),
            vars.specification.authorFee(),
            vars.specification.primaryNominalValue(),
            vars.specification.complementNominalValue(),
            vars.specification.oracleSymbols()
        );

        vars.collateral = IERC20Metadata(vars.vault.collateralToken());
        vars.collateralToken = IERC20(address(vars.collateral));
        collateralData = Token(
            address(vars.collateral),
            vars.collateral.name(),
            vars.collateral.symbol(),
            vars.collateral.decimals(),
            _sender == address(0) ? 0 : vars.collateralToken.balanceOf(_sender)
        );
        lockedCollateralAmount = vars.collateralToken.balanceOf(_vault);

        vars.primary = IERC20Metadata(vars.vault.primaryToken());
        primaryData = Token(
            address(vars.primary),
            vars.primary.name(),
            vars.primary.symbol(),
            vars.primary.decimals(),
            _sender == address(0)
                ? 0
                : IERC20(address(vars.primary)).balanceOf(_sender)
        );

        vars.complement = IERC20Metadata(vars.vault.complementToken());
        complementData = Token(
            address(vars.complement),
            vars.complement.name(),
            vars.complement.symbol(),
            vars.complement.decimals(),
            _sender == address(0)
                ? 0
                : IERC20(address(vars.complement)).balanceOf(_sender)
        );
    }

    /// @notice Getting vault derivative token balances
    /// @param _owner address for which balances are being extracted
    /// @param _vaults list of all vaults
    /// @return primaries primary token balances
    /// @return complements complement token balances
    function getVaultTokenBalancesByOwner(
        address _owner,
        address[] calldata _vaults
    )
        external
        view
        returns (uint256[] memory primaries, uint256[] memory complements)
    {
        primaries = new uint256[](_vaults.length);
        complements = new uint256[](_vaults.length);

        IVault vault;
        for (uint256 i = 0; i < _vaults.length; i++) {
            vault = IVault(_vaults[i]);
            primaries[i] = IERC20(vault.primaryToken()).balanceOf(_owner);
            complements[i] = IERC20(vault.complementToken()).balanceOf(_owner);
        }
    }

    /// @notice Getting any ERC20 token balances
    /// @param _owner address for which balances are being extracted
    /// @param _tokens list of all tokens
    /// @return balances token balances
    function getERC20BalancesByOwner(address _owner, address[] calldata _tokens)
        external
        view
        returns (uint256[] memory balances)
    {
        balances = new uint256[](_tokens.length);

        for (uint256 i = 0; i < _tokens.length; i++) {
            balances[i] = IERC20(_tokens[i]).balanceOf(_owner);
        }
    }
}
