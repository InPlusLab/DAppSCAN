pragma solidity 0.8.5;
//SPDX-License-Identifier: MIT

import "@openzeppelin/contracts/access/Ownable.sol";
import "./BlocksRewardsManager.sol";

contract BlocksSpace is Ownable {
    struct Block {
        uint256 price;
        address owner;
    }

    struct BlockView {
        uint256 price;
        address owner;
        uint16 blockNumber;
    }

    struct BlocksArea {
        address owner;
        uint256 blockstart;
        uint256 blockend;
        string imghash;
        uint256 zindex;
    }

    struct BlockAreaLocation {
        uint256 startBlockX;
        uint256 startBlockY;
        uint256 endBlockX;
        uint256 endBlockY;
    }

    struct UserState {
        BlocksArea lastBlocksAreaBought;
        uint256 lastPurchase;
    }

    uint256 constant PRICE_OF_LOGO_BLOCKS = 42 ether;
    BlocksRewardsManager public rewardsPool;
    uint256 public minTimeBetweenPurchases = 42 hours;
    mapping(uint256 => Block) public blocks;
    mapping(address => UserState) public users;
    
    event MinTimeBetweenPurchasesUpdated(uint256 inSeconds);
    event BlocksAreaPurchased(address indexed blocksAreaOwner, uint256 blocksBought, uint256 paid);

    constructor(address rewardsPoolContract_) {
        rewardsPool = BlocksRewardsManager(rewardsPoolContract_);
        setPriceOfLogoBlocks(0, 301);
    }

    function setPriceOfLogoBlocks(uint256 startBlockId_, uint256 endBlockId_) internal {
        // 0 - 301
        (uint256 startBlockX, uint256 startBlockY) = (startBlockId_ / 100, startBlockId_ % 100);
        (uint256 endBlockX, uint256 endBlockY) = (endBlockId_ / 100, endBlockId_ % 100);
        for (uint256 i = startBlockX; i <= endBlockX; ++i) {
            for (uint256 j = startBlockY; j <= endBlockY; ++j) {
                Block storage currentBlock = blocks[i * 100 + j];
                currentBlock.price = PRICE_OF_LOGO_BLOCKS;
                currentBlock.owner = msg.sender;
            }
        }
    }

    function purchaseBlocksArea(
        uint256 startBlockId_,
        uint256 endBlockId_,
        string calldata imghash_
    ) external payable {
        BlockAreaLocation memory areaLoc = BlockAreaLocation(
            startBlockId_ / 100,
            startBlockId_ % 100,
            endBlockId_ / 100,
            endBlockId_ % 100
        );

        // 1. Checks
        uint256 paymentReceived = msg.value;
        require(paymentReceived > 0, "Money expected...");
        require(
            block.timestamp >= users[msg.sender].lastPurchase + minTimeBetweenPurchases,
            "You must wait between buys"
        );
        require(isBlocksAreaValid(areaLoc), "BlocksArea invalid");
        require(bytes(imghash_).length != 0, "Image hash cannot be empty");

        (uint256 currentPriceOfBlocksArea, uint256 numberOfBlocks) = calculatePriceAndSize(areaLoc);

        // Price increase per block needs to be at least minimal
        require(paymentReceived > currentPriceOfBlocksArea, "Price increase too small");
        uint256 priceIncreasePerBlock_ = (paymentReceived - currentPriceOfBlocksArea) / numberOfBlocks;
        require(priceIncreasePerBlock_ > 0, "Price incr per block too small");

        // 2. Storage operations
        (address[] memory previousBlockOwners, uint256[] memory previousOwnersPrices) = calculateBlocksOwnershipChanges(
            areaLoc,
            priceIncreasePerBlock_,
            numberOfBlocks
        );
        updateUserState(msg.sender, startBlockId_, endBlockId_, imghash_);

        // 3. Transactions
        // Send fresh info to RewardsPool contract, so buyer gets some sweet rewards
        rewardsPool.blocksAreaBoughtOnSpace{value: paymentReceived}(
            msg.sender,
            previousBlockOwners,
            previousOwnersPrices
        );

        // 4. Emit purchase event
        emit BlocksAreaPurchased(msg.sender, startBlockId_ * 10000 + endBlockId_, paymentReceived);
    }

    function calculateBlocksOwnershipChanges(
        BlockAreaLocation memory areaLoc,
        uint256 priceIncreasePerBlock_,
        uint256 numberOfBlocks_
    ) internal returns (address[] memory, uint256[] memory) {
        // Go through all blocks that were paid for
        address[] memory previousBlockOwners = new address[](numberOfBlocks_);
        uint256[] memory previousOwnersPrices = new uint256[](numberOfBlocks_);
        uint256 arrayIndex;
        for (uint256 i = areaLoc.startBlockX; i <= areaLoc.endBlockX; ++i) {
            for (uint256 j = areaLoc.startBlockY; j <= areaLoc.endBlockY; ++j) {
                //Set new state of the Block
                Block storage currentBlock = blocks[i * 100 + j];
                previousBlockOwners[arrayIndex] = currentBlock.owner;
                previousOwnersPrices[arrayIndex] = currentBlock.price;
                currentBlock.price = currentBlock.price + priceIncreasePerBlock_; // Set new price that was paid for this block
                currentBlock.owner = msg.sender; // Set new owner of block
                ++arrayIndex;
            }
        }
        return (previousBlockOwners, previousOwnersPrices);
    }

    function updateUserState(
        address user_,
        uint256 startBlockId_,
        uint256 endBlockId_,
        string calldata imghash_
    ) internal {
        UserState storage userState = users[user_];
        userState.lastBlocksAreaBought.owner = user_;
        userState.lastBlocksAreaBought.blockstart = startBlockId_;
        userState.lastBlocksAreaBought.blockend = endBlockId_;
        userState.lastBlocksAreaBought.imghash = imghash_;
        userState.lastBlocksAreaBought.zindex = block.number;
        userState.lastPurchase = block.timestamp;
    }

    function getPricesOfBlocks(uint256 startBlockId_, uint256 endBlockId_) external view returns (BlockView[] memory) {
        BlockAreaLocation memory areaLoc = BlockAreaLocation(
            startBlockId_ / 100,
            startBlockId_ % 100,
            endBlockId_ / 100,
            endBlockId_ % 100
        );

        require(isBlocksAreaValid(areaLoc), "BlocksArea invalid");

        BlockView[42] memory blockAreaTemp;
        uint256 arrayCounter;
        for (uint256 i = areaLoc.startBlockX; i <= areaLoc.endBlockX; ++i) {
            for (uint256 j = areaLoc.startBlockY; j <= areaLoc.endBlockY; ++j) {
                uint16 index = uint16(i * 100 + j);
                Block storage currentBlock = blocks[index];
                blockAreaTemp[arrayCounter] = BlockView(
                    currentBlock.price,
                    currentBlock.owner,
                    index // block number
                );
                ++arrayCounter;
            }
        }

        // Shrink array and return only whats filled
        BlockView[] memory blockArea = new BlockView[](arrayCounter);
        for (uint256 i; i < arrayCounter; ++i) {
            blockArea[i] = blockAreaTemp[i];
        }
        return blockArea;
    }

    function calculatePriceAndSize(BlockAreaLocation memory areaLoc) internal view returns (uint256, uint256) {
        uint256 currentPrice;
        uint256 numberOfBlocks;
        for (uint256 i = areaLoc.startBlockX; i <= areaLoc.endBlockX; ++i) {
            for (uint256 j = areaLoc.startBlockY; j <= areaLoc.endBlockY; ++j) {
                currentPrice = currentPrice + blocks[i * 100 + j].price;
                ++numberOfBlocks;
            }
        }
        return (currentPrice, numberOfBlocks);
    }

    function isBlocksAreaValid(BlockAreaLocation memory areaLoc) internal pure returns (bool) {
        require(areaLoc.startBlockX < 42 && areaLoc.endBlockX < 42, "X blocks out of range. Oh Why?");
        require(areaLoc.startBlockY < 24 && areaLoc.endBlockY < 24, "Y blocks out of range. Oh Why?");

        uint256 blockWidth = areaLoc.endBlockX - areaLoc.startBlockX + 1; // +1 because its including
        uint256 blockHeight = areaLoc.endBlockY - areaLoc.startBlockY + 1; // +1 because its including
        uint256 blockArea = blockWidth * blockHeight;

        return blockWidth <= 7 && blockHeight <= 7 && blockArea <= 42;
    }

    function updateMinTimeBetweenPurchases(uint256 inSeconds_) external onlyOwner {
        minTimeBetweenPurchases = inSeconds_;
        emit MinTimeBetweenPurchasesUpdated(inSeconds_);
    }
}