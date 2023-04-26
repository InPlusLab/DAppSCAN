// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../libraries/Random.sol";

import "../interfaces/IDataStorage.sol";
import "../libraries/NFTLib.sol";

contract DroidBot is ERC721Burnable, Ownable
{
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private minters;
    uint256 totalSupply;
    mapping (uint256 => NFTLib.Info) public nftInfo;
    string baseURI;

    /*----------------------------CONSTRUCTOR----------------------------*/
    constructor(string memory _URI) ERC721("DroidBot NFT Token", "DBOT")
    {
        baseURI = _URI;
    }

    function _baseURI() internal view override returns(string memory) {
        return baseURI;
    }

    /*----------------------------EXTERNAL FUNCTIONS----------------------------*/
    function create(address _receiver, uint256 _lv, uint256 _power) external onlyMinter returns(uint256 _tokenId) {
        require(_receiver != address(0), 'DroidBotNFT: _receiver is the zero address');
        totalSupply++;
        _tokenId = totalSupply;
       _mint(_receiver, _tokenId);
        nftInfo[_tokenId] = NFTLib.Info({
            level : _lv,
            power : _power
        });
        emit DroidBotCreated(_receiver, _tokenId, _lv, _power);
    }

    function upgrade(uint256 _id, uint256 _lv, uint256 _power) external onlyMinter {
        NFTLib.Info storage _token = nftInfo[_id];
        _token.level = _lv;
        _token.power = _power;
        emit DroidBotUpgraded(_id, _lv, _power);
    }

    function info(uint256 _id) external view returns (NFTLib.Info memory) {
        return nftInfo[_id];
    }

    function power(uint256 _id) external view returns(uint256) {
        return nftInfo[_id].power;
    }

    function level(uint256 _id) external view returns(uint256) {
        return nftInfo[_id].level;
    }

    /*----------------------------RESTRICT FUNCTIONS----------------------------*/

    function addMinter(address _addMinter) external onlyOwner returns (bool) {
        require(_addMinter != address(0), "Token: _addMinter is the zero address");
        return EnumerableSet.add(minters, _addMinter);
    }

    function delMinter(address _delMinter) external onlyOwner returns (bool) {
        require(_delMinter != address(0), "Token: _delMinter is the zero address");
        return EnumerableSet.remove(minters, _delMinter);
    }

    function getMinterLength() public view returns (uint256) {
        return EnumerableSet.length(minters);
    }

    function isMinter(address account) public view returns (bool) {
        return EnumerableSet.contains(minters, account);
    }

    function getMinter(uint256 _index) external view onlyOwner returns (address) {
        require(_index <= getMinterLength() - 1, "Token: index out of bounds");
        return EnumerableSet.at(minters, _index);
    }
    // modifier for mint function
    modifier onlyMinter() {
        require(isMinter(msg.sender), "caller is not the minter");
        _;
    }

    /*----------------------------EVENTS----------------------------*/
    event DroidBotCreated(address indexed receiver, uint256 indexed id, uint256 level, uint256 power);
    event DroidBotEvolved(address indexed receiver, uint256 newDroidBotLevel, uint256 droid0Level, uint256 droid1Level, uint256 indexed newDroidBotId, uint256 newDroidBotPower);
    event DroidBotUpgraded(uint256 indexed tokenId, uint256 newLv, uint256 newPower);
}
