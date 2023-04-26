// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./interfaces/IMerkleDistributor.sol";
import "./interfaces/IGovernance.sol";
import "./lib/AccessControlEnumerable.sol";
import "./lib/MerkleProof.sol";
import "./lib/ERC721Enumerable.sol";

/**
 * @title MerkleDistributor
 * @dev Distributes rewards to block producers in the network. NFT serves as proof of distribution.
 */
contract MerkleDistributor is IMerkleDistributor, AccessControlEnumerable, ERC721Enumerable {

    /// @notice Role allowing the merkle root to be updated
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    /// @notice Role to slash earned rewards
    bytes32 public constant SLASHER_ROLE = keccak256("SLASHER_ROLE");

    /// @notice Role to distribute rewards to accounts
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @notice Token distributed by this contract
    IERC20Mintable public immutable override token;

    /// @notice Root of a merkle tree containing total earned amounts
    bytes32 public override merkleRoot;

    /// @notice Total number of distributions, also token id of the current distribution
    uint256 public override distributionCount;

    /// @notice Number of votes from updaters needed to apply a new root
    uint256 public updateThreshold;

    /// @notice Governance address
    address public governance;

    /// @notice Properties of each account -- totalEarned is stored in merkle tree
    struct AccountState {
        uint256 totalClaimed;
        uint256 totalSlashed;
    }

    /// @notice Account state
    mapping(address => AccountState) public override accountState;

    /// @notice Historical merkle roots
    mapping(bytes32 => bool) public override previousMerkleRoot;

    /// @dev Path to distribution metadata (including proofs)
    mapping(uint256 => string) private _tokenURI;

    /// @dev Votes for a new merkle root
    mapping(bytes32 => uint256) private _updateVotes;

    /// @dev Vote for new merkle root for each distribution
    mapping(address => mapping(uint256 => bytes32)) private _updaterVotes;

    /// @dev Modifier to restrict functions to only updaters
    modifier onlyUpdaters() {
        require(hasRole(UPDATER_ROLE, msg.sender), "MerkleDistributor: Caller must have UPDATER_ROLE");
        _;
    }

    /// @dev Modifier to restrict functions to only slashers
    modifier onlySlashers() {
        require(hasRole(SLASHER_ROLE, msg.sender), "MerkleDistributor: Caller must have SLASHER_ROLE");
        _;
    }

    /// @dev Modifier to restrict functions to only admins
    modifier onlyAdmins() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "MerkleDistributor: Caller must have DEFAULT_ADMIN_ROLE");
        _;
    }

    /**
     * @notice Create new MerkleDistributor
     * @param _token Token address
     * @param _governance Governance address
     * @param _admin Admin address
     * @param _updateThreshold Number of updaters required to update
     * @param _updaters Initial updaters
     * @param _slashers Initial slashers
     */
    constructor(
        IERC20Mintable _token, 
        address _governance, 
        address _admin, 
        uint8 _updateThreshold,
        address[] memory _updaters, 
        address[] memory _slashers
    ) ERC721("Eden Network Distribution", "EDEND") {
        token = _token;
        previousMerkleRoot[merkleRoot] = true;

        _setGovernance(_governance);

        for(uint i; i< _updaters.length; i++) {
            _setupRole(UPDATER_ROLE, _updaters[i]);
        }

        _setUpdateThreshold(_updateThreshold);

        for(uint i; i< _slashers.length; i++) {
            _setupRole(SLASHER_ROLE, _slashers[i]);
        }

        _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    /**
     * @notice Change the governance address
     * @dev The caller must have the `DEFAULT_ADMIN_ROLE`
     * @param to New governance address
     */
    function setGovernance(address to) onlyAdmins external override {
        _setGovernance(to);
    }

    /**
     * @notice Add updaters and modify threshold
     * @dev The caller must have the `DEFAULT_ADMIN_ROLE`
     * @param newUpdaters New updater addresses
     * @param newThreshold New threshold
     */
    function addUpdaters(address[] memory newUpdaters, uint256 newThreshold) onlyAdmins external override {
        for(uint i; i< newUpdaters.length; i++) {
            _setupRole(UPDATER_ROLE, newUpdaters[i]);
        }
        _setUpdateThreshold(newThreshold);
    }

    /**
     * @notice Remove updaters and modify threshold
     * @dev The caller must have the `DEFAULT_ADMIN_ROLE`
     * @param existingUpdaters Existing updater addresses
     * @param newThreshold New threshold
     */
    function removeUpdaters(address[] memory existingUpdaters, uint256 newThreshold) onlyAdmins external override {
        for(uint i; i< existingUpdaters.length; i++) {
            _revokeRole(UPDATER_ROLE, existingUpdaters[i]);
        }
        _setUpdateThreshold(newThreshold);
    }

    /**
     * @notice Change the update threshold
     * @dev The caller must have the `DEFAULT_ADMIN_ROLE`
     * @param to New threshold
     */
    function setUpdateThreshold(uint256 to) onlyAdmins external override {
        _setUpdateThreshold(to);
    }

    /**
     * @notice Claim all unclaimed tokens
     * @dev Given a merkle proof of (index, account, totalEarned), claim all
     * unclaimed tokens. Unclaimed tokens are the difference between the total
     * earned tokens (provided in the merkle tree) and those that have been
     * either claimed or slashed.
     *
     * Note: it is possible for the claimed and slashed tokens to exceeed
     * the total earned tokens, particularly when a slashing has occured.
     * In this case no tokens are claimable until total earned has exceeded
     * the sum of the claimed and slashed.
     *
     * If no tokens are claimable, this function will revert.
     * 
     * @param index Claim index
     * @param account Account for claim
     * @param totalEarned Total lifetime amount of tokens earned by account
     * @param merkleProof Merkle proof
     */
    function claim(uint256 index, address account, uint256 totalEarned, bytes32[] calldata merkleProof) external override {
        require(governance != address(0), "MerkleDistributor: Governance not set");

        // Verify caller is authorized and select beneficiary
        address beneficiary = msg.sender;
        if (msg.sender != account) {
            address collector = IGovernance(governance).rewardCollector(account);

            if (!hasRole(DISTRIBUTOR_ROLE, msg.sender)) {
                require(msg.sender == collector, "MerkleDistributor: Cannot collect rewards");
            } else {
                beneficiary = collector == address(0) ? account : collector;
            }
        }

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, totalEarned));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "MerkleDistributor: Invalid proof");

        // Calculate the claimable balance
        uint256 alreadyDistributed = accountState[account].totalClaimed + accountState[account].totalSlashed;
        require(totalEarned > alreadyDistributed, "MerkleDistributor: Nothing claimable");
        uint256 claimable = totalEarned - alreadyDistributed;
        emit Claimed(index, totalEarned, account, claimable);

        // Apply account changes and transfer unclaimed tokens
        _increaseAccount(account, claimable, 0);
        require(token.mint(beneficiary, claimable), "MerkleDistributor: Mint failed");
    }

    /**
     * @notice Set a new merkle root and mints NFT with metadata URI to retreive the full tree
     * @dev The caller must have `UPDATER_ROLE`
     * @param newMerkleRoot Merkle root
     * @param uri NFT uri
     * @param newDistributionNumber Number of distribution
     */
    function updateMerkleRoot(bytes32 newMerkleRoot, string calldata uri, uint256 newDistributionNumber) external override onlyUpdaters returns (uint256) {
        require(!previousMerkleRoot[newMerkleRoot], "MerkleDistributor: Cannot update to a previous merkle root");
        uint256 distributionNumber = distributionCount + 1;
        require(distributionNumber == newDistributionNumber, "MerkleDistributor: Can only update next distribution");
        require(_updaterVotes[msg.sender][distributionNumber] == bytes32(0), "MerkleDistributor: Updater already submitted new root");

        _updaterVotes[msg.sender][distributionNumber] = newMerkleRoot;
        uint256 votes = _updateVotes[newMerkleRoot] + 1;
        _updateVotes[newMerkleRoot] = votes;

        if (votes == updateThreshold) {
            merkleRoot = newMerkleRoot;
            previousMerkleRoot[newMerkleRoot] = true;
            distributionCount = distributionNumber;
            _tokenURI[distributionNumber] = uri;

            _mint(msg.sender, distributionNumber);
            emit PermanentURI(uri, distributionNumber);
            emit MerkleRootUpdated(newMerkleRoot, distributionNumber, uri);

            return distributionNumber;
        }
        else {
            return distributionCount;
        }
    }

    /**
     * @notice Slash `account` for `amount` tokens.
     * @dev The caller must have `SLASHERS_ROLE`
     * @param account Account to slash
     * @param amount Amount to slash
     */
    function slash(address account, uint256 amount) external override onlySlashers {
        emit Slashed(account, amount);
        _increaseAccount(account, 0, amount);
    }

    /**
     * @notice Returns true if this contract implements the interface defined by
     * `interfaceId`. 
     * @dev See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     *
     * @param interfaceId ID of interface
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControlEnumerable, IERC165, ERC721Enumerable) returns (bool) {
        return interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC721Metadata).interfaceId
            || interfaceId == type(IERC721Enumerable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @notice Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     * @param tokenId ID of token
     */
    function tokenURI(uint256 tokenId) public view virtual override(ERC721, IERC721Metadata) returns (string memory) {
        require(_exists(tokenId), "ERC721URIStorage: URI query for nonexistent token");

        string memory uri = _tokenURI[tokenId];
        string memory base = _baseURI();

        // If there is no base URI, return the token URI.
        if (bytes(base).length == 0) {
            return uri;
        }
        // If both are set, concatenate the baseURI and tokenURI (via abi.encodePacked).
        if (bytes(uri).length > 0) {
            return string(abi.encodePacked(base, uri));
        }

        return super.tokenURI(tokenId);
    }

    /**
     * @notice Apply a governance change
     * @param to New governance address
     */
    function _setGovernance(address to) private {
        require(to != governance, "MerkleDistributor: Governance address not changed");
        emit GovernanceChanged(governance, to);
        governance = to;
    }

    /**
     * @notice Apply a threshold change
     * @param to New threshold
     */
    function _setUpdateThreshold(uint256 to) private {
        require(to != 0, "MerkleDistributor: Update threshold must be non-zero");
        require(to <= getRoleMemberCount(UPDATER_ROLE), "MerkleDistributor: threshold > updaters");
        emit UpdateThresholdChanged(to);
        updateThreshold = to;
    }

    /**
     * @notice Increase claimed and account amounts for `account`
     * @param account Account to increase
     * @param claimed Claimed amount
     * @param slashed Slashed amount
     */
    function _increaseAccount(address account, uint256 claimed, uint256 slashed) private {
        // Increase balances
        if (claimed != 0) {
            accountState[account].totalClaimed += claimed;
        }

        if (slashed != 0) {
            accountState[account].totalSlashed += slashed;
        }

        if (claimed != 0 || slashed != 0) {
            emit AccountUpdated(account, accountState[account].totalClaimed, accountState[account].totalSlashed);
        }
    }
}