// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./oz/util/ECDSA.sol";
import "./oz/erc20/IERC20.sol";
import "./oz/erc721/IERC721.sol";
import "./zAuctionAccountant.sol";

contract zAuction {
    using ECDSA for bytes32;

    bool initialized;
    zAuctionAccountant accountant;
    IERC20 weth = IERC20(address(0xc778417E063141139Fce010982780140Aa0cD5Ab)); // rinkeby weth

    mapping(uint256 => bool) public randUsed;

    event BidAccepted(address indexed bidder, address indexed seller, uint256 amount, address nftaddress, uint256 tokenid);
    event WethBidAccepted(address indexed bidder, address indexed seller, uint256 amount, address nftaddress, uint256 tokenid);

    function init(address accountantaddress) external {
        require(!initialized);
        initialized = true;
        accountant = zAuctionAccountant(accountantaddress);
    }

    /// recovers bidder's signature based on seller's proposed data and, if bid data hash matches the message hash, transfers nft and payment
    /// @param signature type encoded message signed by the bidder
    /// @param rand a global random nonce stored to invalidate attempts to repeat
    /// @param bidder address of who the seller says the bidder is, for confirmation of the recovered bidder
    /// @param bid eth amount bid
    /// @param nftaddress contract address of the nft we are transferring
    /// @param tokenid token id we are transferring
    function acceptBid(bytes memory signature, uint256 rand, address bidder, uint256 bid, address nftaddress, uint256 tokenid) external {
        address recoveredbidder = recover(toEthSignedMessageHash(keccak256(abi.encode(rand, address(this), block.chainid, bid, nftaddress, tokenid))), signature);
        require(bidder == recoveredbidder, 'zAuction: incorrect bidder');
        require(!randUsed[rand], 'Random nonce already used');
        randUsed[rand] = true;
        IERC721 nftcontract = IERC721(nftaddress);
        accountant.Exchange(bidder, msg.sender, bid);
        nftcontract.transferFrom(msg.sender, bidder, tokenid);
        emit BidAccepted(bidder, msg.sender, bid, nftaddress, tokenid);
    }
    
    /// @dev 'true' in the hash here is the eth/weth switch
    function acceptWethBid(bytes memory signature, uint256 rand, address bidder, uint256 bid, address nftaddress, uint256 tokenid) external {
        address recoveredbidder = recover(toEthSignedMessageHash(keccak256(abi.encode(rand, address(this), block.chainid, bid, nftaddress, tokenid, true))), signature);
        require(bidder == recoveredbidder, 'zAuction: incorrect bidder');
        require(!randUsed[rand], 'Random nonce already used');
        randUsed[rand] = true;
        IERC721 nftcontract = IERC721(nftaddress);
        weth.transferFrom(bidder, msg.sender, bid);
        nftcontract.transferFrom(msg.sender, bidder, tokenid);
        emit WethBidAccepted(bidder, msg.sender, bid, nftaddress, tokenid);
    }
    
    function recover(bytes32 hash, bytes memory signature) public pure returns (address) {
        return hash.recover(signature);
    }

    function toEthSignedMessageHash(bytes32 hash) public pure returns (bytes32) {
        return hash.toEthSignedMessageHash();
    }
}