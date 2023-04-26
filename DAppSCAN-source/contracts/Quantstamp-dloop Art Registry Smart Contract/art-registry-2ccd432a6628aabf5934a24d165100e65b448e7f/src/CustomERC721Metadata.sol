pragma solidity 0.5.17;

import "openzeppelin-solidity/contracts/token/ERC721/ERC721.sol";
import "openzeppelin-solidity/contracts/introspection/ERC165.sol";

// @dev Removed the IERC721Metadata interface. solidity-coverage had issues.
contract CustomERC721Metadata is ERC165, ERC721 {
    string private _name;
    string private _symbol;
    string private _baseURI;

    /*
    * bytes4(keccak256('name()')) == 0x06fdde03
    * bytes4(keccak256('symbol()')) == 0x95d89b41
    * bytes4(keccak256('tokenURI(uint256)')) == 0xc87b56dd
    *
    * => 0x06fdde03 ^ 0x95d89b41 ^ 0xc87b56dd == 0x5b5e139f
    */
    bytes4 private constant _INTERFACE_ID_ERC721_METADATA = 0x5b5e139f;

    event BaseURISet(string baseURI);

    /**
    * @dev Constructor function
    */
    constructor(string memory name, string memory symbol, string memory baseURI)
        public
    {
        _name = name;
        _symbol = symbol;
        _baseURI = baseURI;

        // register the supported interfaces to conform to ERC721 via ERC165
        _registerInterface(_INTERFACE_ID_ERC721_METADATA);
    }

    function _setBaseURI(string memory baseURI) internal {
        _baseURI = baseURI;
        emit BaseURISet(baseURI);
    }

    /**
    * @dev Gets the token name.
    * @return string representing the token name
    */
    function name() external view returns (string memory) {
        return _name;
    }

    /**
    * @dev Gets the token symbol.
    * @return string representing the token symbol
    */
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    function getBaseURI() external view returns (string memory) {
        return _baseURI;
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        require(_exists(tokenId), "tokenId does not exist");
        return string(abi.encodePacked(_baseURI, uint2str(tokenId)));
    }

    // Helper function from Oraclize
    // https://github.com/oraclize/ethereum-api/blob/master/oraclizeAPI_0.5.sol
    function uint2str(uint256 inp) internal pure returns (string memory) {
        if (inp == 0) return "0";
        uint256 i = inp;
        uint256 j = i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length - 1;
        while (i != 0) {
            bstr[k--] = bytes1(uint8(48 + (i % 10)));
            i /= 10;
        }
        return string(bstr);
    }
}
