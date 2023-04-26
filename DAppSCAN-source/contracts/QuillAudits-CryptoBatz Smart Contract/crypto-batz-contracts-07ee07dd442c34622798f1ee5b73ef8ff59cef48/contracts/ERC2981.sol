// SPDX-License-Identifier: MIT
pragma solidity ^0.8.8;

import "@openzeppelin/contracts/utils/introspection/ERC165.sol";
import "./IERC2981.sol";

/// @dev This is a contract used to add ERC2981 support to ERC721 and 1155
contract ERC2981 is ERC165, IERC2981 {
  struct RoyaltyInfo {
    address recipient;
    uint24 amount;
  }

  RoyaltyInfo private _royalties;

  /// @dev Sets token royalties
  /// @param recipient recipient of the royalties
  /// @param value percentage (using 2 decimals - 10000 = 100, 0 = 0)
  function _setRoyalties(address recipient, uint256 value) internal {
    require(value <= 10000, "ERC2981Royalties: Too high");
    _royalties = RoyaltyInfo(recipient, uint24(value));
  }

  /// @inheritdoc	IERC2981
  function royaltyInfo(uint256, uint256 value)
    external
    view
    override
    returns (address receiver, uint256 royaltyAmount)
  {
    RoyaltyInfo memory royalties = _royalties;
    receiver = royalties.recipient;
    royaltyAmount = (value * royalties.amount) / 10000;
  }

  /// @inheritdoc	ERC165
  function supportsInterface(bytes4 interfaceId)
    public
    view
    virtual
    override
    returns (bool)
  {
    return
      interfaceId == type(IERC2981).interfaceId ||
      super.supportsInterface(interfaceId);
  }
}
