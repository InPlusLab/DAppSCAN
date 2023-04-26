// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "../governance/InitializableOwner.sol";
import "../base/BasicMetaTransaction.sol";

contract UserProfile is InitializableOwner, ERC721Holder, BasicMetaTransaction {

    event UserNew(address indexed sender, string nickname, address indexed NFT, uint256 indexed tokenID, uint256 timestamp);
    event WithdrawNFT(address indexed sender, address indexed NFT, uint256 indexed tokenID, uint256 timestamp);
    event ReplaceNFT(address indexed sender, address toNFT, uint256 indexed tokenID, uint256 timestamp);
    event UserUpdateNickname(address indexed sender, string nickname);


    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private supportsNFT;

    struct User {
        address user_id;
        string nickname;
        address NFT_address;
        uint256 token_id;
        bool isActive;
        address superior;
    }

    mapping(address => User) public Users;
    mapping(string => bool) public nicknames;

    bool public _can_create;
    bool public _can_withdraw;
    bool public _can_replace;

    uint public nicknameMaxLength;
    uint public nicknameMinLength;


    constructor() public{
       initialize();
    }


    modifier canCreate() {
        require(_can_create == true, "cant withdraw.");
        _;
    }

    modifier canWithdraw() {
        require(_can_withdraw == true, "cant withdraw.");
        _;
    }

    modifier canReplace() {
        require(_can_replace == true, "cant eplace.");
        _;
    }

    function initialize() public {
        super._initialize();
        _can_create = true;
        _can_withdraw = false;
        _can_replace = false;
        nicknameMaxLength = 30;
        nicknameMinLength = 6;
    }

    function addSupportNFTaddress(address[] memory _nft_address) onlyOwner public {

        require(_nft_address.length != 0, "nft address is zero.");

        for(uint256 i = 0; i < _nft_address.length; i++){
            require(_nft_address[i] != address(0), "address is zero");
            EnumerableSet.add(supportsNFT, _nft_address[i]);
        }
    }

    function switchWithdraw(bool withdraw) onlyOwner public {
        _can_withdraw = withdraw;
    }

    function switchDeposite(bool deposite) onlyOwner public {
        _can_create = deposite;
    }

    function switchReplace(bool replace) onlyOwner public {
        _can_replace = replace;
    }

    function updateNicknameMaxLength(uint256 newLength) public onlyOwner {
        require(newLength > nicknameMinLength, "bad number");
        nicknameMaxLength = newLength;
    }

    function updateNicknameMinLength(uint256 newLength) public onlyOwner {
        require(newLength > 0, "bad number");
        require(newLength < nicknameMaxLength, "bad number");
        
        nicknameMinLength = newLength;
    }

    function checkNickname(string memory nickname) public view returns (bool) {
        bytes memory bt = bytes(nickname);
        if (bt.length > nicknameMaxLength || bt.length < nicknameMinLength) {
            return false;
        }
        
        for (uint i = 0; i < bt.length; ++i) {
            if(bt[i] == '#' || bt[i] == '%' || bt[i] == '@' || bt[i] == '$') {
                return false;
            }
        }

        return true;
    }

    function createProfile(string memory nickname, address nftAddress, uint256 tokenID, address superior) canCreate public {
        _depositeNFT(nftAddress, tokenID);
        _setNickname(msgSender(), nickname);
        Users[msgSender()].superior = superior;

        emit UserNew(msgSender(), nickname, nftAddress, tokenID, block.timestamp);
    }

    function withdraw() canWithdraw public returns(bool) {
        return _withdraw();
    }

    function replaceNFT(address toNFT, uint256 tokenID) canReplace public returns(bool) {
        _withdraw();
        _depositeNFT(toNFT, tokenID);

        ReplaceNFT(msgSender(), toNFT, tokenID, block.timestamp);
        
        return true;
    }

    function updateNickname(string memory nickname) public {
        require(Users[msgSender()].isActive, "User not active");

        _setNickname(msgSender(), nickname);
        emit UserUpdateNickname(msgSender(), nickname);
    }

    function getSupportNFT() public view returns(address[] memory sup){
        sup = new address[](supportsNFT.length());
        for(uint256 i = 0; i < supportsNFT.length(); i++){
            sup[i] = supportsNFT.at(i);
        }
        return sup;
    }

    function pauseUser(address user) public onlyOwner {
        require(Users[user].isActive, "User not active");
        Users[user].isActive = false;
    }

    function reactivateUser(address user) public onlyOwner {
        require(Users[user].user_id != address(0), "User not found");
        Users[user].isActive = true;
    }

    function _setNickname(address user, string memory nickname) internal {
        require(checkNickname(nickname), "bad nickname");
        require(nicknames[nickname] == false, "nickname already used");
        
        nicknames[nickname] = true;

        // reset old nickname.
        if (Users[user].user_id != address(0)) {
            nicknames[Users[user].nickname] = false;
        }
       
        Users[user].nickname = nickname;
    }

    /*
    deposite  nft
     */
    function _depositeNFT(address nftAddress, uint256 tokenID) internal {
    
        // check support
        require(supportsNFT.contains(nftAddress) == true, "support nft address.");
        
        User storage u = Users[msgSender()];

        // check  deposited.
        require(u.user_id == address(0), "address has deposite nft.");
        
        // Loads the interface to deposit the NFT contract
        IERC721 nftToken = IERC721(nftAddress);
        require(msgSender() == nftToken.ownerOf(tokenID), "Only NFT owner can register");
        nftToken.safeTransferFrom(msgSender(), address(this), tokenID);

        u.user_id = msgSender();
        u.NFT_address = address(nftToken);
        u.token_id = tokenID;
        u.isActive = true;
    }

    function _withdraw() internal returns(bool) {

        User storage u = Users[msgSender()];
        require(u.isActive, "not active");
        require(u.user_id != address(0), "has not deposite.");
        require(u.user_id == msgSender(), "not nft owner");

        uint256 tokenID = u.token_id;
        IERC721 nftToken = IERC721(u.NFT_address);
        nftToken.safeTransferFrom(address(this),msgSender(), tokenID);


        u.user_id = address(0);
        u.NFT_address = address(0);
        u.token_id =0;

        delete nicknames[u.nickname];

        emit WithdrawNFT(msgSender(), address(nftToken), tokenID, block.timestamp);

        return true;
    }

}