pragma solidity ^0.8.0;
// SPDX-License-Identifier: (CC-BY-NC-ND-3.0)
// Code and docs are CC-BY-NC-ND-3.0

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import {Base64} from "./libraries/Base64.sol";

contract Vouchers is ERC721Enumerable, Ownable, Pausable, ReentrancyGuard {
    using Strings for uint256;

    address public mintingToken = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;

    event NewDropCreated(bytes32 drop, bytes32 root);

    struct DropInfo {
        uint16 totalNumber;
        uint16 soldNum;
        uint16 maxAllowed;
    }

    struct Drop {
        bytes32 root;
        uint256 price;
        uint16 minPurchase;
        uint16 maxPurchase;
        bool started;
        DropInfo goalkeepers;
        DropInfo defenders;
        DropInfo midfielders;
        DropInfo attackers;
    }

    mapping(address => mapping(bytes32 => mapping(string => uint16)))
        public buysPerDrop;
    mapping(bytes32 => Drop) public drops;
    mapping(uint256 => string) public voucherTypes;
    mapping(string => string) private imageURLs;
    mapping(string => string) private animationURLs;
    string private externalUrl = 'https://metasoccer.com/';

    string private constant GOALKEEPER = "Goalkeeper";
    string private constant DEFENDER = "Defender";
    string private constant MIDFIELDER = "Midfielder";
    string private constant ATTACKER = "Forward";
    string private constant ERROR_WRONG_QTY = "ERROR_WRONG_QTY";

    // Keep count of burned tickets to avoid potential issues with minting and type tracking
    uint256 public burnedCount;

    constructor() ERC721("MetaSoccer Youth Scout Tickets", "MSYST") {}

    function pause(bool stop) external onlyOwner {
        if (stop) {
            _pause();
        } else {
            _unpause();
        }
    }

    function setDrop(bytes32 drop, Drop memory _drop) external onlyOwner {
        drops[drop] = _drop;
        emit NewDropCreated(drop, _drop.root);
    }

    function buyVouchers(
        bytes32 drop,
        bytes32[] calldata proof,
        uint16 qtyGKs,
        uint16 qtyDFs,
        uint16 qtyMFs,
        uint16 qtyAKs
    ) external nonReentrant {
        require(!paused(), "buy while paused");
        require(drops[drop].started, "drop not started");
        require(drops[drop].root != keccak256("0"), "drop does not exist");

        // Check for whitelist
        if (drops[drop].root != "") {
            require(
                _verify(_leaf(msg.sender), proof, drop),
                "Invalid merkle proof"
            );
        }

        // Vouchers should be available at drop level
        require(
            drops[drop].goalkeepers.soldNum + qtyGKs <=
                drops[drop].goalkeepers.totalNumber,
            ERROR_WRONG_QTY
        );
        require(
            drops[drop].defenders.soldNum + qtyDFs <=
                drops[drop].defenders.totalNumber,
            ERROR_WRONG_QTY
        );
        require(
            drops[drop].midfielders.soldNum + qtyMFs <=
                drops[drop].midfielders.totalNumber,
            ERROR_WRONG_QTY
        );
        require(
            drops[drop].attackers.soldNum + qtyAKs <=
                drops[drop].attackers.totalNumber,
            ERROR_WRONG_QTY
        );

        // Should buy more than minimum required by drop and less than total allowed per type
        uint16 totalQty = qtyGKs + qtyDFs + qtyMFs + qtyAKs;
        uint16 previousQty = buysPerDrop[msg.sender][drop][GOALKEEPER] +
            buysPerDrop[msg.sender][drop][DEFENDER] +
            buysPerDrop[msg.sender][drop][MIDFIELDER] +
            buysPerDrop[msg.sender][drop][ATTACKER];
        require(
            totalQty + previousQty >= drops[drop].minPurchase,
            ERROR_WRONG_QTY
        );
        require(
            totalQty + previousQty <= drops[drop].maxPurchase,
            ERROR_WRONG_QTY
        );

        // Should buy less than total allowed per type per drop
        require(
            qtyGKs + buysPerDrop[msg.sender][drop][GOALKEEPER] <=
                drops[drop].goalkeepers.maxAllowed,
            ERROR_WRONG_QTY
        );
        require(
            qtyDFs + buysPerDrop[msg.sender][drop][DEFENDER] <=
                drops[drop].defenders.maxAllowed,
            ERROR_WRONG_QTY
        );
        require(
            qtyMFs + buysPerDrop[msg.sender][drop][MIDFIELDER] <=
                drops[drop].midfielders.maxAllowed,
            ERROR_WRONG_QTY
        );
        require(
            qtyAKs + buysPerDrop[msg.sender][drop][ATTACKER] <=
                drops[drop].attackers.maxAllowed,
            ERROR_WRONG_QTY
        );

        uint256 amount = totalQty * drops[drop].price;
        require(
            IERC20(mintingToken).transferFrom(msg.sender, this.owner(), amount),
            "Unable to receive payment"
        );

        drops[drop].goalkeepers.soldNum =
            drops[drop].goalkeepers.soldNum +
            qtyGKs;
        drops[drop].defenders.soldNum = drops[drop].defenders.soldNum + qtyDFs;
        drops[drop].midfielders.soldNum =
            drops[drop].midfielders.soldNum +
            qtyMFs;
        drops[drop].attackers.soldNum = drops[drop].attackers.soldNum + qtyAKs;

        _mintForDrop(drop, GOALKEEPER, qtyGKs);
        _mintForDrop(drop, DEFENDER, qtyDFs);
        _mintForDrop(drop, MIDFIELDER, qtyMFs);
        _mintForDrop(drop, ATTACKER, qtyAKs);
    }

    function _mintForDrop(
        bytes32 _drop,
        string memory _type,
        uint16 _qty
    ) internal {
        for (uint256 i = 0; i < _qty; ++i) {
            voucherTypes[totalSupply() + burnedCount] = _type;
            ++buysPerDrop[msg.sender][_drop][_type];
            _safeMint(msg.sender, totalSupply() + burnedCount);
        }
    }

    function _leaf(address account) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(account));
    }

    function _verify(
        bytes32 leaf,
        bytes32[] memory proof,
        bytes32 drop
    ) internal view returns (bool) {
        return MerkleProof.verify(proof, drops[drop].root, leaf);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        virtual
        override
        returns (string memory)
    {
        require(_exists(tokenId), "nonexistent token");
        string memory voucherType = voucherTypes[tokenId];
        string memory json = Base64.encode(
            bytes(
                string(
                    abi.encodePacked(
                        '{"name": "',
                        voucherType, ' Ticket',
                        '","description": "',
                        'MetaSoccer Youth Scouts presale: tickets will be redeemable for actual Youth Scouts.',
                        '","external_url": "',
                        externalUrl,
                        '","image": "',
                        imageURLs[voucherType],
                        '","animation_url": "',
                        animationURLs[voucherType],
                        '","attributes": [{',
                            '"trait_type": "Covering",',
                            '"value": "',
                            voucherType,
                            '"}]',
                        '}'
                    )
                )
            )
        );

        string memory finalTokenUri = string(
            abi.encodePacked("data:application/json;base64,", json)
        );
        return finalTokenUri;
    }

    function toggleDropStarted(bytes32 _drop) external onlyOwner {
        drops[_drop].started = !drops[_drop].started;
    }

    function setDropWhitelist(bytes32 _drop, bytes32 _root) external onlyOwner {
        drops[_drop].root = _root;
    }

    function setMintingToken(address _new_minting_token) external onlyOwner {
        mintingToken = _new_minting_token;
    }

    function setExternalUrl(string memory _url) external onlyOwner {
        externalUrl = _url;
    }

    function setImageUrl(string memory _covering, string memory _url) external onlyOwner {
        imageURLs[_covering] = _url;
    }

    function setAnimationUrl(string memory _covering, string memory _url) external onlyOwner {
        animationURLs[_covering] = _url;
    }

    function mintForGiveaway(uint256 _num_to_mint, string memory _type) external onlyOwner {
        for (uint256 i = 0; i < _num_to_mint; ++i) {
            voucherTypes[totalSupply() + burnedCount] = _type;
            _safeMint(msg.sender, totalSupply() + burnedCount);
        }
    }

    function burnToken(uint256 _token_id) external {
        require(
            _isApprovedOrOwner(msg.sender, _token_id),
            "Sender is not owner nor approved"
        );
        burnedCount++;
        _burn(_token_id);
    }

    function getAllVouchers() external view returns (string[] memory) {
        string[] memory ret = new string[](totalSupply() + burnedCount);
        for (uint256 i = 0; i < totalSupply() + burnedCount; i++) {
            ret[i] = voucherTypes[i];
        }
        return ret;
    }

    function getAllOwned(address owner) external view returns (string[] memory) {
        string[] memory ret = new string[](balanceOf(owner));
        for (uint256 i = 0; i < balanceOf(owner); i++) {
            ret[i] = voucherTypes[tokenOfOwnerByIndex(owner, i)];
        }
        return ret;
    }

    function getDropsById(bytes32[] calldata dropIds)
        external
        view
        returns (Drop[] memory)
    {
        require(dropIds.length <= 50, "max amount of dropIds given");

        Drop[] memory d = new Drop[](dropIds.length);
        for (uint16 i = 0; i < dropIds.length; i++) {
            bytes32 id = dropIds[i];
            d[i] = drops[id];
        }
        return d;
    }
}
