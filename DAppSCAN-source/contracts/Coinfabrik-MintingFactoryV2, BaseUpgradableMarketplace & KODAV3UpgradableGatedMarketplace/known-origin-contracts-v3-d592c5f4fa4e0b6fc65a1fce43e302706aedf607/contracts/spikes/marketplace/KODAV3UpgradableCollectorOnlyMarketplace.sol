// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {BaseUpgradableMarketplace} from "../../marketplace/BaseUpgradableMarketplace.sol";
import {IKOAccessControlsLookup} from "../../access/IKOAccessControlsLookup.sol";
import {IKODAV3} from "../../core/IKODAV3.sol";

// TODO consider off-chain path for this as well
// TODO add interfaces to IKODAV3Marketplace

contract KODAV3UpgradableCollectorOnlyMarketplace is BaseUpgradableMarketplace {

    /// @notice emitted when a sale is created
    event SaleCreated(uint256 indexed saleId, uint256 indexed editionId);
    /// @notice emitted when someone mints from a sale
    event MintFromSale(uint256 indexed saleId, uint256 indexed editionId, address account, uint256 mintCount);
    /// @notice emitted when primary sales commission is updated for a sale
    event AdminUpdatePlatformPrimarySaleCommissionGatedSale(uint256 indexed saleId, uint256 platformPrimarySaleCommission);
    /// @notice emitted when a sale is paused
    event SalePaused(uint256 indexed saleId, uint256 indexed editionId);
    /// @notice emitted when a sale is resumed
    event SaleResumed(uint256 indexed saleId, uint256 indexed editionId);

    /// @dev incremental counter for the ID of a sale
    uint256 private saleIdCounter;

    struct Sale {
        uint256 id; // The ID of the sale
        address creator; // The creator of the sale
        uint256 editionId; // The ID of the edition the sale will mint
        uint128 startTime; // The start time of the sale
        uint128 endTime; // The end time of the sale
        uint16 mintLimit; // The mint limit per wallet for the sale
        uint128 priceInWei; // Price in wei for one mint
        bool paused; // Whether the sale is currently paused
    }

    /// @dev sales is a mapping of sale id => Sale
    mapping(uint256 => Sale) public sales;
    /// @dev editionToSale is a mapping of edition id => sale id
    mapping(uint256 => uint256) public editionToSale;
    /// @dev totalMints is a mapping of sale id => tokenId => total minted by that address
    mapping(uint256 => mapping(uint256 => uint)) public totalMints;
    /// @dev saleCommission is a mapping of sale id => commission %, if 0 its default 15_00000 (15%)
    mapping(uint256 => uint256) public saleCommission;

    function createSale(uint256 _editionId, uint128 _startTime, uint128 _endTime, uint16 _mintLimit, uint128 _priceInWei)
    public
    whenNotPaused
    onlyCreatorContractOrAdmin(_editionId)
    {
        uint256 editionSize = koda.getSizeOfEdition(_editionId);
        require(editionSize > 0, 'edition does not exist');
        require(_endTime > _startTime, 'sale end time must be after start time');
        require(_mintLimit > 0 && _mintLimit < editionSize, 'mint limit must be greater than 0 and smaller than edition size');

        uint256 saleId = saleIdCounter += 1;

        // Assign the sale to the sales and editionToSale mappings
        sales[saleId] = Sale({
        id : saleId,
        creator : koda.getCreatorOfEdition(_editionId),
        editionId : _editionId,
        startTime : _startTime,
        endTime : _endTime,
        mintLimit : _mintLimit,
        priceInWei : _priceInWei,
        paused : false
        });
        editionToSale[_editionId] = saleId;

        emit SaleCreated(saleId, _editionId);
    }

    function mint(uint256 _saleId, uint256 _tokenId, uint16 _mintCount)
    payable
    public
    nonReentrant
    whenNotPaused
    {
        Sale memory sale = sales[_saleId];

        require(!sale.paused, 'sale is paused');
        require(canMint(_saleId, _tokenId, _msgSender(), sale.creator), 'address unable to mint from sale');
        require(!koda.isEditionSoldOut(sale.editionId), 'the sale is sold out');
        require(block.timestamp >= sale.startTime && block.timestamp < sale.endTime, 'sale not in progress');
        require(totalMints[_saleId][_tokenId] + _mintCount <= sale.mintLimit, 'cannot exceed total mints for sale');
        require(msg.value >= sale.priceInWei * _mintCount, 'not enough wei sent to complete mint');

        // Up the mint count for the user
        totalMints[_saleId][_tokenId] += _mintCount;

        _handleMint(_saleId, sale.editionId, _mintCount);

        emit MintFromSale(_saleId, sale.editionId, _msgSender(), _mintCount);
    }

    function _handleMint(uint256 _saleId, uint256 _editionId, uint16 _mintCount) internal {
        address _receiver;

        for (uint i = 0; i < _mintCount; i++) {
            (address receiver, address creator, uint256 tokenId) = koda.facilitateNextPrimarySale(_editionId);
            _receiver = receiver;

            // send token to buyer (assumes approval has been made, if not then this will fail)
            koda.safeTransferFrom(creator, _msgSender(), tokenId);
        }

        _handleEditionSaleFunds(_saleId, _editionId, _receiver);
    }

    function canMint(uint256 _saleId, uint256 _tokenId, address _account, address _creator) public view returns (bool) {
        require(sales[_saleId].creator == _creator, 'sale id does not match creator address');

        if (koda.ownerOf(_tokenId) != _account) {
            return false;
        }

        if (koda.getCreatorOfToken(_tokenId) != _creator) {
            return false;
        }

        return true;
    }

    function remainingMintAllowance(uint256 _saleId, uint256 _tokenId, address _account, address _creator) public view returns (uint256) {
        require(canMint(_saleId, _tokenId, _account, _creator), 'address not able to mint from sale');

        return sales[_saleId].mintLimit - totalMints[_saleId][_tokenId];
    }

    function toggleSalePause(uint256 _saleId, uint256 _editionId) public onlyCreatorContractOrAdmin(_editionId) {
        if (sales[_saleId].paused) {
            sales[_saleId].paused = false;
            emit SaleResumed(_saleId, _editionId);
        } else {
            sales[_saleId].paused = true;
            emit SalePaused(_saleId, _editionId);
        }
    }

    function _handleEditionSaleFunds(uint256 _saleId, uint256 _editionId, address _receiver) internal {
        uint256 platformPrimarySaleCommission = saleCommission[_saleId] > 0 ? saleCommission[_saleId] : 15_00000;
        uint256 koCommission = (msg.value / modulo) * platformPrimarySaleCommission;
        if (koCommission > 0) {
            (bool koCommissionSuccess,) = platformAccount.call{value : koCommission}("");
            require(koCommissionSuccess, "commission payment failed");
        }

        (bool success,) = _receiver.call{value : msg.value - koCommission}("");
        require(success, "payment failed");
    }

    function updatePlatformPrimarySaleCommission(uint256 _saleId, uint256 _platformPrimarySaleCommission) public onlyAdmin {
        saleCommission[_saleId] = _platformPrimarySaleCommission;

        emit AdminUpdatePlatformPrimarySaleCommissionGatedSale(_saleId, _platformPrimarySaleCommission);
    }
}
