// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./FountainBase.sol";

/// @title Staking vault of lpTokens
abstract contract HarvestPermit is FountainBase {
    using Counters for Counters.Counter;

    mapping(address => mapping(address => uint256)) private _timeLimits;
    // SWC-119-Shadowing State Variables: L13
    mapping(address => Counters.Counter) private _nonces;

    // solhint-disable-next-line var-name-mixedcase
    bytes32 private immutable _HARVEST_PERMIT_TYPEHASH =
        keccak256(
            "HarvestPermit(address owner,address sender,uint256 timeLimit,uint256 nonce,uint256 deadline)"
        );

    /**
     *  @dev Emitted when the time limit of a `sender` for an `owner` is set by
     * a call to {approve}. `timeLimit` is the new time limit.
     */
    event HarvestApproval(
        address indexed owner,
        address indexed sender,
        uint256 timeLimit
    );

    /// @notice Examine if the time limit is not expired.
    modifier canHarvestFrom(address owner) {
        _requireMsg(
            block.timestamp <= _timeLimits[owner][_msgSender()],
            "general",
            "harvest not allowed"
        );
        _;
    }

    // Getter
    /// @notice Return the time limit owner approved to the sender.
    /// @param owner The owner address.
    /// @param sender The sender address.
    /// @return The time limit.
    function harvestTimeLimit(address owner, address sender)
        public
        view
        returns (uint256)
    {
        return _timeLimits[owner][sender];
    }

    /// @notice Approve sender to harvest before timeLimit.
    /// @param sender The sender address.
    /// @param timeLimit The time limit to be approved.
    function harvestApprove(address sender, uint256 timeLimit)
        external
        returns (bool)
    {
        _harvestApprove(_msgSender(), sender, timeLimit);
        return true;
    }

    /// @notice Approve sender to harvest for owner before timeLimit.
    /// @param owner The owner address.
    /// @param sender The sender address.
    /// @param timeLimit The time limit to be approved.
    /// @param deadline The permit available deadline.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function harvestPermit(
        address owner,
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
            "harvestPermit",
            "expired deadline"
        );

        bytes32 structHash =
            keccak256(
                abi.encode(
                    _HARVEST_PERMIT_TYPEHASH,
                    owner,
                    sender,
                    timeLimit,
                    _nonces[owner].current(),
                    deadline
                )
            );

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        _requireMsg(signer == owner, "harvestPermit", "invalid signature");

        _nonces[owner].increment();
        _harvestApprove(owner, sender, timeLimit);
    }

    function harvestNonces(address owner) public view returns (uint256) {
        return _nonces[owner].current();
    }

    /// @notice User may harvest from any angel for permitted user.
    /// @param angel The angel address.
    /// @param from The owner address.
    /// @param to The recipient address.
    function harvestFrom(
        IAngel angel,
        address from,
        address to
    ) public canHarvestFrom(from) {
        _harvestAngel(angel, from, to);
        emit Harvest(from);
    }

    /// @notice User may harvest from all the joined angels for permitted user.
    /// @param from The owner address.
    /// @param to The recipient address.
    function harvestAllFrom(address from, address to)
        public
        canHarvestFrom(from)
    {
        IAngel[] memory angels = joinedAngel(from);
        for (uint256 i = 0; i < angels.length; i++) {
            IAngel angel = angels[i];
            _harvestAngel(angel, from, to);
        }
        emit Harvest(from);
    }

    /// @notice Perform harvestFrom after permit.
    /// @param angel The angel address.
    /// @param from The owner address.
    /// @param to The recipient address.
    /// @param timeLimit The time limit to be approved.
    /// @param deadline The permit available deadline.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function harvestFromWithPermit(
        IAngel angel,
        address from,
        address to,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        harvestPermit(from, _msgSender(), timeLimit, deadline, v, r, s);
        harvestFrom(angel, from, to);
    }

    /// @notice Perform harvestAllFrom after permit.
    /// @param from The owner address.
    /// @param to The recipient address.
    /// @param timeLimit The time limit to be approved.
    /// @param deadline The permit available deadline.
    /// @param v Signature v.
    /// @param r Signature r.
    /// @param s Signature s.
    function harvestAllFromWithPermit(
        address from,
        address to,
        uint256 timeLimit,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        harvestPermit(from, _msgSender(), timeLimit, deadline, v, r, s);
        harvestAllFrom(from, to);
    }

    function _harvestApprove(
        address owner,
        address sender,
        uint256 timeLimit
    ) internal {
        _requireMsg(
            owner != address(0),
            "_harvestApprove",
            "approve from the zero address"
        );
        _requireMsg(
            sender != address(0),
            "_harvestApprove",
            "approve to the zero address"
        );

        _timeLimits[owner][sender] = timeLimit;
        emit HarvestApproval(owner, sender, timeLimit);
    }
}
