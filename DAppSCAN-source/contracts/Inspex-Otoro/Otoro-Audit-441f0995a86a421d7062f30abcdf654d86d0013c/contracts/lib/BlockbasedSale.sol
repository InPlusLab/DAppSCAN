// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./Roles.sol";

contract BlockbasedSale is Ownable, Roles {
    using SafeMath for uint256;

    event AssignDutchAuction(bool flag);
    event AssignDutchAuctionCap(uint256 cap);
    event AssignPrivateSaleCap(uint256 cap);
    event AssignPriceDecayParameter(
        uint256 size,
        uint256 _lowerBoundPrice,
        uint256 _priceFactor
    );
    event AssignTransactionLimit(uint256 _dutchAuction, uint256 _freeMarket);
    event AssignPrivateSaleConfig(uint256 beginBlock, uint256 endBlock);
    event AssignPublicSaleConfig(uint256 beginBlock, uint256 endBlock);
    event AssignDutchAuctionConfig(uint256 beginBlock, uint256 endBlock);
    event AssignPrivateSalePrice(uint256 price);
    event AssignPublicSalePrice(uint256 price);
    event AssignReserveLimit(uint256 limit);
    event AssignPrivateSapeCap(uint256 cap);
    event EnablePublicSale();
    event EnablePrivateSale();
    event EnableFairDutchAuction();
    event ForceCloseSale();
    event ForcePauseSale();
    event ResetOverridedSaleState();
    event OverrideFinalDAPrice(uint256 price);

    enum SaleState {
        NotStarted,
        DutchAuctionBeforeWithoutBlock,
        DutchAuctionBeforeWithBlock,
        DutchAuctionDuring,
        DutchAuctionEnd,
        DutchAuctionEndSoldOut,
        PrivateSaleBeforeWithoutBlock,
        PrivateSaleBeforeWithBlock,
        PrivateSaleDuring,
        PrivateSaleEnd,
        PrivateSaleEndSoldOut,
        PublicSaleBeforeWithoutBlock,
        PublicSaleBeforeWithBlock,
        PublicSaleDuring,
        PublicSaleEnd,
        PublicSaleEndSoldOut,
        PauseSale,
        AllSalesEnd
    }

    enum SalePhase {
        None,
        DutchAuction,
        Private,
        Public
    }

    enum OverrideSaleState {
        None,
        Pause,
        Close
    }

    struct SalesBlock {
        uint256 beginBlock;
        uint256 endBlock;
    }

    struct DutchAuctionConfig {
        uint256 discountBlockSize;
        uint256 lowerBoundPrice;
        uint256 priceFactor;
    }

    struct SaleStats {
        uint256 totalReserveMinted;
        uint256 totalDAMinted;
        uint256 totalOGMinted;
        uint256 totalWLMinted;
        uint256 totalFMMinted;
    }

    struct SaleConfig {
        uint256 maxDAMintPerWallet;
        uint256 maxFMMintPerTx;
    }

    SalesBlock public dutchAuction;
    SalesBlock public privateSale;
    SalesBlock public publicSale;

    OverrideSaleState public overridedSaleState = OverrideSaleState.None;
    SalePhase public salePhase = SalePhase.None;

    DutchAuctionConfig public dutchAuctionConfig;
    SaleStats public saleStats;
    SaleConfig public saleConfig;

    uint256 public maxSupply;
    uint256 public maxReserve;
    uint256 public privateSalePriceCapped = 500000000000000000;
    uint256 public publicSaleBeginPrice;
    uint256 public finalDAPrice;
    uint256 public privateSaleCapped;
    uint256 public dutchAuctionCapped;

    function setDutchAuctionBlocks(SalesBlock memory _dutchAuction)
        external
        onlyOperator
    {
        dutchAuction = _dutchAuction;
        emit AssignDutchAuctionConfig(
            _dutchAuction.beginBlock,
            _dutchAuction.endBlock
        );
    }

    function setPrivateSaleBlocks(SalesBlock memory _privateSale)
        external
        onlyOperator
    {
        privateSale = _privateSale;
        emit AssignPrivateSaleConfig(
            _privateSale.beginBlock,
            _privateSale.endBlock
        );
    }

    function setPublicSaleBlocks(SalesBlock memory _publicSale)
        external
        onlyOperator
    {
        publicSale = _publicSale;
        emit AssignPublicSaleConfig(
            _publicSale.beginBlock,
            _publicSale.endBlock
        );
    }

    function setOverrideFinalDAPrice(uint256 price) external onlyOperator {
        finalDAPrice = price;
        emit OverrideFinalDAPrice(price);
    }

    function setDutchAuctionParam(
        uint256 size,
        uint256 lowerBoundPrice,
        uint256 factor
    ) external onlyOperator {
        dutchAuctionConfig.discountBlockSize = size;
        dutchAuctionConfig.lowerBoundPrice = lowerBoundPrice;
        dutchAuctionConfig.priceFactor = factor;
        emit AssignPriceDecayParameter(size, lowerBoundPrice, factor);
    }

    function setTransactionLimit(uint256 _dutchAuction, uint256 _freeMarket)
        external
        onlyOperator
    {
        saleConfig.maxDAMintPerWallet = _dutchAuction;
        saleConfig.maxFMMintPerTx = _freeMarket;
        emit AssignTransactionLimit(_dutchAuction, _freeMarket);
    }

    function setPublicSalePrice(uint256 _price) external onlyOperator {
        publicSaleBeginPrice = _price;
        emit AssignPublicSalePrice(_price);
    }

    function setPrivateSaleCapPrice(uint256 _price) external onlyOperator {
        privateSalePriceCapped = _price;
        emit AssignPrivateSalePrice(_price);
    }

    function setCloseSale() external onlyOperator {
        overridedSaleState = OverrideSaleState.Close;
        emit ForceCloseSale();
    }

    function setPauseSale() external onlyOperator {
        overridedSaleState = OverrideSaleState.Pause;
        emit ForcePauseSale();
    }

    function resetOverridedSaleState() external onlyOperator {
        overridedSaleState = OverrideSaleState.None;
        emit ResetOverridedSaleState();
    }

    function setReserve(uint256 reserve) external onlyOperator {
        maxReserve = reserve;
        emit AssignReserveLimit(reserve);
    }

    function setDutchAuctionCap(uint256 cap) external onlyOperator {
        dutchAuctionCapped = cap;
        emit AssignDutchAuctionCap(cap);
    }

    function setPrivateSaleCap(uint256 cap) external onlyOperator {
        privateSaleCapped = cap;
        emit AssignPrivateSaleCap(cap);
    }

    function enableDutchAuction() external onlyOperator {
        salePhase = SalePhase.DutchAuction;
        emit EnableFairDutchAuction();
    }

    function enablePublicSale() external onlyOperator {
        salePhase = SalePhase.Public;
        emit EnablePublicSale();
    }

    function enablePrivateSale() external onlyOperator {
        salePhase = SalePhase.Private;
        emit EnablePrivateSale();
    }

    function getStartSaleBlock() external view returns (uint256) {
        if (salePhase == SalePhase.DutchAuction) {
            return dutchAuction.beginBlock;
        }

        if (salePhase == SalePhase.Private) {
            return privateSale.beginBlock;
        }

        if (salePhase == SalePhase.Public) {
            return publicSale.beginBlock;
        }

        return 0;
    }

    function getEndSaleBlock() external view returns (uint256) {
        if (salePhase == SalePhase.DutchAuction) {
            return dutchAuction.endBlock;
        }

        if (salePhase == SalePhase.Private) {
            return privateSale.endBlock;
        }

        if (salePhase == SalePhase.Public) {
            return publicSale.endBlock;
        }

        return 0;
    }

    function availableReserve() public view returns (uint256) {
        return maxReserve - saleStats.totalReserveMinted;
    }

    function getMaxSupplyByMode() external view returns (uint256) {
        SaleState state = getState();
        if (state == SaleState.DutchAuctionDuring)
            return dutchAuctionCapped;
        if (state == SaleState.PrivateSaleDuring) return privateSaleCapped;
        if (state == SaleState.PublicSaleDuring)
            return
                maxSupply -
                saleStats.totalOGMinted -
                saleStats.totalWLMinted -
                maxReserve -
                saleStats.totalDAMinted;
        return 0;
    }

    function getMintedByMode() external view returns (uint256) {
        SaleState state = getState();
        if (state == SaleState.PrivateSaleDuring)
            return saleStats.totalOGMinted + saleStats.totalWLMinted;
        if (state == SaleState.PublicSaleDuring)
            return saleStats.totalFMMinted;
        if (state == SaleState.DutchAuctionDuring)
            return saleStats.totalDAMinted;
        return 0;
    }

    function getTransactionCappedByMode() external view returns (uint256) {
        if (getState() == SaleState.DutchAuctionDuring)
            return saleConfig.maxDAMintPerWallet;
        if (getState() == SaleState.PublicSaleDuring)
            return saleConfig.maxFMMintPerTx;
        return 2;
    }

    function getPriceByMode() public view returns (uint256) {
        SaleState state = getState();
        if (state == SaleState.DutchAuctionDuring) {
            uint256 passedBlock = block.number - dutchAuction.beginBlock;
            uint256 discountPrice = passedBlock
                .div(dutchAuctionConfig.discountBlockSize)
                .mul(dutchAuctionConfig.priceFactor);

            if (
                discountPrice >=
                publicSaleBeginPrice.sub(dutchAuctionConfig.lowerBoundPrice)
            ) {
                return dutchAuctionConfig.lowerBoundPrice;
            } else {
                return publicSaleBeginPrice.sub(discountPrice);
            }
        }

        if (state == SaleState.PrivateSaleDuring) {
            uint256 halfFinalPrice = finalDAPrice.div(2);
            return
                (halfFinalPrice < privateSalePriceCapped)
                    ? privateSalePriceCapped
                    : halfFinalPrice;
        }

        if (state == SaleState.PublicSaleDuring) {
            return finalDAPrice;
        }

        return publicSaleBeginPrice;
    }

    function totalPrivateSaleMinted() public view returns (uint256) {
        return saleStats.totalWLMinted + saleStats.totalOGMinted;
    }

    function isPrivateSaleSoldOut() public view returns (bool) {
        return totalPrivateSaleMinted() == privateSaleCapped;
    }

    function isDASoldOut() public view returns (bool) {
        return dutchAuctionCapped == saleStats.totalDAMinted;
    }

    function isSoldOut() public view returns (bool) {
        uint256 supplyWithoutReserve = maxSupply - maxReserve;
        uint256 mintedWithoutReserve = saleStats.totalDAMinted +
            saleStats.totalFMMinted +
            saleStats.totalOGMinted + 
            saleStats.totalWLMinted;
        return supplyWithoutReserve == mintedWithoutReserve;
    }

    function getStateName() public view returns (string memory) {
        SaleState state = getState();
        if (state == SaleState.DutchAuctionBeforeWithoutBlock)
            return "DutchAuctionBeforeWithoutBlock";
        if (state == SaleState.DutchAuctionBeforeWithBlock)
            return "DutchAuctionBeforeWithBlock";
        if (state == SaleState.DutchAuctionDuring) return "DutchAuctionDuring";
        if (state == SaleState.DutchAuctionEnd) return "DutchAuctionEnd";
        if (state == SaleState.DutchAuctionEndSoldOut)
            return "DutchAuctionEndSoldOut";
        if (state == SaleState.PrivateSaleBeforeWithoutBlock)
            return "PrivateSaleBeforeWithoutBlock";
        if (state == SaleState.PrivateSaleBeforeWithBlock)
            return "PrivateSaleBeforeWithBlock";
        if (state == SaleState.PrivateSaleDuring) return "PrivateSaleDuring";
        if (state == SaleState.PrivateSaleEnd) return "PrivateSaleEnd";
        if (state == SaleState.PrivateSaleEndSoldOut)
            return "PrivateSaleEndSoldOut";
        if (state == SaleState.PublicSaleBeforeWithoutBlock)
            return "PublicSaleBeforeWithoutBlock";
        if (state == SaleState.PublicSaleBeforeWithBlock)
            return "PublicSaleBeforeWithBlock";
        if (state == SaleState.PublicSaleDuring) return "PublicSaleDuring";
        if (state == SaleState.PublicSaleEnd) return "PublicSaleEnd";
        if (state == SaleState.PublicSaleEndSoldOut)
            return "PublicSaleEndSoldOut";
        if (state == SaleState.PauseSale) return "PauseSale";
        if (state == SaleState.AllSalesEnd) return "AllSalesEnd";

        return "NotStarted";
    }

    function getState() public view returns (SaleState) {
        if (overridedSaleState == OverrideSaleState.Close) {
            return SaleState.AllSalesEnd;
        }

        if (overridedSaleState == OverrideSaleState.Pause) {
            return SaleState.PauseSale;
        }

        if (salePhase == SalePhase.None) {
            return SaleState.NotStarted;
        }

        /******* Public Sale Phase Determination  *******/

        if (salePhase == SalePhase.Public) {
            if (isSoldOut()) {
                return SaleState.PublicSaleEndSoldOut;
            }

            if (publicSale.endBlock > 0 && block.number > publicSale.endBlock) {
                return SaleState.PublicSaleEnd;
            }

            if (
                publicSale.beginBlock > 0 &&
                block.number >= publicSale.beginBlock
            ) {
                return SaleState.PublicSaleDuring;
            }

            if (
                publicSale.beginBlock > 0 &&
                block.number < publicSale.beginBlock &&
                block.number > privateSale.endBlock
            ) {
                return SaleState.PublicSaleBeforeWithBlock;
            }

            if (
                publicSale.beginBlock == 0 &&
                block.number > privateSale.endBlock
            ) {
                return SaleState.PublicSaleBeforeWithoutBlock;
            }
        }
        /******* Private Sale Phase Determination  *******/
        if (salePhase == SalePhase.Private) {
            if (isPrivateSaleSoldOut()) {
                return SaleState.PrivateSaleEndSoldOut;
            }

            if (
                privateSale.endBlock > 0 && block.number > privateSale.endBlock
            ) {
                return SaleState.PrivateSaleEnd;
            }

            if (
                privateSale.beginBlock > 0 &&
                block.number >= privateSale.beginBlock
            ) {
                return SaleState.PrivateSaleDuring;
            }

            if (
                privateSale.beginBlock > 0 &&
                block.number < privateSale.beginBlock
            ) {
                return SaleState.PrivateSaleBeforeWithBlock;
            }

            if (privateSale.beginBlock == 0) {
                return SaleState.PrivateSaleBeforeWithoutBlock;
            }
        }
        /******* Dutch Auction Phase Determination  *******/
        if (salePhase == SalePhase.DutchAuction) {
            if (isDASoldOut()) {
                return SaleState.DutchAuctionEndSoldOut;
            }

            if (
                dutchAuction.endBlock > 0 &&
                block.number > dutchAuction.endBlock
            ) {
                return SaleState.DutchAuctionEnd;
            }

            if (
                dutchAuction.beginBlock > 0 &&
                block.number >= dutchAuction.beginBlock
            ) {
                return SaleState.DutchAuctionDuring;
            }

            if (
                dutchAuction.beginBlock > 0 &&
                block.number < dutchAuction.beginBlock
            ) {
                return SaleState.DutchAuctionBeforeWithBlock;
            }

            if (dutchAuction.beginBlock == 0) {
                return SaleState.DutchAuctionBeforeWithoutBlock;
            }
        }

        return SaleState.NotStarted;
    }
}
