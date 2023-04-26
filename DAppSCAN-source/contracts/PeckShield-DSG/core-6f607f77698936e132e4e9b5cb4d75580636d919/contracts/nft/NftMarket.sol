// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../libraries/LibPart.sol";
import "../libraries/TransferHelper.sol";
import "../interfaces/IWOKT.sol";
import "../governance/InitializableOwner.sol";

interface Royalties {
    event RoyaltiesSet(uint256 tokenId, LibPart.Part[] royalties);

    function getRoyalties(uint256 id) external view returns (LibPart.Part[] memory);
}

contract NFTMarket is Context, IERC721Receiver, ReentrancyGuard, InitializableOwner {

    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct SalesObject {
        uint256 id;
        uint256 tokenId;
        uint256 startTime;
        uint256 durationTime;
        uint256 maxPrice;
        uint256 minPrice;
        uint256 finalPrice;
        uint8 status;
        address payable seller;
        address payable buyer;
        IERC721 nft;
    }

    event eveSales(
        uint256 indexed id, 
        uint256 indexed tokenId,
        address buyer, 
        address currency,
        uint256 finalPrice, 
        uint256 tipsFee,
        uint256 royaltiesAmount,
        uint256 timestamp
    );

    event eveNewSales(
        uint256 indexed id,
        uint256 indexed tokenId, 
        address seller, 
        address nft,
        address buyer, 
        address currency,
        uint256 startTime,
        uint256 durationTime,
        uint256 maxPrice, 
        uint256 minPrice,
        uint256 finalPrice
    );
    event eveCancelSales(
        uint256 indexed id,
        uint256 tokenId
    );
    event eveNFTReceived(address operator, address from, uint256 tokenId, bytes data);
    event GovernanceTransferred(address indexed previousOwner, address indexed newOwner);
    event eveSupportCurrency(
        address currency, 
        bool support
    );

    uint256 public _salesAmount = 0;

    SalesObject[] _salesObjects;

    uint256 public _minDurationTime = 5 minutes;
    
    address public WETH;

    mapping(address => bool) public _seller;
    mapping(address => bool) public _verifySeller;
    mapping(address => bool) public _supportNft;
    bool public _isStartUserSales;

    uint256 public _tipsFeeRate = 20;
    uint256 public _baseRate = 1000;
    address payable _tipsFeeWallet;
    mapping(address => bool) private _disabledRoyalties;

    mapping(uint256 => address) public _saleOnCurrency;
    mapping(address => bool) public _supportCurrency;
    
    constructor() public {

    }

    function initialize(address payable tipsFeeWallet, address weth) public {
        super._initialize();

        _tipsFeeRate = 50;
        _baseRate = 1000;
        _minDurationTime = 5 minutes;
        _tipsFeeWallet = tipsFeeWallet;
        WETH = weth;

        addSupportCurrency(TransferHelper.getETH());
    }

    /**
     * check address
     */
    modifier validAddress( address addr ) {
        require(addr != address(0));
        _;
    }

    modifier checkindex(uint index) {
        require(index < _salesObjects.length, "overflow");
        _;
    }

    modifier checkTime(uint index) {
        require(index < _salesObjects.length, "overflow");
        SalesObject storage obj = _salesObjects[index];
        require(obj.startTime <= block.timestamp, "!open");
        _;
    }

    modifier mustNotSellingOut(uint index) {
        require(index < _salesObjects.length, "overflow");
        SalesObject storage obj = _salesObjects[index];
        require(obj.buyer == address(0) && obj.status == 0, "sry, selling out");
        _;
    }

    modifier onlySalesOwner(uint index) {
        require(index < _salesObjects.length, "overflow");
        SalesObject storage obj = _salesObjects[index];
        require(obj.seller == msg.sender || msg.sender == owner(), "author & owner");
        _;
    }

    function seize(IERC20 asset) external returns (uint256 balance) {
        balance = asset.balanceOf(address(this));
        asset.safeTransfer(owner(), balance);
    }

    function updateDisabledRoyalties(address nft, bool val) public onlyOwner {
        _disabledRoyalties[nft] = val;
    }

    function addSupportNft(address nft) public onlyOwner validAddress(nft) {
        _supportNft[nft] = true;
    }

    function removeSupportNft(address nft) public onlyOwner validAddress(nft) {
        _supportNft[nft] = false;
    }

    function addSeller(address seller) public onlyOwner validAddress(seller) {
        _seller[seller] = true;
    }

    function removeSeller(address seller) public onlyOwner validAddress(seller) {
        _seller[seller] = false;
    }
    
    function addSupportCurrency(address erc20) public onlyOwner {
        require(_supportCurrency[erc20] == false, "the currency have support");
        _supportCurrency[erc20] = true;
        emit eveSupportCurrency(erc20, true);
    }

    function removeSupportCurrency(address erc20) public onlyOwner {
        require(_supportCurrency[erc20], "the currency can not remove");
        _supportCurrency[erc20] = false;
        emit eveSupportCurrency(erc20, false);
    }

    function addVerifySeller(address seller) public onlyOwner validAddress(seller) {
        _verifySeller[seller] = true;
    }

    function removeVerifySeller(address seller) public onlyOwner validAddress(seller) {
        _verifySeller[seller] = false;
    }

    function setIsStartUserSales(bool isStartUserSales) public onlyOwner {
        _isStartUserSales = isStartUserSales;
    }

    function setMinDurationTime(uint256 durationTime) public onlyOwner {
        _minDurationTime = durationTime;
    }

    function setTipsFeeWallet(address payable wallet) public onlyOwner {
        _tipsFeeWallet = wallet;
    }

    function getTipsFeeWallet() public view returns(address) {
        return address(_tipsFeeWallet);
    }

    function getSalesEndTime(uint index) 
        external
        view
        checkindex(index)
        returns (uint256) 
    {
        SalesObject storage obj = _salesObjects[index];
        return obj.startTime.add(obj.durationTime);
    }

    function getSales(uint index) external view checkindex(index) returns(SalesObject memory) {
        return _salesObjects[index];
    }
    
    function getSalesCurrency(uint index) public view returns(address) {
        return _saleOnCurrency[index];
    }

    function getSalesPrice(uint index)
        external
        view
        checkindex(index)
        returns (uint256)
    {
        SalesObject storage obj = _salesObjects[index];
        if(obj.buyer != address(0) || obj.status == 1) {
            return obj.finalPrice;
        } else {
            if(obj.startTime.add(obj.durationTime) < block.timestamp) {
                return obj.minPrice;
            } else if (obj.startTime >= block.timestamp) {
                return obj.maxPrice;
            } else {
                uint256 per = obj.maxPrice.sub(obj.minPrice).div(obj.durationTime);
                return obj.maxPrice.sub(block.timestamp.sub(obj.startTime).mul(per));
            }
        }
    }

    function setBaseRate(uint256 rate) external onlyOwner {
        _baseRate = rate;
    }

    function setTipsFeeRate(uint256 rate) external onlyOwner {
        _tipsFeeRate = rate;
    }

    function isVerifySeller(uint index) public view checkindex(index) returns(bool) {
        SalesObject storage obj = _salesObjects[index];
        return _verifySeller[obj.seller];
    }

    function cancelSales(uint index) external checkindex(index) onlySalesOwner(index) mustNotSellingOut(index) nonReentrant {
        SalesObject storage obj = _salesObjects[index];
        obj.status = 2;
        obj.nft.safeTransferFrom(address(this), obj.seller, obj.tokenId);

        emit eveCancelSales(index, obj.tokenId);
    }

    function startSales(uint256 tokenId,
                        uint256 maxPrice, 
                        uint256 minPrice,
                        uint256 startTime, 
                        uint256 durationTime,
                        address nft,
                        address currency)
        external 
        nonReentrant
        validAddress(nft)
        returns(uint)
    {
        require(tokenId != 0, "invalid token");
        require(startTime.add(durationTime) > block.timestamp, "invalid start time");
        require(durationTime >= _minDurationTime, "invalid duration");
        require(maxPrice >= minPrice, "invalid price");
        require(_isStartUserSales || _seller[msg.sender] == true || _supportNft[nft] == true, "cannot sales");
        require(_supportCurrency[currency] == true, "not support currency");

        IERC721(nft).safeTransferFrom(msg.sender, address(this), tokenId);

        _salesAmount++;
        SalesObject memory obj;

        obj.id = _salesAmount;
        obj.tokenId = tokenId;
        obj.seller = payable(msg.sender);
        obj.nft = IERC721(nft);
        obj.startTime = startTime;
        obj.durationTime = durationTime;
        obj.maxPrice = maxPrice;
        obj.minPrice = minPrice;
        
        _saleOnCurrency[obj.id] = currency;
        
        if (_salesObjects.length == 0) {
            SalesObject memory zeroObj;
            zeroObj.status = 2;
            _salesObjects.push(zeroObj);    
        }

        _salesObjects.push(obj);
        
        uint256 tmpMaxPrice = maxPrice;
        uint256 tmpMinPrice = minPrice;
        emit eveNewSales(obj.id, tokenId, msg.sender, nft, address(0x0), currency, startTime, durationTime, tmpMaxPrice, tmpMinPrice, 0);
        return _salesAmount;
    }

    function buy(uint index)
        public
        nonReentrant
        mustNotSellingOut(index)
        checkTime(index)
        payable 
    {
        SalesObject storage obj = _salesObjects[index];
        require(obj.status == 0, "bad status");
        
        uint256 price = this.getSalesPrice(index);
        obj.status = 1;

        uint256 tipsFee = price.mul(_tipsFeeRate).div(_baseRate);
        uint256 purchase = price.sub(tipsFee);

        address currencyAddr = _saleOnCurrency[obj.id];
        if (currencyAddr == address(0)) {
            currencyAddr = TransferHelper.getETH();
        }

        uint256 royaltiesAmount;
        if(obj.nft.supportsInterface(bytes4(keccak256('getRoyalties(uint256)')))
            && _disabledRoyalties[address(obj.nft)] == false) {

            LibPart.Part[] memory fees = Royalties(address(obj.nft)).getRoyalties(obj.tokenId);
            for(uint i = 0; i < fees.length; i++) {
                uint256 feeValue = price.mul(fees[i].value).div(10000);
                if (purchase > feeValue) {
                    purchase = purchase.sub(feeValue);
                } else {
                    feeValue = purchase;
                    purchase = 0;
                }
                if (feeValue != 0) {
                    royaltiesAmount = royaltiesAmount.add(feeValue);
                    if(TransferHelper.isETH(currencyAddr)) {
                        TransferHelper.safeTransferETH(fees[i].account, feeValue);
                    } else {
                        IERC20(currencyAddr).safeTransferFrom(msg.sender, fees[i].account, feeValue);
                    }
                }
            }
        }

        if (TransferHelper.isETH(currencyAddr)) {
            require (msg.value >= this.getSalesPrice(index), "your price is too low");
            uint256 returnBack = msg.value.sub(price);
            if(returnBack > 0) {
                payable(msg.sender).transfer(returnBack);
            }
            if(tipsFee > 0) {
                IWOKT(WETH).deposit{value: tipsFee}();
                IWOKT(WETH).transfer(_tipsFeeWallet, tipsFee);
            }
            obj.seller.transfer(purchase);
        } else {
            IERC20(currencyAddr).safeTransferFrom(msg.sender, _tipsFeeWallet, tipsFee);
            IERC20(currencyAddr).safeTransferFrom(msg.sender, obj.seller, purchase);
        }

        obj.nft.safeTransferFrom(address(this), msg.sender, obj.tokenId);
        
        obj.buyer = payable(msg.sender);
        obj.finalPrice = price;

        // fire event
        emit eveSales(index, obj.tokenId, msg.sender, currencyAddr, price, tipsFee, royaltiesAmount, block.timestamp);
    }

    function onERC721Received(address operator, address from, uint256 tokenId, bytes memory data) public override returns (bytes4) {
        //only receive the _nft staff
        if(address(this) != operator) {
            //invalid from nft
            return 0;
        }

        //success
        emit eveNFTReceived(operator, from, tokenId, data);
        return bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"));
    }

    // fallback() external payable {
    //     revert();
    // }
}