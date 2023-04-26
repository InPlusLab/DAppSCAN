//SPDX-License-Identifier: Unlicense
/*
░██████╗██████╗░███████╗███████╗██████╗░░░░░░░░██████╗████████╗░█████╗░██████╗░
██╔════╝██╔══██╗██╔════╝██╔════╝██╔══██╗░░░░░░██╔════╝╚══██╔══╝██╔══██╗██╔══██╗
╚█████╗░██████╔╝█████╗░░█████╗░░██║░░██║█████╗╚█████╗░░░░██║░░░███████║██████╔╝
░╚═══██╗██╔═══╝░██╔══╝░░██╔══╝░░██║░░██║╚════╝░╚═══██╗░░░██║░░░██╔══██║██╔══██╗
██████╔╝██║░░░░░███████╗███████╗██████╔╝░░░░░░██████╔╝░░░██║░░░██║░░██║██║░░██║
╚═════╝░╚═╝░░░░░╚══════╝╚══════╝╚═════╝░░░░░░░╚═════╝░░░░╚═╝░░░╚═╝░░╚═╝╚═╝░░╚═╝
*/
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract Shop is Ownable {
    using SafeMath for uint256;
    using SafeCast for int256;
    using SafeERC20 for ERC20;

    event BuyPack(uint16 packId, uint256 price, address buyer);
    event SetSaleOpen(bool isOpen);
    event SetPackPrice(uint16 packId, uint256 price);
    event SetPackAvaliable(uint16 packId, uint256 amount);
    event BuyPackAmount(address user, uint16 packId, uint256 amount);
    event UpdatePriceFeed(address user,address feed);
    event ClaimToken(address user,uint256 amount);

    // 100,300,900,1800
    mapping(uint16 => uint256) private packPriceDollar;
    // 3965,5884,567,234
    mapping(uint16 => uint256) public packAvaliable;
    AggregatorV3Interface internal onePriceFeed;

    bool private openSale;

    constructor() {
        onePriceFeed = AggregatorV3Interface(
            0xdCD81FbbD6c4572A69a534D8b8152c562dA8AbEF
        );
    }

    function setPriceFeed(address _address) external onlyOwner {
        require(!openSale, "Unable to set during sale");
        onePriceFeed = AggregatorV3Interface(_address);

        emit UpdatePriceFeed(msg.sender, _address);
    }

    function setPackPrice(uint16 _packId, uint256 _price) external onlyOwner {
        require(!openSale, "Unable to set during sale");
        packPriceDollar[_packId] = _price;
        emit SetPackPrice(_packId, _price);
    }

    function setPackAvaliable(uint16 _packId, uint256 _amount)
        external
        onlyOwner
    {
        require(!openSale, "Unable to set during sale");
        packAvaliable[_packId] = _amount;
        emit SetPackAvaliable(_packId, _amount);
    }

    function setOpenSale(bool _openSale) external onlyOwner {
        openSale = _openSale;
        emit SetSaleOpen(_openSale);
    }

    function getONERate() public view returns (uint256) {
        (, int256 price, , , ) = onePriceFeed.latestRoundData();
        return uint256(price);
    }

    function getPackPrice(uint16 _packId) public view returns (uint256) {
        uint256 rate = getONERate();
        require(rate != 0, "Not found rate for swap.");

        uint256 payAmountPerDollar = uint256(
            (1000000000000000000 / uint256(rate))
        ).mul(100000000);
        return packPriceDollar[_packId].mul(payAmountPerDollar);
    }

    function buyPack(uint16 _packId) public payable {
        require(openSale, "Not open sale");
        require(packPriceDollar[_packId] > 0, "Price not set");
        require(packAvaliable[_packId] > 0, "Not avaliable");
        uint256 rate = getONERate();
        require(rate != 0, "Not found rate for swap.");

        uint256 payAmount = getPackPrice(_packId);
        require(msg.value >= payAmount, "pay amount mismatch");

        packAvaliable[_packId] = packAvaliable[_packId].sub(1);
        // each 100 stable to selled the price is increase to 10$
        if (_packId == 0) {
            if (packAvaliable[_packId] % (100) == 0) {
                packPriceDollar[_packId] = packPriceDollar[_packId].add(10);
            }
        }
        emit BuyPack(_packId, payAmount, msg.sender);
    }

    function buyPackAmount(uint16 _packId, uint16 _amount) external payable {
        require(_amount <= 6, "Over limit amount");
        require(packAvaliable[_packId] > 0, "Not avaliable");
        require(packAvaliable[_packId] >= _amount, "pack not enougth");

        require(
            msg.value >= getPackPrice(_packId).mul(_amount),
            "one not enougth."
        );

        for (uint256 index = 0; index < _amount; index++) {
            buyPack(_packId);
        }

        emit BuyPackAmount(msg.sender, _packId, _amount);
    }

    function claimToken() external onlyOwner {
        uint256 totalBalance = address(this).balance;
        (bool sent, ) = msg.sender.call{value: totalBalance}("");
        require(sent, "Failed to send Ether");

        emit ClaimToken(msg.sender, totalBalance);
    }
}
