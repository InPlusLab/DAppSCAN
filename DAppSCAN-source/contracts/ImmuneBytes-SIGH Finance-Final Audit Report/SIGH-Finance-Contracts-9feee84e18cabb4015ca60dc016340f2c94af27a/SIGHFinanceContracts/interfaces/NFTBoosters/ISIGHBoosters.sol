// SPDX-License-Identifier: MIT
pragma experimental ABIEncoderV2;
pragma solidity ^0.7.0;

interface ISIGHBoosters {

    // ########################
    // ######## EVENTS ########
    // ########################

    event baseURIUpdated(string baseURI);
    event newCategoryAdded(string _type, uint256 _platformFeeDiscount_, uint256 _sighPayDiscount_);
    event BoosterMinted(address _owner, string _type,string boosterURI,uint256 newItemId,uint256 totalBoostersOfThisCategory);
    event boosterURIUpdated(uint256 boosterId, string _boosterURI);
    event discountMultiplierUpdated(string _type,uint256 _platformFeeDiscount_,uint256 _sighPayDiscount_ );

    event BoosterWhiteListed(uint256 boosterId);
    event BoosterBlackListed(uint256 boosterId);

    // #################################
    // ######## ADMIN FUNCTIONS ########
    // #################################
    
    function addNewBoosterType(string memory _type, uint256 _platformFeeDiscount_, uint256 _sighPayDiscount_) external returns (bool) ;
    function createNewBoosters(string[] memory _type,  string[] memory boosterURI) external returns (uint256);
    function createNewSIGHBooster(address _owner, string memory _type,  string memory boosterURI, bytes memory _data ) external returns (uint256) ;
    function _updateBaseURI(string memory baseURI )  external ;
    function updateBoosterURI(uint256 boosterId, string memory boosterURI )  external returns (bool) ;
    function updateDiscountMultiplier(string memory _type, uint256 _platformFeeDiscount_,uint256 _sighPayDiscount_)  external returns (bool) ;

    function blackListBooster(uint256 boosterId) external;
    function whiteListBooster(uint256 boosterId) external;
    // ###########################################
    // ######## STANDARD ERC721 FUNCTIONS ########
    // ###########################################

    function name() external view  returns (string memory) ;
    function symbol() external view  returns (string memory) ;
    function totalSupply() external view  returns (uint256) ;
    function baseURI() external view returns (string memory) ;

    function tokenByIndex(uint256 index) external view  returns (uint256) ;

    function balanceOf(address _owner) external view returns (uint256 balance) ;    // Returns total number of Boosters owned by the _owner
    function tokenOfOwnerByIndex(address owner, uint256 index) external view  returns (uint256) ; //  See {IERC721Enumerable-tokenOfOwnerByIndex}.

    function ownerOfBooster(uint256 boosterId) external view returns (address owner) ; // Returns current owner of the Booster having the ID = boosterId
    function tokenURI(uint256 boosterId) external view  returns (string memory) ;   // Returns the boostURI for the Booster

    function approve(address to, uint256 boosterId) external ;  // A BOOSTER owner can approve anyone to be able to transfer the underlying booster
    function setApprovalForAll(address operator, bool _approved) external;


    function getApproved(uint256 boosterId) external view  returns (address);   // Returns the Address currently approved for the Booster with ID = boosterId
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    function transferFrom(address from, address to, uint256 boosterId) external;
    function safeTransferFrom(address from, address to, uint256 boosterId) external;
    function safeTransferFrom(address from, address to, uint256 boosterId, bytes memory data) external;

    // #############################################################
    // ######## FUNCTIONS SPECIFIC TO SIGH FINANCE BOOSTERS ########
    // #############################################################

    function getAllBoosterTypes() external view returns (string[] memory);

    function isCategorySupported(string memory _category) external view returns (bool);
    function getDiscountRatiosForBoosterCategory(string memory _category) external view returns ( uint platformFeeDiscount, uint sighPayDiscount );

    function totalBoostersAvailable(string memory _category) external view returns (uint256);

    function totalBoostersOwnedOfType(address owner, string memory _category) external view returns (uint256) ;  // Returns the number of Boosters of a particular category owned by the owner address

    function isValidBooster(uint256 boosterId) external view returns (bool);
    function getBoosterCategory(uint256 boosterId) external view returns ( string memory boosterType );
    function getDiscountRatiosForBooster(uint256 boosterId) external view returns ( uint platformFeeDiscount, uint sighPayDiscount );
    function getBoosterInfo(uint256 boosterId) external view returns (address farmer, string memory boosterType,uint platformFeeDiscount, uint sighPayDiscount );

    function isBlacklisted(uint boosterId) external view returns(bool) ;
//     function getAllBoosterTypesSupported() external view returns (string[] memory) ;

}