// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IARTH} from './IARTH.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {AccessControl} from '../access/AccessControl.sol';

contract ArthBridge is AccessControl {
    using SafeMath for uint256;

    /**
     * State variables.
     */

    /// @dev Bridge token.
    IARTH private ARTH;

    address public ownerAddress;
    address public timelockAddress;
    uint256 public cumulativeDeposits;
    uint256 public cumulativeWithdrawals;

    /**
     * Events.
     */
    event receivedDeposit(uint256 chainId, string to, uint256 amountD18);

    /**
     * Modifiers.
     */

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == timelockAddress || msg.sender == ownerAddress,
            'ARTHBridge: FORBIDDEN'
        );
        _;
    }

    /**
     * Constructor.
     */

    constructor(
        address _arthContractAddress,
        address _creatorAddress,
        address _timelockAddress
    ) {
        ownerAddress = _creatorAddress;
        ARTH = IARTH(_arthContractAddress);
        timelockAddress = _timelockAddress;

        _setupRole(DEFAULT_ADMIN_ROLE, ownerAddress);
    }

    /**
     * Public.
     */

    /// @notice Needed for compatibility to use poolMint()
    function getCollateralGMUBalance() public pure returns (uint256) {
        return 0;
    }

    function depositArth(
        uint256 chainId,
        string memory to,
        uint256 amountD18
    ) external {
        ARTH.transferFrom(msg.sender, address(this), amountD18);

        cumulativeDeposits = cumulativeDeposits.add(amountD18);

        ARTH.poolBurnFrom(address(this), amountD18);
        emit receivedDeposit(chainId, to, amountD18);
    }

    function withdrawArth(address _to, uint256 amountD18)
        external
        onlyByOwnerOrGovernance
    {
        cumulativeWithdrawals = cumulativeWithdrawals.add(amountD18);

        ARTH.poolMint(_to, amountD18);
    }
}
