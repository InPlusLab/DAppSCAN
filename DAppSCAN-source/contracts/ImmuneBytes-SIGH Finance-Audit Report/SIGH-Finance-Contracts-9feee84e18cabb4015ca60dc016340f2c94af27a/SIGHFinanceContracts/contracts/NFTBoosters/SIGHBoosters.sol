// SPDX-License-Identifier: agpl-3.0
pragma experimental ABIEncoderV2;
pragma solidity 0.7.0;

import "../dependencies/openzeppelin/token/ERC721/IERC721Metadata.sol";
import "../dependencies/openzeppelin/token/ERC721/IERC721Enumerable.sol";
import "../dependencies/openzeppelin/token/ERC721/IERC721Receiver.sol";

import "../dependencies/openzeppelin/introspection/ERC165.sol";
import "../dependencies/openzeppelin/access/Ownable.sol";
import "../dependencies/openzeppelin/utils/Counters.sol";
import "../dependencies/openzeppelin/math/SafeMath.sol";
import "../dependencies/openzeppelin/utils/Address.sol";
import "../dependencies/openzeppelin/utils/Strings.sol";

import "../dependencies/BoostersDependencies/BoostersEnumerableSet.sol";
import "../dependencies/BoostersDependencies/BoostersEnumerableMap.sol";
import "../dependencies/BoostersDependencies/BoostersStringUtils.sol";

import "../../interfaces/NFTBoosters/ISIGHBoosters.sol";


