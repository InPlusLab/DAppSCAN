// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/finance/PaymentSplitter.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./external/ERC721A.sol";

// @author rollauver.eth

contract Silks is ERC721A, Ownable, Pausable, PaymentSplitter {
  string public _baseTokenURI;

  bytes32 public _merkleRoot;

  uint256 public _price;
  uint256 public _presalePrice;
  uint256 public _maxSupply;
  uint256 public _maxPerAddress;
  uint256 public _presaleMaxPerAddress;
  uint256 public _publicSaleTime;
  uint256 public _preSaleTime;
  uint256 public _maxTxPerAddress;
  mapping(address => uint256) private _purchases;

  event EarlyPurchase(address indexed addr, uint256 indexed atPrice, uint256 indexed count);
  event Purchase(address indexed addr, uint256 indexed atPrice, uint256 indexed count);

  constructor(
    string memory name,
    string memory symbol,
    string memory baseTokenURI, // baseTokenURI - 0
    uint256[] memory numericValues, // price - 0, presalePrice - 1, maxSupply - 2, maxPerAddress - 3, presaleMaxPerAddress - 4, publicSaleTime - 5, _preSaleTime - 6, _maxTxPerAddress - 7
    bytes32 merkleRoot,
    address[] memory payees,
    uint256[] memory shares
  ) ERC721A(name, symbol, numericValues[2]) PaymentSplitter(payees, shares) {
    _baseTokenURI = baseTokenURI;

    _price = numericValues[0];
    _presalePrice = numericValues[1];
    _maxSupply = numericValues[2];
    _maxPerAddress = numericValues[3];
    _presaleMaxPerAddress = numericValues[4];
    _publicSaleTime = numericValues[5];
    _preSaleTime = numericValues[6];
    _maxTxPerAddress = numericValues[7];

    _merkleRoot = merkleRoot;
  }

  function setSaleInformation(
    uint256 publicSaleTime,
    uint256 preSaleTime,
    uint256 maxPerAddress,
    uint256 presaleMaxPerAddress,
    uint256 price,
    uint256 presalePrice,
    bytes32 merkleRoot,
    uint256 maxTxPerAddress
  ) external onlyOwner {
    _publicSaleTime = publicSaleTime;
    _preSaleTime = preSaleTime;
    _maxPerAddress = maxPerAddress;
    _presaleMaxPerAddress = presaleMaxPerAddress;
    _price = price;
    _presalePrice = presalePrice;
    _merkleRoot = merkleRoot;
    _maxTxPerAddress = maxTxPerAddress;
  }

  function setBaseUri(
    string memory baseUri
  ) external onlyOwner {
    _baseTokenURI = baseUri;
  }

  function setMerkleRoot(bytes32 merkleRoot) external onlyOwner {
    _merkleRoot = merkleRoot;
  }

  function _baseURI() override internal view virtual returns (string memory) {
    return string(
      abi.encodePacked(
        _baseTokenURI,
        Strings.toHexString(uint256(uint160(address(this))), 20),
        '/'
      )
    );
  }

  function mint(address to, uint256 count) external payable onlyOwner {
    ensureMintConditions(count);

    _safeMint(to, count);
  }

  function purchase(uint256 count) external payable whenNotPaused {
    ensurePublicMintConditions(msg.sender, count, _maxPerAddress);
    require(isPublicSaleActive(), "BASE_COLLECTION/CANNOT_MINT");

    _purchase(count, _price);
    emit Purchase(msg.sender, _price, count);
  }

  function earlyPurchase(uint256 count, bytes32[] calldata merkleProof) external payable whenNotPaused {
    ensurePublicMintConditions(msg.sender, count, _presaleMaxPerAddress);
    require(isPreSaleActive() && onEarlyPurchaseList(msg.sender, merkleProof), "BASE_COLLECTION/CANNOT_MINT_PRESALE");

    _purchase(count, _presalePrice);
    emit EarlyPurchase(msg.sender, _presalePrice, count);
  }

  function _purchase(uint256 count, uint256 price) private {
    require(price * count <= msg.value, 'BASE_COLLECTION/INSUFFICIENT_ETH_AMOUNT');

    _purchases[msg.sender] += count;
    _safeMint(msg.sender, count);
  }

  function ensureMintConditions(uint256 count) internal view {
    require(totalSupply() + count <= _maxSupply, "BASE_COLLECTION/EXCEEDS_MAX_SUPPLY");
  }

  function ensurePublicMintConditions(address to, uint256 count, uint256 maxPerAddress) internal view {
    ensureMintConditions(count);

    require((_maxTxPerAddress == 0) || (count <= _maxTxPerAddress), "BASE_COLLECTION/EXCEEDS_MAX_PER_TRANSACTION");
    uint256 totalMintFromAddress = _purchases[to] + count;
    require ((maxPerAddress == 0) || (totalMintFromAddress <= maxPerAddress), "BASE_COLLECTION/EXCEEDS_INDIVIDUAL_SUPPLY");
  }

  function isPublicSaleActive() public view returns (bool) {
    return (_publicSaleTime == 0 || _publicSaleTime < block.timestamp);
  }

  function isPreSaleActive() public view returns (bool) {
    return (_preSaleTime == 0 || (_preSaleTime < block.timestamp) && (block.timestamp < _publicSaleTime));
  }

  function onEarlyPurchaseList(address addr, bytes32[] calldata merkleProof) public view returns (bool) {
    require(_merkleRoot.length > 0, "BASE_COLLECTION/PRESALE_MINT_LIST_UNSET");

    bytes32 node = keccak256(abi.encodePacked(addr));
    return MerkleProof.verify(merkleProof, _merkleRoot, node);
  }

  function MAX_TOTAL_MINT() public view returns (uint256) {
    return _maxSupply;
  }

  function PRICE() public view returns (uint256) {
    if (isPreSaleActive()) {
      return _presalePrice;
    }

    return _price;
  }

  function MAX_TOTAL_MINT_PER_ADDRESS() public view returns (uint256) {
    if (isPreSaleActive()) {
      return _presaleMaxPerAddress;
    }

    return _maxPerAddress;
  }

  function pause() external onlyOwner {
    _pause();
  }

  function unpause() external onlyOwner {
    _unpause();
  }
}