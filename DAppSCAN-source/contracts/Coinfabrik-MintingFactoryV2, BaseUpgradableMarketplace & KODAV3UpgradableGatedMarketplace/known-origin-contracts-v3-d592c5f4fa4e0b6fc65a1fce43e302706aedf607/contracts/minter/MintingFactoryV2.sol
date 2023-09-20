// SPDX-License-Identifier: MIT
// SWC-102-Outdated Compiler Version: L3
pragma solidity 0.8.4;

import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IKODAV3Minter} from "../core/IKODAV3Minter.sol";
import {IKODAV3PrimarySaleMarketplace, IKODAV3GatedMarketplace} from "../marketplace/IKODAV3Marketplace.sol";
import {ICollabRoyaltiesRegistry} from "../collab/ICollabRoyaltiesRegistry.sol";
import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";

contract MintingFactoryV2 is Context, UUPSUpgradeable {

    event EditionMinted(uint256 indexed _editionId);
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

    modifier canMintAgain(address _sender) {
        require(_canCreateNewEdition(_sender), "Caller unable to create yet");
        _;
    }

    struct MintingPeriod {
        uint128 mints;
        uint128 firstMintInPeriod;
    }

    enum SaleType {
        BUY_NOW, OFFERS, STEPPED, RESERVE
    }

    // Minting allowance period
    uint256 public mintingPeriod;

    // Limit of mints with in the period
    uint256 public maxMintsInPeriod;

    // Frequency override list for users - you can temporarily add in address which disables the freeze time check
    mapping(address => bool) public frequencyOverride;

    // How many mints within the current minting period
    mapping(address => MintingPeriod) mintingPeriodConfig;

    IKOAccessControlsLookup public accessControls;
    IKODAV3Minter public koda;
    IKODAV3PrimarySaleMarketplace public marketplace;
    IKODAV3GatedMarketplace public gatedMarketplace;
    ICollabRoyaltiesRegistry public royaltiesRegistry;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer {}

    function initialize(
        IKOAccessControlsLookup _accessControls,
        IKODAV3Minter _koda,
        IKODAV3PrimarySaleMarketplace _marketplace,
        IKODAV3GatedMarketplace _gatedMarketplace,
        ICollabRoyaltiesRegistry _royaltiesRegistry
    ) public initializer {

        accessControls = _accessControls;
        koda = _koda;
        marketplace = _marketplace;
        gatedMarketplace = _gatedMarketplace;
        royaltiesRegistry = _royaltiesRegistry;

        mintingPeriod = 30 days;
        maxMintsInPeriod = 15;

        emit MintingFactoryCreated();
    }

    function _authorizeUpgrade(address newImplementation) internal view override {
        require(accessControls.hasAdminRole(msg.sender), "Only admin can upgrade");
    }

    //////////////////////////////////////////
    /// Mint & setup on primary marketplace //
    //////////////////////////////////////////

// SWC-107-Reentrancy: L93 - L112
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
    ) canMintAgain(_msgSender()) external {
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
    ) canMintAgain(_creator) external {
        require(accessControls.isVerifiedArtistProxy(_creator, _msgSender()), "Caller is not artist proxy");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _creator, _uri);

        _setupSalesMechanic(editionId, _saleType, _startDate, _basePrice, _stepPrice);
        _recordSuccessfulMint(_creator);
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    //////////////////////////////////////
    /// Mint & setup on gated only drop //
    //////////////////////////////////////

    function mintBatchEditionGatedOnly(
        uint16 _editionSize,
        uint256 _merkleIndex,
        bytes32[] calldata _merkleProof,
        address _deployedRoyaltiesHandler,
        string calldata _uri
    ) canMintAgain(_msgSender()) external {
        require(accessControls.isVerifiedArtist(_merkleIndex, _msgSender(), _merkleProof), "Caller must have minter role");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _msgSender(), _uri);

        // Created gated sale
        gatedMarketplace.createSale(editionId);

        _recordSuccessfulMint(_msgSender());
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    function mintBatchEditionGatedOnlyAsProxy(
        address _creator,
        uint16 _editionSize,
        address _deployedRoyaltiesHandler,
        string calldata _uri
    ) canMintAgain(_creator) external {
        require(accessControls.isVerifiedArtistProxy(_creator, _msgSender()), "Caller is not artist proxy");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _creator, _uri);

        // Created gated sale
        gatedMarketplace.createSale(editionId);

        _recordSuccessfulMint(_creator);
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    //////////////////////////////////////////
    /// Mint & setup on gated & public drop //
    //////////////////////////////////////////

    function mintBatchEditionGatedAndPublic(
        uint16 _editionSize,
        uint128 _publicStartDate,
        uint128 _publicBuyNowPrice,
        uint256 _merkleIndex,
        bytes32[] calldata _merkleProof,
        address _deployedRoyaltiesHandler,
        string calldata _uri
    ) canMintAgain(_msgSender()) external {
        require(accessControls.isVerifiedArtist(_merkleIndex, _msgSender(), _merkleProof), "Caller must have minter role");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _msgSender(), _uri);

        // Setup public sale
        _setupSalesMechanic(editionId, SaleType.BUY_NOW, _publicStartDate, _publicBuyNowPrice, 0);

        // Created gated sale
        gatedMarketplace.createSale(editionId);

        _recordSuccessfulMint(_msgSender());
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    function mintBatchEditionGatedAndPublicAsProxy(
        address _creator,
        uint16 _editionSize,
        uint128 _publicStartDate,
        uint128 _publicBuyNowPrice,
        address _deployedRoyaltiesHandler,
        string calldata _uri
    ) canMintAgain(_creator) external {
        require(accessControls.isVerifiedArtistProxy(_creator, _msgSender()), "Caller is not artist proxy");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _creator, _uri);

        // Setup public sale
        _setupSalesMechanic(editionId, SaleType.BUY_NOW, _publicStartDate, _publicBuyNowPrice, 0);

        // Created gated sale
        gatedMarketplace.createSale(editionId);

        _recordSuccessfulMint(_creator);
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);
    }

    ////////////////
    /// Mint only //
    ////////////////

    function mintBatchEditionOnly(
        uint16 _editionSize,
        uint256 _merkleIndex,
        bytes32[] calldata _merkleProof,
        address _deployedRoyaltiesHandler,
        string calldata _uri
    ) canMintAgain(_msgSender()) external {
        require(accessControls.isVerifiedArtist(_merkleIndex, _msgSender(), _merkleProof), "Caller must have minter role");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _msgSender(), _uri);

        _recordSuccessfulMint(_msgSender());
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);

        emit EditionMinted(editionId);
    }

    function mintBatchEditionOnlyAsProxy(
        address _creator,
        uint16 _editionSize,
        address _deployedRoyaltiesHandler,
        string calldata _uri
    ) canMintAgain(_creator) external {
        require(accessControls.isVerifiedArtistProxy(_creator, _msgSender()), "Caller is not artist proxy");

        // Make tokens & edition
        uint256 editionId = koda.mintBatchEdition(_editionSize, _creator, _uri);

        _recordSuccessfulMint(_creator);
        _setupRoyalties(editionId, _deployedRoyaltiesHandler);

        emit EditionMinted(editionId);
    }

    ///////////////////////
    /// Internal helpers //
    ///////////////////////

    function _setupSalesMechanic(uint256 _editionId, SaleType _saleType, uint128 _startDate, uint128 _basePrice, uint128 _stepPrice) internal {
        if (SaleType.BUY_NOW == _saleType) {
            marketplace.listForBuyNow(_msgSender(), _editionId, _basePrice, _startDate);
        }
        else if (SaleType.STEPPED == _saleType) {
            marketplace.listSteppedEditionAuction(_msgSender(), _editionId, _basePrice, _stepPrice, _startDate);
        }
        else if (SaleType.OFFERS == _saleType) {
            marketplace.enableEditionOffers(_editionId, _startDate);
        }
        else if (SaleType.RESERVE == _saleType) {
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