contract SIGHBoosters is ISIGHBoosters, ERC165,IERC721Metadata,IERC721Enumerable, Ownable {

    using Counters for Counters.Counter;
    Counters.Counter private _boosterIds;

    using SafeMath for uint256;
    using Address for address;
    using BoostersEnumerableSet for BoostersEnumerableSet.BoosterSet;
    using BoostersEnumerableMap for BoostersEnumerableMap.UintToNFTMap;
    using Strings for uint256;
    using BoostersStringUtils for string;

    // Equals to `bytes4(keccak256("onERC721Received(address,address,uint256,bytes)"))`
    // which can be also obtained as `IERC721Receiver(0).onERC721Received.selector`
    bytes4 private constant _ERC721_RECEIVED = 0x150b7a02;
    bytes4 private constant _INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;
    bytes4 private constant _INTERFACE_ID_ERC721_ENUMERABLE = 0x780e9d63;

    string private _name;
    string private _symbol;
    mapping (uint256 => string) private _BoostURIs;
    string private _baseURI;

    struct boosterCategory {
        bool isSupported;
        uint256 totalBoosters;
        uint256 _platformFeeDiscount;
        uint256 _sighPayDiscount;
    }
    
    string[] private boosterTypesList ;
    mapping (string => boosterCategory) private boosterCategories;

    mapping(uint => bool) blacklistedBoosters;                                    // Mapping for blacklisted boosters
    mapping (uint256 => string) private _BoosterCategory;
    mapping (uint256 => address) private _BoosterApprovals;                       // Mapping from BoosterID to approved address
    mapping (address => mapping (address => bool)) private _operatorApprovals;    // Mapping from owner to operator approvals
   
    mapping (address => BoostersEnumerableSet.BoosterSet) private farmersWithBoosts;     // Mapping from holder address to their (enumerable) set of owned tokens & categories
    BoostersEnumerableMap.UintToNFTMap private boostersData;                            // Enumerable mapping from token ids to their owners & categories


    constructor(string memory name_, string memory symbol_)  {
        _name = name_;
        _symbol = symbol_;

        _registerInterface(_INTERFACE_ID_ERC721);
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
        _registerInterface(_INTERFACE_ID_ERC721_ENUMERABLE);
    }


    // #################################
    // ######## ADMIN FUNCTIONS ########
    // #################################

    function addNewBoosterType(string memory _type, uint256 _platformFeeDiscount_, uint256 _sighPayDiscount_) public override onlyOwner returns (bool) {
        require(!boosterCategories[_type].isSupported,"BOOSTERS: Type already exists");
        boosterCategories[_type] =  boosterCategory({isSupported: true, totalBoosters:0, _platformFeeDiscount: _platformFeeDiscount_, _sighPayDiscount: _sighPayDiscount_  });
        boosterTypesList.push(_type);
        emit newCategoryAdded(_type,_platformFeeDiscount_,_sighPayDiscount_);
        return true;
    }

    function _updateBaseURI(string memory baseURI )  public override onlyOwner {
        _baseURI = baseURI;
        emit baseURIUpdated(baseURI);
     }

    function updateDiscountMultiplier(string memory _type, uint256 _platformFeeDiscount_,uint256 _sighPayDiscount_)  public override onlyOwner returns (bool) {
        require(boosterCategories[_type].isSupported,"BOOSTERS: Type doesn't exist");
        boosterCategories[_type]._platformFeeDiscount = _platformFeeDiscount_;
        boosterCategories[_type]._sighPayDiscount = _sighPayDiscount_;
        emit discountMultiplierUpdated(_type,_platformFeeDiscount_,_sighPayDiscount_ );
        return true;
     }

    function createNewBoosters(string[] memory _type,  string[] memory boosterURI) public override onlyOwner returns (uint256) {
        require( _type.length == boosterURI.length, 'Size not equal');
        bytes memory _data;
        uint i;
        for(; i< _type.length; i++) {
            createNewSIGHBooster(msg.sender, _type[i], boosterURI[i], _data);
        }
        return i;
    }

    function createNewSIGHBooster(address _owner, string memory _type,  string memory boosterURI, bytes memory _data) public override onlyOwner returns (uint256) {
        require(boosterCategories[_type].isSupported,'Not a valid Type');
        require(_boosterIds.current() < 65535, 'Max Booster limit reached');

        _boosterIds.increment();
        uint256 newItemId = _boosterIds.current();

        _safeMint(_owner, newItemId, _type,_data);
        _setBoosterURI(newItemId,boosterURI);
        _setType(newItemId,_type);

        boosterCategories[_type].totalBoosters = boosterCategories[_type].totalBoosters.add(1);

        emit BoosterMinted(_owner,_type,boosterURI,newItemId,boosterCategories[_type].totalBoosters);
        return newItemId;
    }


    
    function updateBoosterURI(uint256 boosterId, string memory boosterURI )  public override onlyOwner returns (bool) {
        require(_exists(boosterId), "Non-existent Booster");
        _setBoosterURI(boosterId,boosterURI);
        return true;
     }



    function blackListBooster(uint256 boosterId) external override onlyOwner {
        require(_exists(boosterId), "Non-existent Booster");
        blacklistedBoosters[boosterId] = true;
        emit BoosterBlackListed(boosterId);
    }

    function whiteListBooster(uint256 boosterId) external override onlyOwner {
        require(_exists(boosterId), "Non-existent Booster");
        require(blacklistedBoosters[boosterId], "Already whitelisted");
        blacklistedBoosters[boosterId] = false;
        emit BoosterWhiteListed(boosterId);
    }

    // ###########################################
    // ######## STANDARD ERC721 FUNCTIONS ########
    // ###########################################

    function name() public view override(IERC721Metadata,ISIGHBoosters) returns (string memory) {
        return _name;
    }

    function symbol() public view override(IERC721Metadata,ISIGHBoosters) returns (string memory) {
        return _symbol;
    }

    // Returns total number of Boosters owned by the _owner
    function balanceOf(address _owner) external view override(IERC721,ISIGHBoosters) returns (uint256 balance) {
        require(_owner != address(0), "ERC721: balance query for the zero address");
        return farmersWithBoosts[_owner].length();
    }

    //  See {IERC721Enumerable-tokenOfOwnerByIndex}.
    function tokenOfOwnerByIndex(address owner, uint256 index) public view override(IERC721Enumerable,ISIGHBoosters) returns (uint256 id) {
        BoostersEnumerableSet.ownedBooster memory _booster = farmersWithBoosts[owner].at(index);
        return _booster.boostId;
    }

    // Returns current owner of the Booster having the ID = boosterId
    function ownerOf(uint256 boosterId) public view override returns (address owner) {
         owner =  ownerOfBooster(boosterId);
         return owner;
    }

    // Returns current owner of the Booster having the ID = boosterId
    function ownerOfBooster(uint256 boosterId) public view override returns (address owner) {
         ( owner, ) =  boostersData.get(boosterId);
         return owner;
    }

    // Returns the boostURI for the Booster
    function tokenURI(uint256 boosterId) public view override(IERC721Metadata,ISIGHBoosters) returns (string memory) {
        require(_exists(boosterId), "Non-existent Booster");
        string memory _boostURI = _BoostURIs[boosterId];
        
        if (bytes(_baseURI).length == 0 && bytes(_boostURI).length > 0) {                                  // If there is no base URI, return the token URI.
            return _boostURI;
        }

        if (bytes(_baseURI).length > 0 && bytes(_boostURI).length > 0) {                                  // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
            return string(abi.encodePacked(_baseURI, _boostURI));
        }
        
        if (bytes(_baseURI).length > 0 && bytes(_boostURI).length == 0) {                                  // If there is a baseURI but no tokenURI, concatenate the boosterId to the baseURI.
            return string(abi.encodePacked(_baseURI, boosterId.toString()));
        }

        return boosterId.toString();
    }

    function baseURI() public view override returns (string memory) {
        return _baseURI;
    }

    function totalSupply() public view override(IERC721Enumerable,ISIGHBoosters) returns (uint256) {
        return boostersData.length();
    }

    function tokenByIndex(uint256 index) public view override(IERC721Enumerable,ISIGHBoosters) returns (uint256) {
        (uint256 _boostId, , ) = boostersData.at(index);
        return _boostId;
    }

    // A BOOSTER owner can approve anyone to be able to transfer the underlying booster
    function approve(address to, uint256 boosterId) override(IERC721,ISIGHBoosters) external {
        address _owner = ownerOfBooster(boosterId);
        require(to != _owner, "BOOSTERS: Owner cannot be approved");
        require(_msgSender() == _owner || isApprovedForAll(_owner, _msgSender()),"BOOSTERS: Neither owner nor approved");
        _approve(to, boosterId);
    }

    // Returns the Address currently approved for the Booster with ID = boosterId
    function getApproved(uint256 boosterId) public view override(IERC721,ISIGHBoosters) returns (address) {
        require(_exists(boosterId), "BOOSTERS: Non-existent Booster");
        return _BoosterApprovals[boosterId];
    }

    function setApprovalForAll(address operator, bool _approved) public virtual override(IERC721,ISIGHBoosters) {
        require(operator != _msgSender(), "BOOSTERS: Caller cannot be Approved");
        require(_operatorApprovals[_msgSender()][operator] != _approved && _approved != true , "Already Approved");
        require(_operatorApprovals[_msgSender()][operator] != _approved && _approved != false , "Already Not-Approved");
        _operatorApprovals[_msgSender()][operator] = _approved;
        emit ApprovalForAll(_msgSender(), operator, _approved);
    }

    function isApprovedForAll(address owner, address operator) public view override(IERC721,ISIGHBoosters) returns (bool) {
       return _operatorApprovals[owner][operator];
    }

    function safeTransferFrom(address from, address to, uint256 boosterId)  public virtual override(IERC721,ISIGHBoosters) {
        require(!blacklistedBoosters[boosterId], "Booster blacklisted");
        safeTransferFrom(from, to, boosterId, "");
    }

    function safeTransferFrom(address from, address to, uint256 boosterId, bytes memory data) public virtual override(IERC721,ISIGHBoosters) {
        require(!blacklistedBoosters[boosterId], "Booster blacklisted");
        require(_isApprovedOrOwner(_msgSender(), boosterId), "BOOSTERS: Neither owner nor approved");
        _safeTransfer(from, to, boosterId, data);
    }


    function transferFrom(address from, address to, uint256 boosterId) public virtual override(IERC721,ISIGHBoosters) {
        require(!blacklistedBoosters[boosterId], "Booster blacklisted");
        require(_isApprovedOrOwner(_msgSender(), boosterId), "BOOSTERS: Neither owner nor approved");
        _transfer(from, to, boosterId);
    }


    // #############################################################
    // ######## FUNCTIONS SPECIFIC TO SIGH FINANCE BOOSTERS ########
    // #############################################################

    // Returns the number of Boosters of a particular category owned by the owner address
    function totalBoostersOwnedOfType(address owner, string memory _category) external view override returns (uint) {
        require(owner != address(0), "SIGH BOOSTERS: zero address query");
        require(boosterCategories[_category].isSupported, "Not valid Type");

        BoostersEnumerableSet.BoosterSet storage boostersOwned = farmersWithBoosts[owner];

        if (boostersOwned.length() == 0) {
            return 0;
        }

        uint ans;

        for (uint32 i=0; i < boostersOwned.length(); i++ ) {
            BoostersEnumerableSet.ownedBooster memory _booster = boostersOwned.at(i);
            if ( _booster._type.equal(_category) ) {
                ans = ans + 1;
            }
        }

        return ans ;
    }

    // Returns farmer address who owns this Booster and its boosterType 
    function getBoosterInfo(uint256 boosterId) external view override returns (address farmer, string memory boosterType, uint platformFeeDiscount, uint sighPayDiscount ) {
         ( farmer, boosterType ) =  boostersData.get(boosterId);
         platformFeeDiscount = boosterCategories[boosterType]._platformFeeDiscount;
         sighPayDiscount = boosterCategories[boosterType]._sighPayDiscount ;
    }

    function isCategorySupported(string memory _category) external view override returns (bool) {
        return boosterCategories[_category].isSupported;
    }

    function totalBoostersAvailable(string memory _category) external view override returns (uint256) {
        return boosterCategories[_category].totalBoosters;
    }

    

    // get Booster Type
    function getBoosterCategory(uint256 boosterId) public view override returns ( string memory boosterType ) {
         ( , boosterType ) =  boostersData.get(boosterId);
    }

    // get Booster Discount Multiplier for a Booster
    function getDiscountRatiosForBooster(uint256 boosterId) external view override returns ( uint platformFeeDiscount, uint sighPayDiscount ) {
        require(_exists(boosterId), "Non-existent Booster");
        platformFeeDiscount =  boosterCategories[getBoosterCategory(boosterId)]._platformFeeDiscount;
        sighPayDiscount =  boosterCategories[getBoosterCategory(boosterId)]._sighPayDiscount;
    }

    // get Booster Discount Multipliers for Booster Category
    function getDiscountRatiosForBoosterCategory(string memory _category) external view override returns ( uint platformFeeDiscount, uint sighPayDiscount ) {
        require(boosterCategories[_category].isSupported,"BOOSTERS: Type doesn't exist");
        platformFeeDiscount =  boosterCategories[_category]._platformFeeDiscount;
        sighPayDiscount =  boosterCategories[_category]._sighPayDiscount;
    }


    function isValidBooster(uint256 boosterId) external override view returns (bool) {
        return _exists(boosterId);
    }
    
    
    // Returns a list containing all the Booster categories currently supported
    function getAllBoosterTypes() external override view returns (string[] memory) {
        return boosterTypesList;
    }   
    
    
//    // Returns a list of BoosterIDs of the boosters owned by the user
//    function getAllBoostersOwned(address user) external view returns(uint[] memory boosterIds) {
//        BoostersEnumerableSet.BoosterSet storage boostersOwned = farmersWithBoosts[user];
//        for (uint i=1; i < boostersOwned.length() ; i++) {
//            BoostersEnumerableSet.ownedBooster memory _booster = boostersOwned.at(i);
//            boosterIds[i] = _booster.boostId;
//        }
//    }

    // returns true is the Booster has been blacklisted. Else returns false
    function isBlacklisted(uint boosterId) external override view returns(bool) {
        return blacklistedBoosters[boosterId];
    }





    // #####################################
    // ######## INTERNAL FUNCTIONS  ########
    // #####################################

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 boosterId, string memory _typeOfBoost, bytes memory _data) internal {
        _mint(to, boosterId, _typeOfBoost);
        require(_checkOnERC721Received(address(0), to, boosterId, _data), "BOOSTERS: Transfer to non ERC721Receiver implementer");
    }


    /**
     * @dev Mints `boosterId` and transfers it to `to`.
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     */
    function _mint(address to, uint256 boosterId, string memory _typeOfBoost) internal  {
        require(to != address(0), "BOOSTERS: Cannot mint to zero address");
        require(!_exists(boosterId), "BOOSTERS: Already minted");

        BoostersEnumerableSet.ownedBooster memory newBooster = BoostersEnumerableSet.ownedBooster({ boostId: boosterId, _type: _typeOfBoost });
        BoostersEnumerableMap.boosterInfo memory newBoosterInfo = BoostersEnumerableMap.boosterInfo({ owner: to, _type: _typeOfBoost });

        farmersWithBoosts[to].add(newBooster);
        boostersData.set(boosterId, newBoosterInfo);

        emit Transfer(address(0), to, boosterId);
    }

    /**
     * @dev Returns whether `boosterId` exists.
     */
    function _exists(uint256 boosterId) internal view returns (bool) {
        return boostersData.contains(boosterId);
    }


    /**
     * @dev Sets `_boosterURI` as the boosterURI of `boosterId`.
     *
     * Requirements:
     *
     * - `boosterId` must exist.
     */
    function _setBoosterURI(uint256 boosterId, string memory _boosterURI) internal  {
        _BoostURIs[boosterId] = _boosterURI;
         emit boosterURIUpdated(boosterId,_boosterURI);
    }

    function _setType(uint256 boosterId, string memory _type) internal virtual {
        require(_exists(boosterId), "Non-existent Booster");
        _BoosterCategory[boosterId] = _type;
    }


    function _approve(address to, uint256 boosterId) private {
        _BoosterApprovals[boosterId] = to;
        emit Approval(ownerOfBooster(boosterId), to, boosterId);
    }

    // Returns whether `spender` is allowed to manage `tokenId`.
    function _isApprovedOrOwner(address spender, uint256 boosterId) internal view returns (bool) {
        require(_exists(boosterId), "Non-existent Booster");
        address owner = ownerOfBooster(boosterId);
        return (spender == owner || getApproved(boosterId) == spender || isApprovedForAll(owner, spender));
    }

    function _safeTransfer(address from, address to, uint256 boosterId, bytes memory _data) internal virtual {
        _transfer(from, to, boosterId);
        require(_checkOnERC721Received(from, to, boosterId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    function _transfer(address from, address to, uint256 boosterId) internal virtual {
        require(ownerOfBooster(boosterId) == from, "BOOSTERS: Not owned");
        require(to != address(0), "BOOSTERS: Transfer to the zero address");

//        _beforeTokenTransfer(from, to, boosterId);
        _approve(address(0), boosterId);          // Clear approvals from the previous owner
        
        BoostersEnumerableSet.ownedBooster memory _ownedBooster = BoostersEnumerableSet.ownedBooster({boostId: boosterId, _type: _BoosterCategory[boosterId] });

        farmersWithBoosts[from].remove(_ownedBooster);
        farmersWithBoosts[to].add(_ownedBooster);

        BoostersEnumerableMap.boosterInfo memory _boosterInfo = BoostersEnumerableMap.boosterInfo({owner: to, _type: _BoosterCategory[boosterId] });
        boostersData.set(boosterId, _boosterInfo);

        emit Transfer(from, to, boosterId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param boosterId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(address from, address to, uint256 boosterId, bytes memory _data) private returns (bool) {
        if (!to.isContract()) {
            return true;
        }
        bytes memory returndata = to.functionCall(abi.encodeWithSelector( IERC721Receiver(to).onERC721Received.selector, _msgSender(), from, boosterId, _data ), "ERC721: transfer to non ERC721Receiver implementer");
        bytes4 retval = abi.decode(returndata, (bytes4));
        return (retval == _ERC721_RECEIVED);
    }


//    /**
//     * @dev Hook that is called before any token transfer.
//    */
//    function _beforeTokenTransfer(address from, address to, uint256 boosterId) internal virtual { }


}