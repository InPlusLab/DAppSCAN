// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IERC2981} from "../core/IERC2981.sol";
import {ERC165} from "@openzeppelin/contracts/utils/introspection/ERC165.sol";

// N:B: Mock contract for testing purposes only
contract MockRoyaltiesRegistry is ERC165, IERC2981 {

    /// @notice precision 100.00000%
    uint256 public modulo = 100_00000;

    struct Royalty {
        address receiver;
        uint256 amount;
    }

    mapping(uint256 => Royalty) overrides;

    function royaltyInfo(
        uint256 _tokenId,
        uint256 _value
    ) external override view returns (
        address _receiver,
        uint256 _royaltyAmount
    ) {
        return (overrides[_tokenId].receiver, (_value / modulo) * overrides[_tokenId].amount);
    }

    function getRoyaltiesReceiver(uint256 _editionId) external override view returns (address) {
        return overrides[_editionId].receiver;
    }

    function hasRoyalties(uint256 _tokenId) external override view returns (bool) {
        return overrides[_tokenId].amount > 0;
    }

    function setupRoyalty(uint256 _tokenId, address _receiver, uint256 _amount) public {
        overrides[_tokenId] = Royalty(_receiver, _amount);
    }
}
