// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "@openzeppelin/contracts/utils/Context.sol";
import "../../access/KOAccessControls.sol";
import "../../core/IKODAV3.sol";
import "../../programmable/ITokenUriResolver.sol";

contract TokenUriResolverRegistry is ITokenUriResolver, Context {

    KOAccessControls public accessControls;

    mapping(uint256 => ITokenUriResolver) editionIdOverrides;

    constructor(KOAccessControls _accessControls) {
        accessControls = _accessControls;
    }

    function tokenURI(uint256 _editionId, uint256 _tokenId) external override view returns (string memory) {
        return editionIdOverrides[_editionId].tokenURI(_editionId, _tokenId);
    }

    function isDefined(uint256 _editionId, uint256 _tokenId) external override view returns (bool) {
        return editionIdOverrides[_editionId] != ITokenUriResolver(address(0));
    }
}
