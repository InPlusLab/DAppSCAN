// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./OwnableContract.sol";
import "./IBaseDoNFT.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract DoNFTFactory is OwnableContract{
    /**nftAddress => (gameKey => doNFT) */
    mapping(address => mapping(address => address)) vritualDoNftMap;
    mapping(address => address) wrapDoNftMap;
    mapping(address => address) doNftToNft;
    address private vritualDoNftImplementation;
    address private wrapDoNftImplementation;

    constructor(){
        
    }

    function createVritualDoNFT(address nftAddress,address gameKey,string calldata name, string calldata symbol) external returns(address) {
        require(IERC165(nftAddress).supportsInterface(type(IERC721).interfaceId),"no 721");
        require(vritualDoNftMap[nftAddress][gameKey] == address(0),"already create");
        address clone = Clones.clone(vritualDoNftImplementation);
        IBaseDoNFT(clone).init(nftAddress,name, symbol);
        vritualDoNftMap[nftAddress][gameKey] = clone;
        doNftToNft[clone] = nftAddress;
        return clone;
    }

    function createWrapDoNFT(address nftAddress,string calldata name, string calldata symbol) external returns(address) {
        require(IERC165(nftAddress).supportsInterface(type(IERC721).interfaceId),"no 721");
        require(wrapDoNftMap[nftAddress] == address(0),"already create");
        address clone = Clones.clone(wrapDoNftImplementation);
        IBaseDoNFT(clone).init(nftAddress,name, symbol);
        wrapDoNftMap[nftAddress] = clone;
        doNftToNft[clone] = nftAddress;
        return clone;
    }

    function setWrapDoNftImplementation(address imp) public onlyAdmin {
        wrapDoNftImplementation = imp;
    }

    function setVritualDoNftImplementation(address imp) public onlyAdmin {
        vritualDoNftImplementation = imp;
    }

    function getWrapDoNftImplementation() public view returns(address){
        return wrapDoNftImplementation;
    }

    function getVritualDoNftImplementation() public view returns(address) {
        return vritualDoNftImplementation;
    }

    function getWrapDoNftImplementation(address nftAddress) public view returns(address){
        return wrapDoNftMap[nftAddress];
    }

    function getVritualDoNftImplementation(address nftAddress,address gameKey) public view returns(address){
        return vritualDoNftMap[nftAddress][gameKey];
    }


}
