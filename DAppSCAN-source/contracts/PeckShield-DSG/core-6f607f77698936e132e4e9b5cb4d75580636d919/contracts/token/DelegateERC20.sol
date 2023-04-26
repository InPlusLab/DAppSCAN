// SPDX-License-Identifier: MIT
pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";

abstract contract DelegateERC20 is ERC20 {
    // A record of each accounts delegate
    mapping(address => address) internal _delegates;
    uint256 public totalBurned;

    // A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    // A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    // The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    // The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    // The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address delegate_,uint256 nonce,uint256 expiry)");

    // A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    // support delegates mint
    function _mint(address account, uint256 amount) internal virtual override {
        super._mint(account, amount);

        // add delegates to the minter
        _moveDelegates(address(0), _delegates[account], amount);
    }

    function _burn(address account, uint256 amount) internal virtual override {
        super._burn(account, amount);

        _moveDelegates(_delegates[account], address(0), amount);
        totalBurned += amount;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override {
        super._transfer(sender, recipient, amount);
        _moveDelegates(_delegates[sender], _delegates[recipient], amount);
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegate_`
     * @param delegate_ The address to delegate votes to
     */
    function delegate(address delegate_) external {
        return _delegate(msg.sender, delegate_);
    }

    /**
     * @notice Delegates votes from signatory to `delegate_`
     * @param delegate_ The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegate_,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator =
        keccak256(abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name())), getChainId(), address(this)));

        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegate_, nonce, expiry));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "DSGToken::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "DSGToken::delegateBySig: invalid nonce");
        require(now <= expiry, "DSGToken::delegateBySig: signature expired");
        return _delegate(signatory, delegate_);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint256) {
        require(blockNumber < block.number, "DSGToken::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegate_) internal {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying balances (not scaled);
        _delegates[delegator] = delegate_;

        _moveDelegates(currentDelegate, delegate_, delegatorBalance);

        emit DelegateChanged(delegator, currentDelegate, delegate_);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegate_,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        uint32 blockNumber = safe32(block.number, "DSGToken::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegate_][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegate_][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegate_][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegate_] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegate_, oldVotes, newVotes);
    }

    function safe32(uint256 n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        return chainId;
    }

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
}