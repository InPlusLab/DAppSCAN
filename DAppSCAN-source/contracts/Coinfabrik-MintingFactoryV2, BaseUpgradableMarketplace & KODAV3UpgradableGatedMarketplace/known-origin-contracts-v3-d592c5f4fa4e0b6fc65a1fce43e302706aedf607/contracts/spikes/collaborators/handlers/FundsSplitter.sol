// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import "../IFundsHandler.sol";

/**
 * splits all funds as soon as the contract receives it
 */
contract FundsSplitter is IFundsHandler {

    bool private locked;

    uint256 constant SCALE = 100000;

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

    // TODO test GAS limit problems ... ? call vs transfer 21000 limits?

    // accept all funds
    receive() external payable {

        // accept funds
        uint256 balance = msg.value;
        uint256 singleUnitOfValue = balance / SCALE;

        // split according to total
        for (uint256 i = 0; i < recipients.length; i++) {

            // Work out split
            uint256 share = singleUnitOfValue * splits[i];

            // TODO assumed all recipients are EOA and not contracts ... ?
            // AMG: would it be a problem if a contract? Doubt it?

            // Fire split to recipient
            payable(recipients[i]).transfer(share);
        }
    }

    // Enumerable by something else

    function totalRecipients() public override view returns (uint256) {
        return recipients.length;
    }

    function royaltyAtIndex(uint256 _index) public override view returns (address recipient, uint256 split) {
        recipient = recipients[_index];
        split = splits[_index];
    }
}
