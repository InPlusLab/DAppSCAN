// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./libs/@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "./IDerivativeSpecification.sol";
import "./registries/IAddressRegistry.sol";
import "./IVaultBuilder.sol";
import "./IPausableVault.sol";

/// @title Vault Factory implementation contract
/// @notice Creates new vaults and registers them in internal storage
contract VaultFactory is OwnableUpgradeSafe {
    address[] internal _vaults;

    IAddressRegistry public derivativeSpecificationRegistry;
    IAddressRegistry public oracleRegistry;
    IAddressRegistry public collateralTokenRegistry;
    IAddressRegistry public collateralSplitRegistry;
    address public tokenBuilder;
    address public feeLogger;

    /// @notice protocol fee multiplied by 10 ^ 12
    uint256 public protocolFee;
    /// @notice protocol fee receiving wallet
    address public feeWallet;
    /// @notice author above limit fee multiplied by 10 ^ 12
    uint256 public authorFeeLimit;

    IVaultBuilder public vaultBuilder;
    IAddressRegistry public oracleIteratorRegistry;

    /// @notice redeem function can only be called after the end of the Live period + delay
    uint256 public settlementDelay;

    event VaultCreated(
        bytes32 indexed derivativeSymbol,
        address vault,
        address specification
    );

    /// @notice Initializes vault factory contract storage
    /// @dev Used only once when vault factory is created for the first time
    // SWC-114-Transaction Order Dependence: L46 - L79
    function initialize(
        address _derivativeSpecificationRegistry,
        address _oracleRegistry,
        address _oracleIteratorRegistry,
        address _collateralTokenRegistry,
        address _collateralSplitRegistry,
        address _tokenBuilder,
        address _feeLogger,
        uint256 _protocolFee,
        address _feeWallet,
        uint256 _authorFeeLimit,
        address _vaultBuilder,
        uint256 _settlementDelay
    ) external initializer {
        __Ownable_init();

        setDerivativeSpecificationRegistry(_derivativeSpecificationRegistry);
        setOracleRegistry(_oracleRegistry);
        setOracleIteratorRegistry(_oracleIteratorRegistry);
        setCollateralTokenRegistry(_collateralTokenRegistry);
        setCollateralSplitRegistry(_collateralSplitRegistry);

        setTokenBuilder(_tokenBuilder);
        setFeeLogger(_feeLogger);
        setVaultBuilder(_vaultBuilder);

        setSettlementDelay(_settlementDelay);

        protocolFee = _protocolFee;
        authorFeeLimit = _authorFeeLimit;

        require(_feeWallet != address(0), "Fee wallet");
        feeWallet = _feeWallet;
    }

    /// @notice Creates a new vault based on derivative specification symbol and initialization timestamp
    /// @dev Initialization timestamp allows to target a specific start time for Live period
    /// @param _derivativeSymbolHash a symbol hash which resolves to the derivative specification
    /// @param _liveTime vault live timestamp
    function createVault(bytes32 _derivativeSymbolHash, uint256 _liveTime)
        external
    {
        IDerivativeSpecification derivativeSpecification =
            IDerivativeSpecification(
                derivativeSpecificationRegistry.get(_derivativeSymbolHash)
            );
        require(
            address(derivativeSpecification) != address(0),
            "Specification is absent"
        );

        address collateralToken =
            collateralTokenRegistry.get(
                derivativeSpecification.collateralTokenSymbol()
            );
        address collateralSplit =
            collateralSplitRegistry.get(
                derivativeSpecification.collateralSplitSymbol()
            );

        address[] memory oracles;
        address[] memory oracleIterators;
        (oracles, oracleIterators) = getOraclesAndIterators(
            derivativeSpecification
        );

        require(_liveTime > 0, "Zero live time");

        address vault =
            vaultBuilder.buildVault(
                _liveTime,
                protocolFee,
                feeWallet,
                address(derivativeSpecification),
                collateralToken,
                oracles,
                oracleIterators,
                collateralSplit,
                tokenBuilder,
                feeLogger,
                authorFeeLimit,
                settlementDelay
            );
        emit VaultCreated(
            _derivativeSymbolHash,
            vault,
            address(derivativeSpecification)
        );
        _vaults.push(vault);
    }

    function getOraclesAndIterators(
        IDerivativeSpecification _derivativeSpecification
    )
        internal
        returns (address[] memory _oracles, address[] memory _oracleIterators)
    {
        bytes32[] memory oracleSymbols =
            _derivativeSpecification.oracleSymbols();
        bytes32[] memory oracleIteratorSymbols =
            _derivativeSpecification.oracleIteratorSymbols();
        require(
            oracleSymbols.length == oracleIteratorSymbols.length,
            "Oracles and iterators length"
        );

        _oracles = new address[](oracleSymbols.length);
        _oracleIterators = new address[](oracleIteratorSymbols.length);
        for (uint256 i = 0; i < oracleSymbols.length; i++) {
            address oracle = oracleRegistry.get(oracleSymbols[i]);
            require(address(oracle) != address(0), "Oracle is absent");
            _oracles[i] = oracle;

            address oracleIterator =
                oracleIteratorRegistry.get(oracleIteratorSymbols[i]);
            require(
                address(oracleIterator) != address(0),
                "OracleIterator is absent"
            );
            _oracleIterators[i] = oracleIterator;
        }
    }

    function setProtocolFee(uint256 _protocolFee) external onlyOwner {
        protocolFee = _protocolFee;
    }

    function setAuthorFeeLimit(uint256 _authorFeeLimit) external onlyOwner {
        authorFeeLimit = _authorFeeLimit;
    }

    function setTokenBuilder(address _tokenBuilder) public onlyOwner {
        require(_tokenBuilder != address(0), "Token builder");
        tokenBuilder = _tokenBuilder;
    }

    function setFeeLogger(address _feeLogger) public onlyOwner {
        require(_feeLogger != address(0), "Fee logger");
        feeLogger = _feeLogger;
    }

    function setVaultBuilder(address _vaultBuilder) public onlyOwner {
        require(_vaultBuilder != address(0), "Vault builder");
        vaultBuilder = IVaultBuilder(_vaultBuilder);
    }

    function setSettlementDelay(uint256 _settlementDelay) public onlyOwner {
        settlementDelay = _settlementDelay;
    }

    function setDerivativeSpecificationRegistry(
        address _derivativeSpecificationRegistry
    ) public onlyOwner {
        require(
            _derivativeSpecificationRegistry != address(0),
            "Derivative specification registry"
        );
        derivativeSpecificationRegistry = IAddressRegistry(
            _derivativeSpecificationRegistry
        );
    }

    function setOracleRegistry(address _oracleRegistry) public onlyOwner {
        require(_oracleRegistry != address(0), "Oracle registry");
        oracleRegistry = IAddressRegistry(_oracleRegistry);
    }

    function setOracleIteratorRegistry(address _oracleIteratorRegistry)
        public
        onlyOwner
    {
        require(
            _oracleIteratorRegistry != address(0),
            "Oracle iterator registry"
        );
        oracleIteratorRegistry = IAddressRegistry(_oracleIteratorRegistry);
    }

    function setCollateralTokenRegistry(address _collateralTokenRegistry)
        public
        onlyOwner
    {
        require(
            _collateralTokenRegistry != address(0),
            "Collateral token registry"
        );
        collateralTokenRegistry = IAddressRegistry(_collateralTokenRegistry);
    }

    function setCollateralSplitRegistry(address _collateralSplitRegistry)
        public
        onlyOwner
    {
        require(
            _collateralSplitRegistry != address(0),
            "Collateral split registry"
        );
        collateralSplitRegistry = IAddressRegistry(_collateralSplitRegistry);
    }

    function pauseVault(address _vault) public onlyOwner {
        IPausableVault(_vault).pause();
    }

    function unpauseVault(address _vault) public onlyOwner {
        IPausableVault(_vault).unpause();
    }

    function setDerivativeSpecification(address _value) external {
        derivativeSpecificationRegistry.set(_value);
    }

    function setOracle(address _value) external {
        oracleRegistry.set(_value);
    }

    function setOracleIterator(address _value) external {
        oracleIteratorRegistry.set(_value);
    }

    function setCollateralToken(address _value) external {
        collateralTokenRegistry.set(_value);
    }

    function setCollateralSplit(address _value) external {
        collateralSplitRegistry.set(_value);
    }

    /// @notice Returns vault based on internal index
    /// @param _index internal vault index
    /// @return vault address
    function getVault(uint256 _index) external view returns (address) {
        return _vaults[_index];
    }

    /// @notice Get last created vault index
    /// @return last created vault index
    function getLastVaultIndex() external view returns (uint256) {
        return _vaults.length - 1;
    }

    /// @notice Get all previously created vaults
    /// @return all previously created vaults
    function getAllVaults() external view returns (address[] memory) {
        return _vaults;
    }

    uint256[50] private __gap;
}
