// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";

import {IKODAV3Minter} from "../core/IKODAV3Minter.sol";
import {IKODAV3PrimarySaleMarketplace} from "../marketplace/KODAV3PrimaryMarketplace.sol";
import {ICollabRoyaltiesRegistry} from "../collab/ICollabRoyaltiesRegistry.sol";
import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";

contract MintingFactory is Context {

    event EditionMintedAndListed(uint256 indexed _editionId, SaleType _saleType);

    event MintingFactoryCreated();
    event AdminMintingPeriodChanged(uint256 _mintingPeriod);
    event AdminMaxMintsInPeriodChanged(uint256 _maxMintsInPeriod);
    event AdminFrequencyOverrideChanged(address _account, bool _override);
    event AdminRoyaltiesRegistryChanged(address _royaltiesRegistry);

    modifier onlyAdmin() {
        require(accessControls.hasAdminRole(_msgSender()), "Caller must have admin role");
        _;
    }

    modifier canMintAgain(){
        require(_canCreateNewEdition(_msgSender()), "Caller unable to create yet");
        _;
    }

    IKOAccessControlsLookup public accessControls;
    IKODAV3Minter public koda;
    IKODAV3PrimarySaleMarketplace public marketplace;
    ICollabRoyaltiesRegistry public royaltiesRegistry;

    // Minting allowance period
    uint256 public mintingPeriod = 30 days;

    // Limit of mints with in the period
    uint256 public maxMintsInPeriod = 15;

    // Frequency override list for users - you can temporarily add in address which disables the freeze time check
    mapping(address => bool) public frequencyOverride;

    struct MintingPeriod {
        uint128 mints;
        uint128 firstMintInPeriod;
    }

    // How many mints within the current minting period
    mapping(address => MintingPeriod) mintingPeriodConfig;

    enum SaleType {
        BUY_NOW, OFFERS, STEPPED, RESERVE
    }

    constructor(
        IKOAccessControlsLookup _accessControls,
        IKODAV3Minter _koda,
        IKODAV3PrimarySaleMarketplace _marketplace,
        ICollabRoyaltiesRegistry _royaltiesRegistry
    ) {
        accessControls = _accessControls;
        koda = _koda;
        marketplace = _marketplace;
        royaltiesRegistry = _royaltiesRegistry;

        emit MintingFactoryCreated();
    }

    function mintToken(
        SaleType _saleType,
        uint128 _startDate,
        uint128 _basePrice,
        uint128 _stepPrice,
        string calldata _uri,
        uint256 _merkleIndex,
        bytes32[] calldata _merkleProof,
        address _deployedRoyaltiesHandler
    ) canMintAgain external {
        require(accessControls.isVerifiedArtist(_merkleIndex, _msgSender(), _merkleProof), "Caller must have minter role");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(1, _msgSender(), _uri);

        _setupSalesMechanic(editionId, _saleType, _startDate, _basePrice, _stepPrice);
        _recordSuccessfulMint(_msgSender());
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    function mintTokenAsProxy(
        address _creator,
        SaleType _saleType,
        uint128 _startDate,
        uint128 _basePrice,
        uint128 _stepPrice,
        string calldata _uri,
        address _deployedRoyaltiesHandler
    ) canMintAgain external {
        require(accessControls.isVerifiedArtistProxy(_creator, _msgSender()), "Caller is not artist proxy");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(1, _creator, _uri);

        _setupSalesMechanic(editionId, _saleType, _startDate, _basePrice, _stepPrice);
        _recordSuccessfulMint(_creator);
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    function mintBatchEdition(
        SaleType _saleType,
        uint16 _editionSize,
        uint128 _startDate,
        uint128 _basePrice,
        uint128 _stepPrice,
        string calldata _uri,
        uint256 _merkleIndex,
        bytes32[] calldata _merkleProof,
        address _deployedRoyaltiesHandler
    ) canMintAgain external {
        require(accessControls.isVerifiedArtist(_merkleIndex, _msgSender(), _merkleProof), "Caller must have minter role");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _msgSender(), _uri);

        _setupSalesMechanic(editionId, _saleType, _startDate, _basePrice, _stepPrice);
        _recordSuccessfulMint(_msgSender());
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    function mintBatchEditionAsProxy(
        address _creator,
        SaleType _saleType,
        uint16 _editionSize,
        uint128 _startDate,
        uint128 _basePrice,
        uint128 _stepPrice,
        string calldata _uri,
        address _deployedRoyaltiesHandler
    ) canMintAgain external {
        require(accessControls.isVerifiedArtistProxy(_creator, _msgSender()), "Caller is not artist proxy");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _creator, _uri);

        _setupSalesMechanic(editionId, _saleType, _startDate, _basePrice, _stepPrice);
        _recordSuccessfulMint(_creator);
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    function mintBatchEditionAndComposeERC20s(
        SaleType _saleType,
    // --- _config array (expected length of 5) ---
    // Index 0 - Merkle Index
    // Index 1 - Edition size
    // Index 2 - Start Date
    // Index 3 - Base price
    // Index 4 - Step price
    // ---------------------------------------------
        uint128[] calldata _config,
        string calldata _uri,
        address[] calldata _erc20s,
        uint256[] calldata _amounts,
        bytes32[] calldata _merkleProof
    ) canMintAgain external {
        require(accessControls.isVerifiedArtist(_config[0], _msgSender(), _merkleProof), "Caller must have minter role");
        require(_config.length == 5, "Config must consist of 5 elements in the array");

        uint256 editionId = koda.mintBatchEditionAndComposeERC20s(uint16(_config[1]), _msgSender(), _uri, _erc20s, _amounts);

        _setupSalesMechanic(editionId, _saleType, _config[2], _config[3], _config[4]);
        _recordSuccessfulMint(_msgSender());
    }

    function mintBatchEditionAndComposeERC20sAsProxy(
        address _creator,
        SaleType _saleType,
    // --- _config array (expected length of 4) ---
    // Index 0 - Edition size
    // Index 1 - Start Date
    // Index 2 - Base price
    // Index 3 - Step price
    // ---------------------------------------------
        uint128[] calldata _config,
        string calldata _uri,
        address[] calldata _erc20s,
        uint256[] calldata _amounts
    ) canMintAgain external {
        require(accessControls.isVerifiedArtistProxy(_creator, _msgSender()), "Caller is not artist proxy");
        require(_config.length == 4, "Config must consist of 4 elements in the array");

        uint256 editionId = koda.mintBatchEditionAndComposeERC20s(uint16(_config[0]), _creator, _uri, _erc20s, _amounts);

        _setupSalesMechanic(editionId, _saleType, _config[1], _config[2], _config[3]);
        _recordSuccessfulMint(_creator);
    }

    function mintConsecutiveBatchEdition(
        SaleType _saleType,
        uint16 _editionSize,
        uint128 _startDate,
        uint128 _basePrice,
        uint128 _stepPrice,
        string calldata _uri,
        uint256 _merkleIndex,
        bytes32[] calldata _merkleProof,
        address _deployedRoyaltiesHandler
    ) canMintAgain external {
        require(accessControls.isVerifiedArtist(_merkleIndex, _msgSender(), _merkleProof), "Caller must have minter role");

        // Make tokens & edition
        uint256 editionId = koda.mintConsecutiveBatchEdition(_editionSize, _msgSender(), _uri);

        _setupSalesMechanic(editionId, _saleType, _startDate, _basePrice, _stepPrice);
        _recordSuccessfulMint(_msgSender());
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    function mintConsecutiveBatchEditionAsProxy(
        address _creator,
        SaleType _saleType,
        uint16 _editionSize,
        uint128 _startDate,
        uint128 _basePrice,
        uint128 _stepPrice,
        string calldata _uri,
        address _deployedRoyaltiesHandler
    ) canMintAgain external {
        require(accessControls.isVerifiedArtistProxy(_creator, _msgSender()), "Caller is not artist proxy");

        // Make tokens & edition
        uint256 editionId = koda.mintConsecutiveBatchEdition(_editionSize, _creator, _uri);

        _setupSalesMechanic(editionId, _saleType, _startDate, _basePrice, _stepPrice);
        _recordSuccessfulMint(_creator);
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    function _setupSalesMechanic(uint256 _editionId, SaleType _saleType, uint128 _startDate, uint128 _basePrice, uint128 _stepPrice) internal {
        if (SaleType.BUY_NOW == _saleType) {
            marketplace.listForBuyNow(_msgSender(), _editionId, _basePrice, _startDate);
        }
        else if (SaleType.STEPPED == _saleType) {
            marketplace.listSteppedEditionAuction(_msgSender(), _editionId, _basePrice, _stepPrice, _startDate);
        }
        else if (SaleType.OFFERS == _saleType) {
            marketplace.enableEditionOffers(_editionId, _startDate);
        } else if (SaleType.RESERVE == _saleType) {
            // use base price for reserve price
            marketplace.listForReserveAuction(_msgSender(), _editionId, _basePrice, _startDate);
        }

        emit EditionMintedAndListed(_editionId, _saleType);
    }

    function _setupRoyalties(uint256 _editionId, address _deployedHandler) internal {
        if (_deployedHandler != address(0) && address(royaltiesRegistry) != address(0)) {
            royaltiesRegistry.useRoyaltiesRecipient(_editionId, _deployedHandler);
        }
    }

    /// Internal helpers

    function _canCreateNewEdition(address _account) internal view returns (bool) {
        // if frequency is overridden then assume they can mint
        if (frequencyOverride[_account]) {
            return true;
        }

        // if within the period range, check remaining allowance
        if (_getNow() <= mintingPeriodConfig[_account].firstMintInPeriod + mintingPeriod) {
            return mintingPeriodConfig[_account].mints < maxMintsInPeriod;
        }

        // if period expired - can mint another one
        return true;
    }

    function _recordSuccessfulMint(address _account) internal {
        MintingPeriod storage period = mintingPeriodConfig[_account];

        uint256 endOfCurrentMintingPeriodLimit = period.firstMintInPeriod + mintingPeriod;

        // if first time use, set the first timestamp to be now abd start counting
        if (period.firstMintInPeriod == 0) {
            period.firstMintInPeriod = _getNow();
            period.mints = period.mints + 1;
        }
        // if still within the minting period, record the new mint
        else if (_getNow() <= endOfCurrentMintingPeriodLimit) {
            period.mints = period.mints + 1;
        }
        // if we are outside of the window reset the limit and record a new single mint
        else if (endOfCurrentMintingPeriodLimit < _getNow()) {
            period.mints = 1;
            period.firstMintInPeriod = _getNow();
        }
    }

    function _getNow() internal virtual view returns (uint128) {
        return uint128(block.timestamp);
    }

    /// Public helpers

    function canCreateNewEdition(address _account) public view returns (bool) {
        return _canCreateNewEdition(_account);
    }

    function currentMintConfig(address _account) public view returns (uint128 mints, uint128 firstMintInPeriod) {
        MintingPeriod memory config = mintingPeriodConfig[_account];
        return (
        config.mints,
        config.firstMintInPeriod
        );
    }

    function setFrequencyOverride(address _account, bool _override) onlyAdmin public {
        frequencyOverride[_account] = _override;
        emit AdminFrequencyOverrideChanged(_account, _override);
    }

    function setMintingPeriod(uint256 _mintingPeriod) onlyAdmin public {
        mintingPeriod = _mintingPeriod;
        emit AdminMintingPeriodChanged(_mintingPeriod);
    }

    function setRoyaltiesRegistry(ICollabRoyaltiesRegistry _royaltiesRegistry) onlyAdmin public {
        royaltiesRegistry = _royaltiesRegistry;
        emit AdminRoyaltiesRegistryChanged(address(_royaltiesRegistry));
    }

    function setMaxMintsInPeriod(uint256 _maxMintsInPeriod) onlyAdmin public {
        maxMintsInPeriod = _maxMintsInPeriod;
        emit AdminMaxMintsInPeriodChanged(_maxMintsInPeriod);
    }

}
