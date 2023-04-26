// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";
import {ITokenUriResolver} from "./ITokenUriResolver.sol";
import {IKODAV3} from "../core/IKODAV3.sol";

contract TokenUriResolverRegistry is ITokenUriResolver {

    IKODAV3 public koda;
    IKOAccessControlsLookup public accessControls;

    mapping(uint256 => ITokenUriResolver) public editionIdOverrides;

    constructor(IKOAccessControlsLookup _accessControls, IKODAV3 _koda) {
        koda = _koda;
        accessControls = _accessControls;
    }

    // TODO CRUD resolver methods
    // TODO admin requirements?
    // TODO setter methods for contract and admin
    // TODO free flags i.e. once set cannot be undone (is their a universal event for this?)
    // TODO upgradable
    // TODO events

    function tokenURI(uint256 _editionId, uint256 _tokenId) external override view returns (string memory) {
        return editionIdOverrides[_editionId].tokenURI(_editionId, _tokenId);
    }

    function isDefined(uint256 _editionId, uint256 _tokenId) external override view returns (bool) {
        return editionIdOverrides[_editionId] != ITokenUriResolver(address(0));
    }
}
