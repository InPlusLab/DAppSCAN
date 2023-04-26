// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "../governance/InitializableOwner.sol";
import "../interfaces/IDsgNft.sol";
import "../interfaces/IFragmentToken.sol";
import "../libraries/Random.sol";


contract MysteryBox is ERC721, InitializableOwner {

    struct BoxFactory {
        uint256 id;
        string name;
        IDsgNft nft;
        uint256 limit; //0 unlimit
        uint256 minted;
        address currency;
        uint256 price;
        string resPrefix; // default res prefix
        address author;
        uint256 createdTime;
    }

    struct BoxView {
        uint256 id;
        uint256 factoryId;
        string name;
        address nft;
        uint256 limit; //0 unlimit
        uint256 minted;
        address author;
    }

    struct ResInfo {
        string name;
        string prefix; //If the resNumBegin = resNumEnd, resName will be resPrefix
        uint numBegin;
        uint numEnd;
    }

    event NewBoxFactory(
        uint256 indexed id,
        string name,
        address nft,
        uint256 limit,
        address author,
        address currency,
        uint256 price,
        uint256 createdTime
    );

    event OpenBox(uint256 indexed id, address indexed nft, uint256 boxId, uint256 tokenId);
    event Minted(uint256 indexed id, uint256 indexed factoryId, address to);

    uint256 private _boxFactoriesId = 0;
    uint256 private _boxId = 1e3;

    string private _baseURIVar;

    mapping(uint256 => uint256) private _boxes; // boxId: BoxFactoryId
    mapping(uint256 => BoxFactory) private _boxFactories; // factoryId: BoxFactory
    mapping(uint256 => mapping(uint256 => ResInfo)) private _res; // factoryId: {level: ResInfo}

    uint256[] private _levelBasePower = [1000, 2500, 6500, 14500, 35000, 90000];

    string private _name;
    string private _symbol;

    constructor() public ERC721("", "") {
    }

    function initialize(string memory uri) public {
        super._initialize();

        _levelBasePower = [1000, 2500, 6500, 14500, 35000, 90000];
        _boxId = 1e3;

        _baseURIVar = uri;

        _name = "DsgMysteryBox";
        _symbol = "DsgBox";
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function setBaseURI(string memory uri) public onlyOwner {
        _baseURIVar = uri;
    }

    function baseURI() public view override returns (string memory) {
        return _baseURIVar;
    }

    function addBoxFactory(
        string memory name_,
        IDsgNft nft,
        uint256 limit,
        address author,
        address currency,
        uint256 price,
        string memory resPrefix
    ) public onlyOwner returns (uint256) {
        _boxFactoriesId++;

        BoxFactory memory box;
        box.id = _boxFactoriesId;
        box.name = name_;
        box.nft = nft;
        box.limit = limit;
        box.author = author;
        box.currency = currency;
        box.price = price;
        box.resPrefix  = resPrefix;
        box.createdTime = block.timestamp;

        _boxFactories[_boxFactoriesId] = box;

        emit NewBoxFactory(
            _boxFactoriesId,
            name_,
            address(nft),
            limit,
            author,
            currency,
            price,
            block.timestamp
        );
        return _boxFactoriesId;
    }

    function setRes(
        uint256 factoryId, 
        uint256 level, 
        string memory nftName, 
        string memory prefix, 
        uint numBegin, 
        uint numEnd
    ) public onlyOwner {
        ResInfo storage res = _res[factoryId][level];
        res.name = nftName;
        res.prefix = prefix;
        res.numBegin = numBegin;
        res.numEnd = numEnd;
    }

    function getRes(uint256 factoryId, uint256 level) public view returns (ResInfo memory) {
        return _res[factoryId][level];
    }

    function mint(address to, uint256 factoryId, uint256 amount) public onlyOwner {
        BoxFactory storage box = _boxFactories[factoryId];
        require(address(box.nft) != address(0), "box not found");
        
        if(box.limit > 0) {
            require(box.limit.sub(box.minted) >= amount, "Over the limit");
        }
        box.minted = box.minted.add(amount);

        for(uint i = 0; i < amount; i++) {
            _boxId++;
            _mint(to, _boxId);
            _boxes[_boxId] = factoryId;
            emit Minted(_boxId, factoryId, to);
        }
    }

    function buy(uint256 factoryId, uint256 amount) public {
        BoxFactory storage box = _boxFactories[factoryId];
        require(address(box.nft) != address(0), "box not found");

        if(box.limit > 0) {
            require(box.limit.sub(box.minted) >= amount, "Over the limit");
        }
        box.minted = box.minted.add(amount);

        uint256 price = box.price.mul(amount);
        require(IFragmentToken(box.currency).transferFrom(msg.sender, address(this), price), "transfer error");
        IFragmentToken(box.currency).burn(price);

        for(uint i = 0; i < amount; i++) {
            _boxId++;
            _mint(msg.sender, _boxId);
            _boxes[_boxId] = factoryId;
            emit Minted(_boxId, factoryId, msg.sender);
        }
    }

    function burn(uint256 tokenId) public {
        address owner = ERC721.ownerOf(tokenId);
        require(_msgSender() == owner, "caller is not the box owner");

        delete _boxes[tokenId];
        _burn(tokenId);
    }

    function getFactory(uint256 factoryId) public view
    returns (BoxFactory memory)
    {
        return _boxFactories[factoryId];
    }

    function getBox(uint256 boxId)
    public
    view
    returns (BoxView memory)
    {
        uint256 factoryId = _boxes[boxId];
        BoxFactory memory factory = _boxFactories[factoryId];

        return BoxView({
            id: boxId,
            factoryId: factoryId,
            name: factory.name,
            nft: address(factory.nft),
            limit: factory.limit,
            minted: factory.minted,
            author: factory.author
        });
    }

    // 81.92 12.23 3.5 1.5 0.6 0.25
    function getLevel(uint256 seed) internal pure returns(uint256) {
        uint256 val = seed / 8897 % 10000;
        if(val <= 8192) {
            return 1;
        } else if (val < 9415) {
            return 2;
        } else if (val < 9765) {
            return 3;
        } else if (val < 9915) {
            return 4;
        } else if (val < 9975) {
            return 5;
        }
        return 6;
    }

    function randomPower(uint256 level, uint256 seed ) internal view returns(uint256) {
        if (level == 1) {
            return _levelBasePower[0] + seed % 200;
        } else if (level == 2) {
            return _levelBasePower[1] + seed % 500;
        } else if (level == 3) {
            return _levelBasePower[2] + seed % 500;
        } else if (level == 4) {
            return _levelBasePower[3] + seed % 500;
        } else if (level == 5) {
            return _levelBasePower[4] + seed % 5000;
        }

        return _levelBasePower[5] + seed % 10000;
    }

    function randomRes(uint256 seed, uint256 level, BoxFactory memory factory) 
    internal view returns(string memory resName, string memory nftName) {
        string memory prefix = factory.resPrefix;
        uint numBegin = 1;
        uint numEnd = 1;

        {
            ResInfo storage res = _res[factory.id][level];
            if (bytes(res.prefix).length > 0) {
                prefix = res.prefix;
                numBegin = res.numBegin;
                numEnd = res.numEnd;
                nftName = res.name;
            }
        }

        uint256 num = uint256(numEnd.sub(numBegin));
        
        num = (seed / 3211 % (num+1)).add(uint256(numBegin));
        resName = string(abi.encodePacked(prefix, num.toString()));
    }

    function openBox(uint256 boxId) public {
        require(isContract(msg.sender) == false && tx.origin == msg.sender, "Prohibit contract calls");

        uint256 factoryId = _boxes[boxId];
        BoxFactory memory factory = _boxFactories[factoryId];
        burn(boxId);

        uint256 seed = Random.computerSeed();

        uint256 level = getLevel(seed);
        uint256 power = randomPower(level, seed);
        
        (string memory resName, string memory nftName) = randomRes(seed, level, factory);

        uint256 tokenId = factory.nft.mint(_msgSender(), nftName, level, power, resName, factory.author);

        emit OpenBox(boxId, address(factory.nft), boxId, tokenId);
    }

    function isContract(address addr) internal view returns (bool) {
        uint size;
        assembly { size := extcodesize(addr) }
        return size > 0;
    }
}
