// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../IFundsHandler.sol";
import "../IFundsDrainable.sol";

/**
 * Allows funds to be split using a pull pattern, holding a balance until drained
 */

// FIXME use a single contract as a registry for splits rather than one per collab split
contract FundsReceiver is IFundsHandler, IFundsDrainable {

    bool private _notEntered = true;

    /** @dev Prevents a contract from calling itself, directly or indirectly. */
    modifier nonReentrant() {
        require(_notEntered, "ReentrancyGuard: reentrant call");
        _notEntered = false;
        _;
        _notEntered = true;
    }

    bool private locked;
    address[] public recipients;
    uint256[] public splits;

    /**
     * @notice Using a minimal proxy contract pattern initialises the contract and sets delegation
     * @dev initialises the FundsReceiver (see https://eips.ethereum.org/EIPS/eip-1167)
     */
    function init(address[] calldata _recipients, uint256[] calldata _splits) override external {
        require(!locked, "contract locked sorry");
        locked = true;
        recipients = _recipients;
        splits = _splits;
    }

    // accept all funds
    receive() external payable {}

    function drain() nonReentrant public override {

        // accept funds
        uint256 balance = address(this).balance;
        uint256 singleUnitOfValue = balance / 100000;

        // split according to total
        for (uint256 i = 0; i < recipients.length; i++) {

            // Work out split
            uint256 share = singleUnitOfValue * splits[i];

            // Assumed all recipients are EOA and not contracts atm
            // Fire split to recipient

            // TODO how to handle failures ... call and validate?
            //      - if fails to accept the money, ideally we remove them from the list ...
            payable(recipients[i]).transfer(share);
        }
    }

    function totalRecipients() public override virtual view returns (uint256) {
        return recipients.length;
    }

    function royaltyAtIndex(uint256 _index) public override view returns (address recipient, uint256 split) {
        recipient = recipients[_index];
        split = splits[_index];
    }
}
