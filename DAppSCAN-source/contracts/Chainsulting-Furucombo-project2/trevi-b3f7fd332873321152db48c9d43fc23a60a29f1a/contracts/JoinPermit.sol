// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./FountainBase.sol";

/// @title Staking vault of lpTokens
abstract contract JoinPermit is FountainBase {
    using Counters for Counters.Counter;

    mapping(address => mapping(address => uint256)) private _timeLimits;
    // SWC-119-Shadowing State Variables: L13
    mapping(address => Counters.Counter) private _nonces;

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private immutable _JOIN_PERMIT_TYPEHASH =
        keccak256(
            "JoinPermit(address user,address sender,uint256 timeLimit,uint256 nonce,uint256 deadline)"
        );

    /**
     *  @dev Emitted when the time limit of a `sender` for an `user` is set by
     * a call to {approve}. `timeLimit` is the new time limit.
     */
    event JoinApproval(
        address indexed user,
        address indexed sender,
        uint256 timeLimit
    );

    /// @notice Examine if the time limit is not expired.
    modifier canJoinFor(address user) {
        _requireMsg(
            block.timestamp <= _timeLimits[user][_msgSender()],
            "general",
            "join not allowed"
        );
        _;
    }

    // Getter
    /// @notice Return the time limit user approved to the sender.
    /// @param user The user address.
    /// @param sender The sender address.
    /// @return The time limit.
    function joinTimeLimit(address user, address sender)
        public
        view
        returns (uint256)
    {
        return _timeLimits[user][sender];
    }

    /// @notice Approve sender to join before timeLimit.
    /// @param sender The sender address.
    /// @param timeLimit The time limit to be approved.
    function joinApprove(address sender, uint256 timeLimit)
        external
        returns (bool)
    {
        _joinApprove(_msgSender(), sender, timeLimit);
        return true;
    }

    /// @notice Approve sender to join for user before timeLimit.
    /// @param user The user address.
    /// @param sender The sender address.
    /// @param timeLimit The time limit to be approved.
    /// @param deadline The permit available deadline.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function joinPermit(
        address user,
        address sender,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        // solhint-disable-next-line not-rely-on-time
        _requireMsg(
            block.timestamp <= deadline,
            "joinPermit",
            "expired deadline"
        );

        bytes32 structHash =
            keccak256(
                abi.encode(
                    _JOIN_PERMIT_TYPEHASH,
                    user,
                    sender,
                    timeLimit,
                    _nonces[user].current(),
                    deadline
                )
            );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        _requireMsg(signer == user, "joinPermit", "invalid signature");

        _nonces[user].increment();
        _joinApprove(user, sender, timeLimit);
    }

    function joinNonces(address user) public view returns (uint256) {
        return _nonces[user].current();
    }

    /// @notice User may join angel for permitted user.
    /// @param angel The angel address.
    /// @param user The user address.
    function joinAngelFor(IAngel angel, address user) public canJoinFor(user) {
        _joinAngel(angel, user);
    }

    /// @notice User may join angels for permitted user.
    /// @param angels The angel addresses.
    /// @param user The user address.
    function joinAngelsFor(IAngel[] memory angels, address user)
        public
        canJoinFor(user)
    {
        for (uint256 i = 0; i < angels.length; i++) {
            _joinAngel(angels[i], user);
        }
    }

    /// @notice Perform joinFor after permit.
    /// @param angel The angel address.
    /// @param user The user address.
    /// @param timeLimit The time limit to be approved. Will set to current
    /// time if set as 1 (for one time usage)
    /// @param deadline The permit available deadline.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function joinAngelForWithPermit(
        IAngel angel,
        address user,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        joinPermit(user, _msgSender(), timeLimit, deadline, v, r, s);
        joinAngelFor(angel, user);
    }

    /// @notice Perform joinForMany after permit.
    /// @param angels The angel addresses.
    /// @param user The user address.
    /// @param timeLimit The time limit to be approved. Will set to current
    /// time if set as 1 (for one time usage)
    /// @param deadline The permit available deadline.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function joinAngelsForWithPermit(
        IAngel[] calldata angels,
        address user,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        joinPermit(user, _msgSender(), timeLimit, deadline, v, r, s);
        joinAngelsFor(angels, user);
    }

    function _joinApprove(
        address user,
        address sender,
        uint256 timeLimit
    ) internal {
        _requireMsg(
            user != address(0),
            "_joinApprove",
            "approve from the zero address"
        );
        _requireMsg(
            sender != address(0),
            "_joinApprove",
            "approve to the zero address"
        );

        if (timeLimit == 1) timeLimit = block.timestamp;
        _timeLimits[user][sender] = timeLimit;
        emit JoinApproval(user, sender, timeLimit);
    }
}
