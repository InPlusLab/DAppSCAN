// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libs/SafeMath.sol";
import "./libs/ShibaBEP20.sol";
import "./interfaces/IMoneyPot.sol";

// SNovaToken with Governance.
contract SNovaToken is ShibaBEP20("ShibaNova share token sNova", "sNova") {
    using SafeMath for uint256;

    struct HolderInfo {
        uint256 avgTransactionBlock;
    }


    IMoneyPot public moneyPot;
    ShibaBEP20 public Nova;
    bool private _isNovaSetup = false;
    bool private _isMoneyPotSetup = false;

    uint256 public immutable SWAP_PENALTY_MAX_PERIOD ; // after 72h penalty of holding sNova. Swap penalty is at the minimum
    uint256 public immutable SWAP_PENALTY_MAX_PER_SNova ; // 30% => 1 sNova = 0.3 Nova

    mapping(address => HolderInfo) public holdersInfo;

    constructor (uint256 swapPenaltyMaxPeriod, uint256 swapPenaltyMaxPerSNova) public{
        SWAP_PENALTY_MAX_PERIOD = swapPenaltyMaxPeriod; // default 28800: after 24h penalty of holding sNova. Swap penalty is at the minimum
        SWAP_PENALTY_MAX_PER_SNova = swapPenaltyMaxPerSNova.mul(1e10); // default: 30, 30% => 1 sNova = 0.3 Nova
    }

    function setupNova(ShibaBEP20 _Nova) external onlyOwner {
        require(!_isNovaSetup);
        Nova = _Nova;
        _isNovaSetup = true;
    }

    function setupMoneyPot(IMoneyPot _moneyPot) external onlyOwner {
        require(!_isMoneyPotSetup);
        moneyPot = _moneyPot;
        _isMoneyPotSetup = true;
    }

    /* Calculate the penality for swapping sNova to Nova for a user.
       The penality decrease over time (by holding duration).
       From SWAP_PENALTY_MAX_PER_SNova % to 0% on SWAP_PENALTY_MAX_PERIOD
    */
    function getPenaltyPercent(address _holderAddress) public view returns (uint256){
        HolderInfo storage holderInfo = holdersInfo[_holderAddress];
        if(block.number >= holderInfo.avgTransactionBlock.add(SWAP_PENALTY_MAX_PERIOD)){
            return 0;
        }
        if(block.number == holderInfo.avgTransactionBlock){
            return SWAP_PENALTY_MAX_PER_SNova;
        }
        uint256 avgHoldingDuration = block.number.sub(holderInfo.avgTransactionBlock);
        return SWAP_PENALTY_MAX_PER_SNova.sub(
            SWAP_PENALTY_MAX_PER_SNova.mul(avgHoldingDuration).div(SWAP_PENALTY_MAX_PERIOD)
        );
    }

    /* Allow use to exchange (swap) their sNova to Nova */
    function swapToNova(uint256 _amount) external {
        require(_amount > 0, "amount 0");
        address _from = msg.sender;
        uint256 NovaAmount = _swapNovaAmount( _from, _amount);
        holdersInfo[_from].avgTransactionBlock = _getAvgTransactionBlock(_from, holdersInfo[_from], _amount, true);
        super._burn(_from, _amount);
        Nova.mint(_from, NovaAmount);

        if (address(moneyPot) != address(0)) {
            moneyPot.updateSNovaHolder(_from);
        }
    }

    /* @notice Preview swap return in Nova with _sNovaAmount by _holderAddress
    *  this function is used by front-end to show how much Nova will be retrieve if _holderAddress swap _sNovaAmount
    */
    function previewSwapNovaExpectedAmount(address _holderAddress, uint256 _sNovaAmount) external view returns (uint256 expectedNova){
        return _swapNovaAmount( _holderAddress, _sNovaAmount);
    }

    /* @notice Calculate the adjustment for a user if he want to swap _sNovaAmount to Nova */
    function _swapNovaAmount(address _holderAddress, uint256 _sNovaAmount) internal view returns (uint256 expectedNova){
        require(balanceOf(_holderAddress) >= _sNovaAmount, "Not enough sNova");
        uint256 penalty = getPenaltyPercent(_holderAddress);
        if(penalty == 0){
            return _sNovaAmount;
        }

        return _sNovaAmount.sub(_sNovaAmount.mul(penalty).div(1e12));
    }

    /* @notice Calculate average deposit/withdraw block for _holderAddress */
    function _getAvgTransactionBlock(address _holderAddress, HolderInfo storage holderInfo, uint256 _sNovaAmount, bool _onWithdraw) internal view returns (uint256){
        if (balanceOf(_holderAddress) == 0) {
            return block.number;
        }
        uint256 transactionBlockWeight;
        if (_onWithdraw) {
            if (balanceOf(_holderAddress) == _sNovaAmount) {
                return 0;
            }
            else {
                return holderInfo.avgTransactionBlock;
            }
        }
        else {
            transactionBlockWeight = (balanceOf(_holderAddress).mul(holderInfo.avgTransactionBlock).add(block.number.mul(_sNovaAmount)));
        }
        return transactionBlockWeight.div(balanceOf(_holderAddress).add(_sNovaAmount));
    }


    /// @notice Creates `_amount` token to `_to`.
    function mint(address _to, uint256 _amount) external virtual override onlyOwner {
        HolderInfo storage holder = holdersInfo[_to];
        holder.avgTransactionBlock = _getAvgTransactionBlock(_to, holder, _amount, false);
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);

        if (address(moneyPot) != address(0)) {
            moneyPot.updateSNovaHolder(_to);
        }
    }

    /// @dev overrides transfer function to meet tokenomics of SNova
    function _transfer(address _sender, address _recipient, uint256 _amount) internal virtual override {
        holdersInfo[_sender].avgTransactionBlock = _getAvgTransactionBlock(_sender, holdersInfo[_sender], _amount, true);
        if (_recipient == BURN_ADDRESS) {
            super._burn(_sender, _amount);
            if (address(moneyPot) != address(0)) {
                moneyPot.updateSNovaHolder(_sender);
            }
        } else {
            holdersInfo[_recipient].avgTransactionBlock = _getAvgTransactionBlock(_recipient, holdersInfo[_recipient], _amount, false);
            super._transfer(_sender, _recipient, _amount);

            if (address(moneyPot) != address(0)) {
                moneyPot.updateSNovaHolder(_sender);
                if (_sender != _recipient){
                    moneyPot.updateSNovaHolder(_recipient);
                }
            }
        }
    }

    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    /// @dev A record of each accounts delegate
    mapping(address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
    keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
    keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator)
    external
    view
    returns (address)
    {
        return _delegates[delegator];
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
    external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "Nova::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "Nova::delegateBySig: invalid nonce");
        require(now <= expiry, "Nova::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
    external
    view
    returns (uint256)
    {
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
    function getPriorVotes(address account, uint blockNumber)
    external
    view
    returns (uint256)
    {
        require(blockNumber < block.number, "Nova::getPriorVotes: not yet determined");

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
            uint32 center = upper - (upper - lower) / 2;
            // ceil, avoiding overflow
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

    function _delegate(address delegator, address delegatee)
    internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator);
        // balance of underlying Novas (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
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
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
    internal
    {
        uint32 blockNumber = safe32(block.number, "Nova::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2 ** 32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly {chainId := chainid()}
        return chainId;
    }
}