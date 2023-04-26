// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ITokenUriResolver} from "../ITokenUriResolver.sol";
import {IKODAV3} from "../../core/IKODAV3.sol";

contract SingleEditionStaticTokenIdResolver is ITokenUriResolver {
    using Strings for uint256;

    string baseStorageHash;
    string joiner;
    string extension;

    function tokenURI(uint256, uint256 _tokenId) external override view returns (string memory) {
        // {baseStorageHash}{joiner}{tokenId} e.g. ipfs://ipfs/Qmd9xQFBfqMZLG7RA2rXor7SA7qyJ1Pk2F2mSYzRQ2siMv/1234
        return string(abi.encodePacked(baseStorageHash, joiner, _tokenId.toString()));
    }

    function isDefined(uint256, uint256) external override view returns (bool) {
        return true;
    }
}
