// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC721/ERC721.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol';
import '@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import './interfaces/IERC721Helpers.sol';
import './utils/Counters.sol';

/**
 * ok.lets.ape. NFT contract
 */
contract OKLetsApe is
  Ownable,
  ERC721Burnable,
  ERC721Enumerable,
  ERC721Pausable
{
  using SafeMath for uint256;
  using Strings for uint256;
  using Counters for Counters.Counter;

  // Token id counter
  Counters.Counter private _tokenIds;

  // Sale round counters
  Counters.Counter public _preSaleRound;
  Counters.Counter public _publicSaleRound;

  // Mints per sale round counter
  Counters.Counter public _tokensMintedPerSaleRound;

  // Base token uri
  string private baseTokenURI; // baseTokenURI can point to IPFS folder like https://ipfs.io/ipfs/{cid}/

  // Payment address
  address private paymentAddress;

  // Royalties address
  address private royaltyAddress;

  // Royalties basis points (percentage using 2 decimals - 10000 = 100, 0 = 0)
  uint256 private royaltyBasisPoints = 1000; // 10%

  // Token info
  string public constant TOKEN_NAME = 'ok.lets.ape.';
  string public constant TOKEN_SYMBOL = 'OKLApe';
  uint256 public constant TOTAL_TOKENS = 10000;

  // Mint cost and max per wallet
  uint256 public mintCost = 0.0542069 ether;

  // Mint cost contract
  address public mintCostContract;

  // Max wallet amount
  uint256 public maxWalletAmount = 10;

  // Amount of tokens to mint before automatically stopping public sale
  uint256 public maxMintsPerSaleRound = 1000;

  // Pre sale/Public sale active
  bool public preSaleActive;
  bool public publicSaleActive;

  // Presale whitelist
  mapping(address => bool) public presaleWhitelist;

  // Authorized addresses
  mapping(address => bool) public authorizedAddresses;

  //-- Events --//
  event RoyaltyBasisPoints(uint256 indexed _royaltyBasisPoints);

  //-- Modifiers --//

  // Public sale active modifier
  modifier whenPreSaleActive() {
    require(preSaleActive, 'Pre sale is not active');
    _;
  }

  // Public sale active modifier
  modifier whenPublicSaleActive() {
    require(publicSaleActive, 'Public sale is not active');
    _;
  }

  // Owner or public sale active modifier
  modifier whenOwnerOrSaleActive() {
    require(
      owner() == _msgSender() || preSaleActive || publicSaleActive,
      'Sale is not active'
    );
    _;
  }

  // Owner or authorized addresses modifier
  modifier whenOwnerOrAuthorizedAddress() {
    require(
      owner() == _msgSender() || authorizedAddresses[_msgSender()],
      'Not authorized'
    );
    _;
  }

  // -- Constructor --//
  constructor(string memory _baseTokenURI, uint8 _counterType)
    ERC721(TOKEN_NAME, TOKEN_SYMBOL)
  {
    baseTokenURI = _baseTokenURI;
    paymentAddress = owner();
    royaltyAddress = owner();
    _tokenIds.setType(_counterType);
  }

  // -- External Functions -- //

  // Start pre sale
  function startPreSale() external onlyOwner {
    _preSaleRound.increment();
    _tokensMintedPerSaleRound.reset();
    preSaleActive = true;
    publicSaleActive = false;
  }

  // End pre sale
  function endPreSale() external onlyOwner {
    preSaleActive = false;
    publicSaleActive = false;
  }

  // Start public sale
  function startPublicSale() external onlyOwner {
    _publicSaleRound.increment();
    _tokensMintedPerSaleRound.reset();
    preSaleActive = false;
    publicSaleActive = true;
  }

  // End public sale
  function endPublicSale() external onlyOwner {
    preSaleActive = false;
    publicSaleActive = false;
  }

  // Support royalty info - See {EIP-2981}: https://eips.ethereum.org/EIPS/eip-2981
  function royaltyInfo(uint256, uint256 _salePrice)
    external
    view
    returns (address receiver, uint256 royaltyAmount)
  {
    return (royaltyAddress, (_salePrice.mul(royaltyBasisPoints)).div(10000));
  }

  // Adds multiple addresses to whitelist
  function addToPresaleWhitelist(address[] memory _addresses)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < _addresses.length; i++) {
      address _address = _addresses[i];
      presaleWhitelist[_address] = true;
    }
  }

  // Removes multiple addresses from whitelist
  function removeFromPresaleWhitelist(address[] memory _addresses)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < _addresses.length; i++) {
      address _address = _addresses[i];
      presaleWhitelist[_address] = false;
    }
  }

  // Mint token - requires amount
  function mint(uint256 _amount) external payable whenOwnerOrSaleActive {
    require(_amount > 0, 'Must mint at least one');

    // Check there enough mints left to mint
    require(_amount <= getMintsLeft(), 'Minting would exceed max supply');

    // Check there are mints left per sale round
    require(
      _amount <= getMintsLeftPerSaleRound(),
      'Minting would exceed max mint amount per sale round'
    );

    // Set cost to mint
    uint256 costToMint = 0;

    bool isOwner = owner() == _msgSender();

    if (!isOwner) {
      // If pre sale is active, make sure user is on whitelist
      if (preSaleActive) {
        require(presaleWhitelist[_msgSender()], 'Must be on whitelist');
      }

      // Set cost to mint
      costToMint = getMintCost(_msgSender()) * _amount;

      // Get current address total balance
      uint256 currentWalletAmount = super.balanceOf(_msgSender());

      // Check current token amount and mint amount is not more than max wallet amount
      require(
        currentWalletAmount.add(_amount) <= maxWalletAmount,
        'Requested amount exceeds maximum mint amount per wallet'
      );
    }

    // Check cost to mint, and if enough ETH is passed to mint
    require(costToMint <= msg.value, 'ETH amount sent is not correct');

    for (uint256 i = 0; i < _amount; i++) {
      // Increment token id
      _tokenIds.increment();

      // Safe mint
      _safeMint(_msgSender(), _tokenIds.current());

      // Increment tokens minted per sale round
      _tokensMintedPerSaleRound.increment();
    }

    // Send mint cost to payment address
    Address.sendValue(payable(paymentAddress), costToMint);

    // Return unused value
    if (msg.value > costToMint) {
      Address.sendValue(payable(_msgSender()), msg.value.sub(costToMint));
    }

    // If tokens minted per sale round hits the max mints per sale round, end pre/public sale
    if (_tokensMintedPerSaleRound.current() >= maxMintsPerSaleRound) {
      preSaleActive = false;
      publicSaleActive = false;
    }
  }

  // Custom mint function - requires token id and reciever address
  // Mint or transfer token id - Used for cross chain bridging
  function customMint(uint256 _tokenId, address _reciever)
    external
    whenOwnerOrAuthorizedAddress
  {
    require(!publicSaleActive && !preSaleActive, 'Sales must be inactive');
    require(
      _tokenId > 0 && _tokenId <= TOTAL_TOKENS,
      'Must pass valid token id'
    );

    if (_exists(_tokenId)) {
      // If token exists, make sure token owner is contract owner
      require(owner() == ownerOf(_tokenId), 'Token is already owned');

      // Transfer from contract owner to reciever
      safeTransferFrom(owner(), _reciever, _tokenId);
    } else {
      require(
        _tokenIds.current() > _tokenId,
        'Cannot custom mint NFT if it is still in line for standard mint'
      );
      // Safe mint
      _safeMint(_reciever, _tokenId);
    }
  }

  // Custom burn function - required token id
  // Transfer token id to contract owner - used for cross chain bridging
  function customBurn(uint256 _tokenId) external whenOwnerOrAuthorizedAddress {
    require(!publicSaleActive && !preSaleActive, 'Sales must be inactive');
    require(
      _tokenId > 0 && _tokenId <= TOTAL_TOKENS,
      'Must pass valid token id'
    );

    require(_exists(_tokenId), 'Nonexistent token');

    // Transfer from token owner to contract owner
    safeTransferFrom(ownerOf(_tokenId), owner(), _tokenId);
  }

  // Adds multiple addresses to authorized addresses
  function addToAuthorizedAddresses(address[] memory _addresses)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < _addresses.length; i++) {
      address _address = _addresses[i];
      authorizedAddresses[_address] = true;
    }
  }

  // Removes multiple addresses from authorized addresses
  function removeFromAuthorizedAddresses(address[] memory _addresses)
    external
    onlyOwner
  {
    for (uint256 i = 0; i < _addresses.length; i++) {
      address _address = _addresses[i];
      authorizedAddresses[_address] = false;
    }
  }

  // Set mint cost
  function setMintCost(uint256 _cost) external onlyOwner {
    mintCost = _cost;
  }

  // Set mint cost contract
  function setERC721HelperContract(address _contract) external onlyOwner {
    if (_contract != address(0)) {
      IERC721Helpers _contCheck = IERC721Helpers(_contract);
      // allow setting to zero address to effectively turn off logic
      require(
        _contCheck.getMintCost(_msgSender()) == 0 ||
          _contCheck.getMintCost(_msgSender()) > 0,
        'Contract does not implement interface'
      );
    }
    mintCostContract = _contract;
  }

  // Set max wallet amount
  function setMaxWalletAmount(uint256 _amount) external onlyOwner {
    maxWalletAmount = _amount;
  }

  // Set max mints per sale round amount
  function setMaxMintsPerSaleRound(uint256 _amount) external onlyOwner {
    maxMintsPerSaleRound = _amount;
  }

  // Reset tokens minted per sale round
  function resetTokensMintedPerSaleRound() external onlyOwner {
    _tokensMintedPerSaleRound.reset();
  }

  // Reset pre sale rounds
  function resetPreSaleRounds() external onlyOwner {
    _preSaleRound.reset();
  }

  // Reset public sale rounds
  function resetPublicSaleRounds() external onlyOwner {
    _publicSaleRound.reset();
  }

  // Set payment address
  function setPaymentAddress(address _address) external onlyOwner {
    paymentAddress = _address;
  }

  // Set royalty wallet address
  function setRoyaltyAddress(address _address) external onlyOwner {
    royaltyAddress = _address;
  }

  // Set royalty basis points
  function setRoyaltyBasisPoints(uint256 _basisPoints) external onlyOwner {
    royaltyBasisPoints = _basisPoints;
    emit RoyaltyBasisPoints(_basisPoints);
  }

  // Set base URI
  function setBaseURI(string memory _uri) external onlyOwner {
    baseTokenURI = _uri;
  }

  //-- Public Functions --//

  // Get mint cost from mint cost contract, or fallback to local mintCost
  function getMintCost(address _address) public view returns (uint256) {
    return
      mintCostContract != address(0)
        ? IERC721Helpers(mintCostContract).getMintCost(_address)
        : mintCost;
  }

  // Get mints left
  function getMintsLeft() public view returns (uint256) {
    uint256 currentSupply = super.totalSupply();
    uint256 counterType = _tokenIds._type;
    uint256 totalTokens = counterType != 0 ? TOTAL_TOKENS.div(2) : TOTAL_TOKENS;
    return totalTokens.sub(currentSupply);
  }

  // Get mints left per sale round
  function getMintsLeftPerSaleRound() public view returns (uint256) {
    return maxMintsPerSaleRound.sub(_tokensMintedPerSaleRound.current());
  }

  // Get circulating supply - current supply minus contract owner supply
  function getCirculatingSupply() public view returns (uint256) {
    uint256 currentSupply = super.totalSupply();
    uint256 ownerSupply = balanceOf(owner());
    return currentSupply.sub(ownerSupply);
  }

  // Get total tokens based on counter type
  function getTotalTokens() public view returns (uint256) {
    uint256 counterType = _tokenIds._type;
    uint256 totalTokens = counterType != 0 ? TOTAL_TOKENS.div(2) : TOTAL_TOKENS;
    return totalTokens;
  }

  // Token URI (baseTokenURI + tokenId)
  function tokenURI(uint256 _tokenId)
    public
    view
    virtual
    override
    returns (string memory)
  {
    require(_exists(_tokenId), 'Nonexistent token');

    return string(abi.encodePacked(_baseURI(), _tokenId.toString(), '.json'));
  }

  // Contract metadata URI - Support for OpenSea: https://docs.opensea.io/docs/contract-level-metadata
  function contractURI() public view returns (string memory) {
    return string(abi.encodePacked(_baseURI(), 'contract.json'));
  }

  // Override supportsInterface - See {IERC165-supportsInterface}
  function supportsInterface(bytes4 _interfaceId)
    public
    view
    virtual
    override(ERC721, ERC721Enumerable)
    returns (bool)
  {
    return super.supportsInterface(_interfaceId);
  }

  // Pauses all token transfers - See {ERC721Pausable}
  function pause() external virtual onlyOwner {
    _pause();
  }

  // Unpauses all token transfers - See {ERC721Pausable}
  function unpause() external virtual onlyOwner {
    _unpause();
  }

  //-- Internal Functions --//

  // Get base URI
  function _baseURI() internal view override returns (string memory) {
    return baseTokenURI;
  }

  // Before all token transfer
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenId
  ) internal virtual override(ERC721, ERC721Enumerable, ERC721Pausable) {
    super._beforeTokenTransfer(_from, _to, _tokenId);
  }
}
