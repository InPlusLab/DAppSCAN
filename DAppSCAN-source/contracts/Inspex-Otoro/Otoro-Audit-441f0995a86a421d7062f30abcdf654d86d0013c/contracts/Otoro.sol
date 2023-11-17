// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
// SWC-102-Outdated Compiler Version: L2

import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./lib/BlockbasedSale.sol";
import "./lib/Roles.sol";
import "./lib/Revealable.sol";
import "./lib/RequestSigning.sol";

contract Otoro is
    Ownable,
    ERC721,
    ERC721Enumerable,
    ReentrancyGuard,
    Roles,
    Revealable,
    BlockbasedSale,
    RequestSigning
{
    using Address for address;
    using SafeMath for uint256;

    event Airdrop(address[] addresses, uint256 amount);
    event Purchased(address indexed account, uint256 indexed index);
    event WithdrawNonPurchaseFund(uint256 balance);

    mapping(address => uint256) private _dutchAuctionMinted;
    mapping(address => uint256) private _privateSaleClaimed;
    mapping(address => uint256) private _ogClaimed;
    PaymentSplitter private _splitter;

    struct ChainLinkParams {
        address coordinator;
        address linkToken;
        bytes32 keyHash;
    }

    struct RevenueShareParams {
        address[] payees;
        uint256[] shares;
    }

    struct MintInfo {
        uint128 price;
        uint8 amount;
    }

    mapping(address => MintInfo[]) public fairDAInfo;

    modifier shareHolderOnly() {
        require(
            _splitter.shares(msg.sender) > 0 || owner() == _msgSender(),
            "not shareholder/owner"
        );
        _;
    }

    constructor(
        string memory _tokenName,
        string memory _symbol,
        uint256 _maxSupply,
        uint256 _startPrice,
        string memory _defaultURI,
        ChainLinkParams memory chainLinkParams,
        RevenueShareParams memory revenueShare
    )
        ERC721(_tokenName, _symbol)
        Revealable(
            _defaultURI,
            chainLinkParams.coordinator,
            chainLinkParams.linkToken,
            chainLinkParams.keyHash
        )
        RequestSigning(_symbol)
    {
        _splitter = new PaymentSplitter(
            revenueShare.payees,
            revenueShare.shares
        );
        maxSupply = _maxSupply;
        publicSaleBeginPrice = _startPrice;
        finalDAPrice = _startPrice;
    }

    function airdrop(address[] memory addresses, uint256 amount)
        external
        nonReentrant
        onlyOperator
    {
        require(
            totalSupply().add(addresses.length.mul(amount)) <= maxSupply,
            "Exceed max supply limit."
        );

        require(
            saleStats.totalReserveMinted.add(addresses.length.mul(amount)) <=
                maxReserve,
            "Insufficient reserve."
        );

        saleStats.totalReserveMinted = saleStats.totalReserveMinted.add(
            addresses.length.mul(amount)
        );

        for (uint256 i = 0; i < addresses.length; i++) {
            _mintToken(addresses[i], amount);
        }
        emit Airdrop(addresses, amount);
    }

    function mintOg(bytes calldata signature)
        external
        payable
        nonReentrant
        returns (bool)
    {
        require(msg.sender == tx.origin, "Contract is not allowed.");
        require(
            getState() == SaleState.PrivateSaleDuring,
            "Sale not available."
        );

        if (getState() == SaleState.PrivateSaleDuring) {
            require(isOG(signature), "Not OG whitelisted.");
            require(_ogClaimed[msg.sender] == 0, "Already Claimed OG.");
            require(
                totalPrivateSaleMinted().add(1) <= privateSaleCapped,
                "Exceed Private Sale Limit"
            );

            require(msg.value >= getPriceByMode(), "Insufficient funds.");

            _ogClaimed[msg.sender] = _ogClaimed[msg.sender] + 1;
            saleStats.totalOGMinted = saleStats.totalOGMinted.add(1);

            _mintToken(msg.sender, 1);

            payable(_splitter).transfer(msg.value);

            return true;
        }

        return false;
    }

    function mintToken(uint256 amount, bytes calldata signature)
        external
        payable
        nonReentrant
        returns (bool)
    {
        SaleState state = getState();
        require(msg.sender == tx.origin, "Contract is not allowed.");
        require(
            state == SaleState.PrivateSaleDuring ||
                state == SaleState.PublicSaleDuring ||
                state == SaleState.DutchAuctionDuring,
            "Sale not available."
        );
        require(
            msg.value >= amount.mul(getPriceByMode()),
            "Insufficient funds."
        );

        if (state == SaleState.DutchAuctionDuring) {
            require(
                amount <= saleConfig.maxDAMintPerWallet,
                "Mint exceed transaction limits."
            );
            require(
                _dutchAuctionMinted[msg.sender] + amount <=
                    saleConfig.maxDAMintPerWallet,
                "Mint limit per wallet exceeded."
            );
            require(
                saleStats.totalDAMinted.add(amount) <= dutchAuctionCapped,
                "Purchase exceed limit."
            );
        }

        if (state == SaleState.PublicSaleDuring) {
            require(
                amount <= saleConfig.maxFMMintPerTx,
                "Mint exceed transaction limits."
            );
            require(
                totalSupply().add(amount).add(availableReserve()) <= maxSupply,
                "Purchase exceed max supply."
            );
        }

        if (state == SaleState.PrivateSaleDuring) {
            require(isWhiteListed(signature), "Not whitelisted.");
            require(amount <= 2, "Mint exceed transaction limits");
            require(
                _privateSaleClaimed[msg.sender] + amount <= 2,
                "Mint limit per wallet exceeded."
            );
            require(
                totalPrivateSaleMinted().add(amount) <= privateSaleCapped,
                "Purchase exceed sale capped."
            );
        }

        if (
            state == SaleState.PrivateSaleDuring ||
            state == SaleState.PublicSaleDuring ||
            state == SaleState.DutchAuctionDuring
        ) {
            _mintToken(msg.sender, amount);
            if (state == SaleState.DutchAuctionDuring) {
                saleStats.totalDAMinted = saleStats.totalDAMinted.add(amount);
                
                uint256 mintPrice =  msg.value.div(amount);

                fairDAInfo[msg.sender].push(
                    MintInfo(uint128(mintPrice), uint8(amount))
                );
                
                if (mintPrice < finalDAPrice) {
                    finalDAPrice = mintPrice;
                }
                
                _dutchAuctionMinted[msg.sender] =
                    _dutchAuctionMinted[msg.sender] +
                    amount;
            }
            if (state == SaleState.PublicSaleDuring) {
                saleStats.totalFMMinted = saleStats.totalFMMinted.add(amount);
            }
            if (state == SaleState.PrivateSaleDuring) {
                _privateSaleClaimed[msg.sender] =
                    _privateSaleClaimed[msg.sender] +
                    amount;
                saleStats.totalWLMinted = saleStats.totalWLMinted.add(amount);
            }
            payable(_splitter).transfer(msg.value);
        }

        return true;
    }

    function dutchAuctionInfo(address user)
        public
        view
        returns (MintInfo[] memory)
    {
        return fairDAInfo[user];
    }

    function _mintToken(address addr, uint256 amount) internal returns (bool) {
        for (uint256 i = 0; i < amount; i++) {
            uint256 tokenIndex = totalSupply();
            if (tokenIndex < maxSupply) {
                _safeMint(addr, tokenIndex + 1);
                emit Purchased(addr, tokenIndex);
            }
        }
        return true;
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        require(tokenId <= totalSupply(), "Token not exist.");

        return
            isRevealed()
                ? string(
                    abi.encodePacked(
                        revealedBaseURI,
                        getShuffledId(totalSupply(), maxSupply, tokenId, 1),
                        ".json"
                    )
                )
                : defaultURI;
    }

    function release(address payable account) external virtual shareHolderOnly {
        require(
            msg.sender == account || msg.sender == owner(),
            "Release: no permission"
        );

        _splitter.release(account);
    }

    function withdraw() external onlyOperator {
        uint256 balance = address(this).balance;
        payable(msg.sender).transfer(balance);
        emit WithdrawNonPurchaseFund(balance);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override(ERC721, ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC721, ERC721Enumerable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
