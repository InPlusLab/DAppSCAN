pragma solidity ^0.5.4;

import "./Errors/RegistryErrors.sol";

/// @title Opium.Registry contract keeps addresses of deployed Opium contracts set to allow them route and communicate to each other
contract Registry is RegistryErrors {

    // Address of Opium.TokenMinter contract
    address private minter;

    // Address of Opium.Core contract
    address private core;

    // Address of Opium.OracleAggregator contract
    address private oracleAggregator;

    // Address of Opium.SyntheticAggregator contract
    address private syntheticAggregator;

    // Address of Opium commission receiver
    address private opiumAddress;

    // Address of Opium.TokenSpender contract
    address private tokenSpender;

    // Address of Opium contract set deployer
    address public initializer;

    /// @notice This modifier restricts access to functions, which could be called only by initializer
    modifier onlyInitializer() {
        require(msg.sender == initializer, ERROR_REGISTRY_ONLY_INITIALIZER);
        _;
    }

    /// @notice Sets initializer
    constructor() public {
        initializer = msg.sender;
    }

    // SETTERS

    /// @notice Sets Opium.TokenMinter address and allows to do it only once
    /// @param _minter address Address of Opium.TokenMinter
    function setMinter(address _minter) external onlyInitializer {
        require(minter == address(0), ERROR_REGISTRY_ALREADY_SET);
        minter = _minter;
    }

    /// @notice Sets Opium.Core address and allows to do it only once
    /// @param _core address Address of Opium.Core
    function setCore(address _core) external onlyInitializer {
        require(core == address(0), ERROR_REGISTRY_ALREADY_SET);
        core = _core;
    }

    /// @notice Sets Opium.OracleAggregator address and allows to do it only once
    /// @param _oracleAggregator address Address of Opium.OracleAggregator
    function setOracleAggregator(address _oracleAggregator) external onlyInitializer {
        require(oracleAggregator == address(0), ERROR_REGISTRY_ALREADY_SET);
        oracleAggregator = _oracleAggregator;
    }

    /// @notice Sets Opium.SyntheticAggregator address and allows to do it only once
    /// @param _syntheticAggregator address Address of Opium.SyntheticAggregator
    function setSyntheticAggregator(address _syntheticAggregator) external onlyInitializer {
        require(syntheticAggregator == address(0), ERROR_REGISTRY_ALREADY_SET);
        syntheticAggregator = _syntheticAggregator;
    }

    /// @notice Sets Opium commission receiver and allows to do it only once
    /// @param _opiumAddress address Address of Opium commission receiver
    function setOpiumAddress(address _opiumAddress) external onlyInitializer {
        require(opiumAddress == address(0), ERROR_REGISTRY_ALREADY_SET);
        opiumAddress = _opiumAddress;
    }

    /// @notice Sets Opium.TokenSpender address and allows to do it only once
    /// @param _tokenSpender address Address of Opium.TokenSpender
    function setTokenSpender(address _tokenSpender) external onlyInitializer {
        require(tokenSpender == address(0), ERROR_REGISTRY_ALREADY_SET);
        tokenSpender = _tokenSpender;
    }

    /// @notice Allows opium commission receiver address to change itself
    /// @param _opiumAddress address New opium commission receiver address
    function changeOpiumAddress(address _opiumAddress) external {
        require(opiumAddress == msg.sender, ERROR_REGISTRY_ONLY_OPIUM_ADDRESS_ALLOWED);
        opiumAddress = _opiumAddress;
    }

    // GETTERS

    /// @notice Returns address of Opium.Core
    /// @param result address Address of Opium.Core
    function getCore() external view returns (address result) {
        return core;
    }

    /// @notice Returns address of Opium.TokenMinter
    /// @param result address Address of Opium.TokenMinter
    function getMinter() external view returns (address result) {
        return minter;
    }

    /// @notice Returns address of Opium.OracleAggregator
    /// @param result address Address of Opium.OracleAggregator
    function getOracleAggregator() external view returns (address result) {
        return oracleAggregator;
    }

    /// @notice Returns address of Opium.SyntheticAggregator
    /// @param result address Address of Opium.SyntheticAggregator
    function getSyntheticAggregator() external view returns (address result) {
        return syntheticAggregator;
    }

    /// @notice Returns address of Opium commission receiver
    /// @param result address Address of Opium commission receiver
    function getOpiumAddress() external view returns (address result) {
        return opiumAddress;
    }

    /// @notice Returns address of Opium.TokenSpender
    /// @param result address Address of Opium.TokenSpender
    function getTokenSpender() external view returns (address result) {
        return tokenSpender;
    }
}