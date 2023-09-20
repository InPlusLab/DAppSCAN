// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Address.sol";
import "./Context.sol";
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./IERC165.sol";
import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./ERC721Holder.sol";


contract TestMarket is ERC721Holder, Ownable {
    using Address for address;
    using SafeERC20 for IERC20;


    struct Offer {
        bool status;
        address seller;
        uint256 tokenId;
        uint256 category;
        uint256 amount;
        uint256 tokenIndex;
        uint256 offerId;
    }

    mapping(uint256 => uint256) private tokenOffer;

    mapping(uint256 => Offer) private _offers;

    mapping(address => uint256[]) private tokensIdsOnSell;

    uint256 private _lastOfferID = 0;

    IERC20 private ERC20Contract;

    IERC721 private nftContract;

    address private _feeWallet;

    uint256 private _exchangeRate;

    uint256 private _fee;

    address private _verifier;

    mapping(uint256 => bool) private usedNonces;

    event NewOffer(address indexed wallet, uint256 _id, uint256 tokenId, uint256 category, uint256 amount);

    event OfferCancelled(uint256 _id, uint256 tokenId);

    event OfferChanged(uint256 _id, uint256 tokenId, uint256 amount);

    event OfferClosed(address indexed buyer, uint256 _id, uint256 tokenId);


    constructor (address cOwner, address verifier) Ownable(cOwner) {
        _feeWallet = owner();
        _verifier = verifier;
        _fee = 10;
    }

    function setERC20Contract(address _account) public onlyOwner {
        ERC20Contract = IERC20(_account);
    }

    function setNFTContract(address _account) public onlyOwner {
        nftContract = IERC721(_account);
    }


    function setExchangeRate(uint256 _newrate) public onlyOwner {
        _exchangeRate = _newrate;
    }


    function setFee(uint256 _newfee) public onlyOwner {
        _fee = _newfee;
    }

    function getOfferByToken(uint256 _tokenId) external view returns(Offer memory) {        
        return _offers[tokenOffer[_tokenId]];
    }

    function getOffer(uint256 tokenId) external view returns(uint256) {
        return tokenOffer[tokenId];
    }

    function placeBid(uint256 _tokenId, uint256 _price, uint256 nonce, bytes memory sig) public {
        require(!usedNonces[nonce]);
        bytes32 message = prefixed(keccak256(abi.encodePacked(_tokenId, _price, nonce, address(this))));
        address signer = recoverSigner(message, sig);
        require(signer ==_verifier, "Unauthorized transaction");
        usedNonces[nonce] = true;

        require(nftContract._isApprovedOrOwner(address(this), _tokenId), "Token is not approved for marketplace");
        require(_price > 0, "Zero price prohibited");
        uint256 categoryToken = nftContract.getTokenCategory(_tokenId);
        uint256 amount = _price * _exchangeRate;
        nftContract.transferFrom(_msgSender(), address(this), _tokenId);
        uint256 tokenIndex = addTokenIndex(_msgSender(), _tokenId);
        _lastOfferID += 1;
        Offer memory offer = Offer({
                                    status: true,
                                    seller: _msgSender(),
                                    tokenId: _tokenId,
                                    category: categoryToken,
                                    amount: amount,
                                    tokenIndex: tokenIndex,
                                    offerId: _lastOfferID
                                });
        _offers[_lastOfferID] = offer;
        tokenOffer[_tokenId] = _lastOfferID;
        emit NewOffer(_msgSender(), _lastOfferID, _tokenId, categoryToken, amount);
    }

    function addTokenIndex(address _seller, uint256 _tokenId) private returns(uint256) {
        tokensIdsOnSell[_seller].push(_tokenId);
        uint256 tokenIndex = tokensIdsOnSell[_seller].length - 1;
        return tokenIndex;
    }

    function removeTokenIndex(address _seller, uint256 index) private {
        for (uint256 i = index; i < tokensIdsOnSell[_seller].length - 1; i++) {
            tokensIdsOnSell[_seller][i] = tokensIdsOnSell[_seller][i+1];
        }
        tokensIdsOnSell[_seller].pop();
    }

    function cancelOffer(uint256 _offerId) public {
        require(_offers[_offerId].status, "This offer is not active");
        require(_offers[_offerId].seller == _msgSender(), "You cannot close offer's that are not yours");
        nftContract.safeTransferFrom(address(this), _msgSender(), _offers[_offerId].tokenId);
        emit OfferCancelled(_offerId, _offers[_offerId].tokenId);
        removeTokenIndex(_offers[_offerId].seller, _offers[_offerId].tokenIndex);
        uint256 tokenId = _offers[_offerId].tokenId;
        delete tokenOffer[tokenId];
        delete _offers[_offerId];
    }

    function getSellTokensIds(address _seller) external view returns(uint256[] memory) {
        return tokensIdsOnSell[_seller];       
    }

    function getCostOffer(uint256 _offerId) external view returns(uint256) {
        require(_offers[_offerId].status, "This offer is not active");
        return _offers[_offerId].amount;
    }

    function buyToken(uint256 _offerId) public  {
        require(_offers[_offerId].status, "This offer is not active");
        uint256 commissionAmount = _offers[_offerId].amount / 100 * _fee;

        require(ERC20Contract.balanceOf(_msgSender()) >= _offers[_offerId].amount,"Insufficient ERC20 tokens amount to buy");
        require(ERC20Contract.allowance(_msgSender(), address(this)) >= _offers[_offerId].amount, "Amount is not allowed by ERC20 holder");
        nftContract.safeTransferToken(_msgSender(), _offers[_offerId].seller, _offers[_offerId].tokenId, _offers[_offerId].category);
        ERC20Contract.safeTransferFrom(_msgSender(), _offers[_offerId].seller, _offers[_offerId].amount - commissionAmount);
        ERC20Contract.safeTransferFrom(_msgSender(), _feeWallet, commissionAmount);
        emit OfferClosed(_msgSender(), _offerId, _offers[_offerId].tokenId);
        removeTokenIndex(_offers[_offerId].seller, _offers[_offerId].tokenIndex);
        delete tokenOffer[_offers[_offerId].tokenId];
        delete _offers[_offerId];
    }

    function recoverSigner(bytes32 message, bytes memory sig) public pure
    returns (address)
    {
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = splitSignature(sig);

        return ecrecover(message, v, r, s);
    }

    function splitSignature(bytes memory sig)
    public
    pure
    returns (uint8, bytes32, bytes32)
    {
        require(sig.length == 65);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    // Builds a prefixed hash to mimic the behavior of eth_sign.
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

}
