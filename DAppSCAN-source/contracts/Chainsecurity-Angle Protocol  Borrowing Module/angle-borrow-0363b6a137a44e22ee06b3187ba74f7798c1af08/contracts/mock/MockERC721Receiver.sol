// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC721/utils/ERC721Holder.sol)

pragma solidity ^0.8.0;

/**
 * @dev Implementation of the {IERC721Receiver} interface.
 *
 * Accepts all token transfers.
 * Make sure the contract is able to use its token with {IERC721-safeTransferFrom}, {IERC721-approve} or {IERC721-setApprovalForAll}.
 */
contract MockERC721Receiver {
    uint256 public mode = 0;

    function setMode(uint256 _mode) public {
        mode = _mode;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public view returns (bytes4) {
        require(mode != 1, "0x1111111");
        if (mode == 2) return this.setMode.selector;
        return this.onERC721Received.selector;
    }
}
