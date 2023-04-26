// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;
/*
██████╗ ███████╗ █████╗ ██╗     ██╗████████╗██╗   ██╗ ██████╗ █████╗ ██████╗ ██████╗ ███████╗
██╔══██╗██╔════╝██╔══██╗██║     ██║╚══██╔══╝╚██╗ ██╔╝██╔════╝██╔══██╗██╔══██╗██╔══██╗██╔════╝
██████╔╝█████╗  ███████║██║     ██║   ██║    ╚████╔╝ ██║     ███████║██████╔╝██║  ██║███████╗
██╔══██╗██╔══╝  ██╔══██║██║     ██║   ██║     ╚██╔╝  ██║     ██╔══██║██╔══██╗██║  ██║╚════██║
██║  ██║███████╗██║  ██║███████╗██║   ██║      ██║   ╚██████╗██║  ██║██║  ██║██████╔╝███████║
╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚══════╝╚═╝   ╚═╝      ╚═╝    ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝ 
*/
import "@openzeppelin/contracts/proxy/Clones.sol";
import "hardhat/console.sol";
import "./interfaces/IRCFactory.sol";
import "./interfaces/IRCTreasury.sol";
import "./interfaces/IRCMarket.sol";
import "./interfaces/IRCNftHubL2.sol";
import "./interfaces/IRCOrderbook.sol";
import "./lib/NativeMetaTransaction.sol";
import "./interfaces/IRealitio.sol";

/// @title Reality Cards Factory
/// @author Andrew Stanger & Daniel Chilvers
/// @notice If you have found a bug, please contact andrew@realitycards.io- no hack pls!!
contract RCFactory is NativeMetaTransaction, IRCFactory {
    /*╔═════════════════════════════════╗
      ║           VARIABLES             ║
      ╚═════════════════════════════════╝*/

    /////// CONTRACT VARIABLES ///////
    IRCTreasury public override treasury;
    IRCNftHubL2 public override nfthub;
    IRCOrderbook public override orderbook;
    IRCLeaderboard public override leaderboard;
    IRealitio public override realitio;
    /// @dev reference contract
    address public override referenceContractAddress;
    /// @dev increments each time a new reference contract is added
    uint256 public override referenceContractVersion;
    /// @dev market addresses, mode // address
    /// @dev these are not used for anything, just an easy way to get markets
    mapping(IRCMarket.Mode => address[]) public marketAddresses;

    ////// BACKUP MODE //////
    /// @dev should the Graph fail the UI needs a way to poll the contracts for market data
    /// @dev the IPFS hash for each market
    mapping(address => string) public override ipfsHash;
    /// @dev the slug each market is hosted at
    mapping(string => address) public override slugToAddress;
    mapping(address => string) public override addressToSlug;

    ///// GOVERNANCE VARIABLES- OWNER /////
    /// @dev artist / winner / market creator / affiliate / card affiliate
    uint256[5] public potDistribution;
    /// @dev minimum tokens that must be sent when creating market which forms initial pot
    uint256 public override sponsorshipRequired;
    /// @dev adjust required price increase (in %)
    uint256 public override minimumPriceIncreasePercent;
    /// @dev The number of users that are allowed to mint an NFT
    uint256 public override nftsToAward;
    /// @dev market opening time must be at least this many seconds in the future
    uint32 public override advancedWarning;
    /// @dev market closing time must be no more than this many seconds in the future
    uint32 public override maximumDuration;
    /// @dev market closing time must be at least this many seconds after opening
    uint32 public override minimumDuration;
    /// @dev if false, anyone can create markets
    bool public override marketCreationGovernorsOnly = true;
    /// @dev if false, anyone can be an affiliate
    bool public override approvedAffiliatesOnly = true;
    /// @dev if false, anyone can be an artist
    bool public override approvedArtistsOnly = true;
    /// @dev the maximum number of rent collections to perform in a single transaction
    uint256 public override maxRentIterations;
    /// @dev the maximum number of rent collections to have performed before locking the market
    uint256 public override maxRentIterationsToLockMarket;
    /// @dev the address of the arbitrator
    address public override arbitrator;
    /// @dev the time allowed to dispute the oracle answer
    uint32 public override timeout;
    /// @dev if true markets default to the paused state
    bool public override marketPausedDefaultState;
    /// @dev a limit to the number of NFTs to mint per market
    uint256 public override cardLimit;
    bool public limitNFTsToWinners;

    ///// GOVERNANCE VARIABLES- GOVERNORS /////
    /// @dev unapproved markets hidden from the interface
    mapping(address => bool) public override isMarketApproved;

    ///// OTHER /////
    uint256 public constant PER_MILLE = 1000; // in MegaBip so (1000 = 100%)
    /// @dev store the tokenURIs for when we need to mint them
    /// @dev we may want the original and the copies to have slightly different metadata
    /// @dev We also want to apply traits to the winning and losing outcomes
    /// @dev this means we need 5 different tokenURIs per card:
    /// @dev Original Neutral - Used during the market runtime, not a winner but not a loser
    /// @dev Original Winner - Applied to the winning outcome
    /// @dev Original Loser - Applied to the losing outcomes
    /// @dev Print Winner - Applied to copies of the winning outcome
    /// @dev Print Loser - Applied to copies of the losing outcomes
    /// @dev Print neutral is not required as you can't print before the result is known
    mapping(address => mapping(uint256 => string)) tokenURIs;

    /*╔═════════════════════════════════╗
      ║          Access Control         ║
      ╚═════════════════════════════════╝*/
    bytes32 public constant UBER_OWNER = keccak256("UBER_OWNER");
    bytes32 public constant OWNER = keccak256("OWNER");
    bytes32 public constant GOVERNOR = keccak256("GOVERNOR");
    bytes32 public constant MARKET = keccak256("MARKET");
    bytes32 public constant TREASURY = keccak256("TREASURY");
    bytes32 public constant ORDERBOOK = keccak256("ORDERBOOK");
    bytes32 public constant ARTIST = keccak256("ARTIST");
    bytes32 public constant AFFILIATE = keccak256("AFFILIATE");
    bytes32 public constant CARD_AFFILIATE = keccak256("CARD_AFFILIATE");

    /*╔═════════════════════════════════╗
      ║            EVENTS               ║
      ╚═════════════════════════════════╝*/

    event LogMarketCreated1(
        address contractAddress,
        address treasuryAddress,
        address nftHubAddress,
        uint256 referenceContractVersion
    );
    event LogMarketCreated2(
        address contractAddress,
        IRCMarket.Mode mode,
        string[] tokenURIs,
        string ipfsHash,
        uint32[] timestamps,
        uint256 totalNftMintCount
    );
    event LogMarketApproved(address market, bool approved);
    event LogMarketTimeRestrictions(
        uint256 _newAdvancedWarning,
        uint256 _newMinimumDuration,
        uint256 _newMaximumDuration
    );
    event LogMintNFTCopy(
        uint256 _originalTokenId,
        address _newOwner,
        uint256 _newTokenId
    );
    event LogMintNFT(uint256 _cardId, address _market, uint256 _tokenId);

    /*╔═════════════════════════════════╗
      ║          CONSTRUCTOR            ║
      ╚═════════════════════════════════╝*/

    constructor(
        IRCTreasury _treasury,
        address _realitioAddress,
        address _arbitratorAddress
    ) {
        require(address(_treasury) != address(0), "Must set Address");
        // initialise MetaTransactions
        _initializeEIP712("RealityCardsFactory", "1");

        // store contract instances
        treasury = _treasury;

        // initialise adjustable parameters
        // artist // winner // creator // affiliate // card affiliates
        setPotDistribution(20, 0, 0, 20, 100); // 2% artist, 2% affiliate, 10% card affiliate
        setMinimumPriceIncreasePercent(10); // 10%
        setNumberOfNFTsToAward(3);
        setCardLimit(100); // safe limit tested and set at 100, can be adjusted later if gas limit changes
        setMaxRentIterations(50, 25); // safe limit tested and set at 50 & 25, can be adjusted later if gas limit changes
        // oracle
        setArbitrator(_arbitratorAddress);
        setRealitioAddress(_realitioAddress);
        setTimeout(86400); // 24 hours
        limitNFTsToWinners = false;
    }

    /*╔═════════════════════════════════╗
      ║          VIEW FUNCTIONS         ║
      ╚═════════════════════════════════╝*/

    /// @notice Fetch the address of the most recently created market
    /// @param _mode Filter by market mode, 0=Classic 1=Winner Takes All 2=SafeMode
    /// @return the address of the most recent market in the given mode
    function getMostRecentMarket(IRCMarket.Mode _mode)
        external
        view
        override
        returns (address)
    {
        if (marketAddresses[_mode].length == 0) return address(0);
        return marketAddresses[_mode][marketAddresses[_mode].length - (1)];
    }

    /// @notice Fetch all the market addresses for a given mode
    /// @param _mode Filter by market mode, 0=Classic 1=Winner Takes All 2=SafeMode
    /// @return an array of all markets in a given mode
    function getAllMarkets(IRCMarket.Mode _mode)
        external
        view
        override
        returns (address[] memory)
    {
        return marketAddresses[_mode];
    }

    /// @notice Returns the currently set pot distribution
    /// @return the pot distribution array: artist, winner, creator, affiliate, card affiliates
    function getPotDistribution()
        external
        view
        override
        returns (uint256[5] memory)
    {
        return potDistribution;
    }

    /// @notice fetch the current oracle, arbitrator and timeout settings
    /// @dev called by the market upon initialise
    /// @dev not passed to initialise to avoid stack too deep error
    /// @return Oracle Address
    /// @return Arbitrator Address
    /// @return Question timeout in seconds
    function getOracleSettings()
        external
        view
        override
        returns (
            IRealitio,
            address,
            uint32
        )
    {
        return (realitio, arbitrator, timeout);
    }

    /// @notice Returns market addresses and ipfs hashes
    /// @dev used for the UI backup mode
    /// @param _mode return markets only in the given mode
    /// @param _state return markets only in the given state
    /// @param _results the number of results to return
    /// @param _skipResults the number of results to skip
    function getMarketInfo(
        IRCMarket.Mode _mode,
        uint256 _state,
        uint256 _results,
        uint256 _skipResults
    )
        external
        view
        returns (
            address[] memory,
            string[] memory,
            string[] memory,
            uint256[] memory
        )
    {
        // start at the end of the marketAddresses array so the most recent market is first
        uint256 _marketIndex = marketAddresses[_mode].length;
        if (_marketIndex < _results) {
            // if we haven't created enough markets yet there's no need to return empty results
            _results = _marketIndex;
        }
        uint256 _resultNumber = 0; // counts the valid results we've found
        uint256 _index = 0; // counts how many markets we have checked (valid or invalid)
        address[] memory _marketAddresses = new address[](_results); // store the addresses of valid markets
        while (_resultNumber < _results && _marketIndex > 1) {
            _marketIndex--;
            address _market = marketAddresses[_mode][_marketIndex];
            if (IRCMarket(_market).state() == IRCMarket.States(_state)) {
                // we found an appropriate market
                if (_index < _skipResults) {
                    // we need to skip it however
                    _index++;
                } else {
                    // we can use this one, add the address and increment
                    _marketAddresses[_resultNumber] = _market;
                    _resultNumber++;
                    _index++;
                }
            }
        }
        return _getMarketInfo(_marketAddresses);
    }

    /// @notice Assembles all the Slugs, IPFS hashes and PotSizes for the markets given
    /// @dev separated from getMarketInfo to avoid Stack too deep
    function _getMarketInfo(address[] memory _marketAddresses)
        internal
        view
        returns (
            address[] memory,
            string[] memory,
            string[] memory,
            uint256[] memory
        )
    {
        string[] memory _ipfsHashes = new string[](_marketAddresses.length);
        uint256[] memory _potSizes = new uint256[](_marketAddresses.length);
        string[] memory _slugs = new string[](_marketAddresses.length);
        for (uint256 i = 0; i < _marketAddresses.length; i++) {
            if (_marketAddresses[i] == address(0)) break;
            _ipfsHashes[i] = ipfsHash[_marketAddresses[i]];
            _slugs[i] = addressToSlug[_marketAddresses[i]];
            _potSizes[i] = IRCMarket(_marketAddresses[i]).totalRentCollected();
        }
        return (_marketAddresses, _ipfsHashes, _slugs, _potSizes);
    }

    /*╔═════════════════════════════════╗
      ║           MODIFIERS             ║
      ╚═════════════════════════════════╝*/

    modifier onlyUberOwner() {
        require(
            treasury.checkPermission(UBER_OWNER, msgSender()),
            "Not approved"
        );
        _;
    }
    modifier onlyOwner() {
        require(treasury.checkPermission(OWNER, msgSender()), "Not approved");
        _;
    }
    modifier onlyGovernors() {
        require(
            treasury.checkPermission(GOVERNOR, msgSender()),
            "Not approved"
        );
        _;
    }
    modifier onlyMarkets() {
        require(treasury.checkPermission(MARKET, msgSender()), "Not approved");
        _;
    }

    /*╔═════════════════════════════════╗
      ║       GOVERNANCE - OWNER        ║
      ╚═════════════════════════════════╝*/
    /// @dev all functions should have onlyOwner modifier
    // Min price increase & pot distribution emitted by Market.
    // Advanced Warning and Maximum Duration events emitted here. Nothing else need be emitted.

    /*┌────────────────────────────────────┐
      │ CALLED WITHIN CONSTRUCTOR - PUBLIC │
      └────────────────────────────────────┘*/

    /// @notice update stakeholder payouts
    /// @dev in MegaBip (so 1000 = 100%)
    /// @param _artistCut The artist that designed the card
    /// @param _winnerCut Extra cut for the longest owner
    /// @param _creatorCut The creator of the market
    /// @param _affiliateCut An affiliate for the market that doesn't fit into the other cuts
    /// @param _cardAffiliateCut An affiliate cur for specific cards
    function setPotDistribution(
        uint256 _artistCut,
        uint256 _winnerCut,
        uint256 _creatorCut,
        uint256 _affiliateCut,
        uint256 _cardAffiliateCut
    ) public override onlyOwner {
        require(
            _artistCut +
                _winnerCut +
                _creatorCut +
                _affiliateCut +
                _cardAffiliateCut <=
                PER_MILLE,
            "Cuts too big"
        );
        potDistribution[0] = _artistCut;
        potDistribution[1] = _winnerCut;
        potDistribution[2] = _creatorCut;
        potDistribution[3] = _affiliateCut;
        potDistribution[4] = _cardAffiliateCut;
    }

    /// @notice how much above the current price a user must bid, in %
    /// @param _percentIncrease the percentage to set, e.g. 10 = 10%
    function setMinimumPriceIncreasePercent(uint256 _percentIncrease)
        public
        override
        onlyOwner
    {
        minimumPriceIncreasePercent = _percentIncrease;
    }

    /// @notice how many NFTs will be awarded to the leaderboard
    /// @param _nftsToAward the number of NFTs to award
    function setNumberOfNFTsToAward(uint256 _nftsToAward)
        public
        override
        onlyOwner
    {
        nftsToAward = _nftsToAward;
    }

    /// @notice A limit to the number of NFTs to mint per market
    /// @dev to avoid gas limits
    /// @param _cardLimit the limit to set
    function setCardLimit(uint256 _cardLimit) public override onlyOwner {
        cardLimit = _cardLimit;
    }

    /// @notice A limit to the number of rent collections per transaction
    /// @dev to avoid gas limits
    /// @param _rentLimit the limit to set
    function setMaxRentIterations(uint256 _rentLimit, uint256 _rentLimitLocking)
        public
        override
        onlyOwner
    {
        maxRentIterations = _rentLimit;
        maxRentIterationsToLockMarket = _rentLimitLocking;
    }

    /// @notice set the address of the reality.eth contracts
    /// @param _newAddress the address to set
    function setRealitioAddress(address _newAddress) public override onlyOwner {
        require(_newAddress != address(0), "Must set address");
        realitio = IRealitio(_newAddress);
    }

    /// @notice address of the arbitrator, in case of continued disputes on reality.eth
    /// @param _newAddress the address to set
    function setArbitrator(address _newAddress) public override onlyOwner {
        require(_newAddress != address(0), "Must set address");
        arbitrator = _newAddress;
    }

    /// @notice set how long reality.eth waits for disputes before finalising
    /// @param _newTimeout the timeout to set in seconds, 86400 = 24hrs
    function setTimeout(uint32 _newTimeout) public override onlyOwner {
        // event is emitted from the Oracle when the question is asked
        timeout = _newTimeout;
    }

    /// @notice To set is markets should default to paused or not
    /// @param _state The default state for all new markets
    function setMarketPausedDefaultState(bool _state)
        external
        override
        onlyOwner
    {
        /// @dev the event is emitted when a market is created
        marketPausedDefaultState = _state;
    }

    /// @notice To limit NFT copies to the winning outcome only
    /// @param _limitEnabled Set to True to limit to the winning outcome only
    function setLimitNFTsToWinners(bool _limitEnabled)
        public
        override
        onlyOwner
    {
        limitNFTsToWinners = _limitEnabled;
    }

    /*┌──────────────────────────────────────────┐
      │ NOT CALLED WITHIN CONSTRUCTOR - EXTERNAL │
      └──────────────────────────────────────────┘*/

    /// @notice whether or not only governors can create the market
    function changeMarketCreationGovernorsOnly() external override onlyOwner {
        marketCreationGovernorsOnly = !marketCreationGovernorsOnly;
    }

    /// @notice whether or not anyone can be an artist
    function changeApprovedArtistsOnly() external override onlyOwner {
        approvedArtistsOnly = !approvedArtistsOnly;
    }

    /// @notice whether or not anyone can be an affiliate
    function changeApprovedAffiliatesOnly() external override onlyOwner {
        approvedAffiliatesOnly = !approvedAffiliatesOnly;
    }

    /// @notice how many tokens must be sent in the createMarket tx which forms the initial pot
    /// @param _amount the sponsorship required in wei
    function setSponsorshipRequired(uint256 _amount)
        external
        override
        onlyOwner
    {
        sponsorshipRequired = _amount;
    }

    /// @notice To set the market time restrictions, market opening and min/max duration.
    /// @param _newAdvancedWarning the warning time to set in seconds
    /// @param _newMinimumDuration the minimum market duration
    /// @param _newMaximumDuration the maximum market duration
    /// @dev might be nicer to have these separate but takes up too much space
    function setMarketTimeRestrictions(
        uint32 _newAdvancedWarning,
        uint32 _newMinimumDuration,
        uint32 _newMaximumDuration
    ) external override onlyOwner {
        advancedWarning = _newAdvancedWarning;
        minimumDuration = _newMinimumDuration;
        maximumDuration = _newMaximumDuration;
        emit LogMarketTimeRestrictions(
            _newAdvancedWarning,
            _newMinimumDuration,
            _newMaximumDuration
        );
    }

    /// @notice Allow the owner to update a token URI.
    /// @notice only updates for tokens not yet minted
    /// @dev after calling this existing token URIs should be changed on
    /// @dev .. the NFT hubs using setTokenURI()
    /// @param _market the market address the token belongs to
    /// @param _cardId the index 0 card id of the token to change
    /// @param _newTokenURIs the new URIs to set
    function updateTokenURI(
        address _market,
        uint256 _cardId,
        string[] calldata _newTokenURIs
    ) external override onlyUberOwner {
        IRCMarket.Mode _mode = IRCMarket(_market).mode();
        uint256 _numberOfCards = IRCMarket(_market).numberOfCards();
        tokenURIs[_market][_cardId] = _newTokenURIs[0];
        tokenURIs[_market][(_cardId + _numberOfCards)] = _newTokenURIs[1];
        tokenURIs[_market][(_cardId + (_numberOfCards * 2))] = _newTokenURIs[2];
        tokenURIs[_market][(_cardId + (_numberOfCards * 3))] = _newTokenURIs[3];
        tokenURIs[_market][(_cardId + (_numberOfCards * 4))] = _newTokenURIs[4];

        // assemble the rest of the data so we can reuse the event
        string[] memory _tokenURIs = new string[](_numberOfCards * 5);
        for (uint256 i = 0; i < _tokenURIs.length; i++) {
            _tokenURIs[i] = tokenURIs[_market][i];
        }
        uint32[] memory _timestamps = new uint32[](3);
        _timestamps[0] = IRCMarket(_market).marketOpeningTime();
        _timestamps[1] = IRCMarket(_market).marketLockingTime();
        _timestamps[2] = IRCMarket(_market).oracleResolutionTime();

        // reuse this event so the frontend can pickup the change
        emit LogMarketCreated2(
            _market,
            IRCMarket.Mode(_mode),
            _tokenURIs,
            ipfsHash[_market],
            _timestamps,
            nfthub.totalSupply()
        );
    }

    /*╔═════════════════════════════════╗
      ║     GOVERNANCE - GOVERNORS      ║
      ╚═════════════════════════════════╝*/
    /// @dev all functions should have onlyGovernors modifier

    /// @notice markets are default hidden from the interface, this reveals them
    /// @param _market the market address to change approval for
    function changeMarketApproval(address _market)
        external
        override
        onlyGovernors
    {
        require(_market != address(0), "Must set Address");
        // check it's an RC contract
        require(treasury.checkPermission(MARKET, _market), "Not Market");
        isMarketApproved[_market] = !isMarketApproved[_market];
        // governors shouldn't have the ability to pause a market, only un-pause.
        // .. if a governor accidentally approves a market they should seek
        // .. assistance from the owner to decide if it should be paused.
        treasury.unPauseMarket(_market);
        // the market will however be hidden from the UI in the meantime
        emit LogMarketApproved(_market, isMarketApproved[_market]);
    }

    /*╔═════════════════════════════════╗
      ║     GOVERNANCE - UBER OWNER     ║
      ╠═════════════════════════════════╣
      ║  ******** DANGER ZONE ********  ║
      ╚═════════════════════════════════╝*/
    /// @dev uber owner required for upgrades, this is separated so owner can be
    /// @dev ..  set to multisig, or burn address to relinquish upgrade ability
    /// @dev ... while maintaining governance over other governance functions

    /// @notice change the reference contract for the contract logic
    /// @param _newAddress the address of the new reference contract to set
    function setReferenceContractAddress(address _newAddress)
        external
        override
        onlyUberOwner
    {
        require(_newAddress != address(0));
        // check it's an RC contract
        IRCMarket newContractVariable = IRCMarket(_newAddress);
        require(newContractVariable.isMarket(), "Not Market");
        // set
        referenceContractAddress = _newAddress;
        // increment version
        referenceContractVersion += 1;
    }

    /// @notice where the NFTs live
    /// @param _newAddress the address to set
    function setNftHubAddress(IRCNftHubL2 _newAddress)
        external
        override
        onlyUberOwner
    {
        require(address(_newAddress) != address(0), "Must set Address");
        nfthub = _newAddress;
    }

    /// @notice set the address of the orderbook contract
    /// @param _newOrderbook the address to set
    /// @dev set by the treasury to ensure all contracts use the same orderbook
    function setOrderbookAddress(IRCOrderbook _newOrderbook) external override {
        require(
            treasury.checkPermission(TREASURY, msgSender()),
            "Not approved"
        );
        orderbook = _newOrderbook;
    }

    /// @notice set the address of the leaderboard contract
    /// @param _newLeaderboard the address to set
    /// @dev set by the treasury to ensure all contracts use the same leaderboard
    function setLeaderboardAddress(IRCLeaderboard _newLeaderboard)
        external
        override
    {
        require(
            treasury.checkPermission(TREASURY, msgSender()),
            "Not approved"
        );
        leaderboard = _newLeaderboard;
    }

    /// @notice set the address of the treasury contract
    /// @param _newTreasury the address to set
    function setTreasuryAddress(IRCTreasury _newTreasury)
        external
        override
        onlyUberOwner
    {
        require(address(_newTreasury) != address(0), "Must set Address");
        treasury = _newTreasury;
    }

    /*╔═════════════════════════════════╗
      ║         MARKET CREATION         ║
      ╚═════════════════════════════════╝*/
    // The factory contract has one job, this is it!

    /// @notice Creates a new market with the given parameters
    /// @param _mode 0 = normal, 1 = winner takes all, 2 = Safe mode
    /// @param _ipfsHash the IPFS location of the market metadata
    /// @param _slug the URL subdomain in the UI
    /// @param _timestamps for market opening, locking, and oracle resolution
    /// @param _tokenURIs location of NFT metadata, 5 versions for originals, copies, winners and losers
    /// @param _artistAddress where to send artist's cut, if any
    /// @param _affiliateAddress where to send affiliates cut, if any
    /// @param _cardAffiliateAddresses where to send card specific affiliates cut, if any
    /// @param _realitioQuestion the details of the event to send to the oracle
    /// @param _sponsorship amount of sponsorship to create the market with
    /// @return The address of the new market
    function createMarket(
        uint32 _mode,
        string memory _ipfsHash,
        string memory _slug,
        uint32[] memory _timestamps,
        string[] memory _tokenURIs,
        address _artistAddress,
        address _affiliateAddress,
        address[] memory _cardAffiliateAddresses,
        string memory _realitioQuestion,
        uint256 _sponsorship
    ) external override returns (address) {
        address _creator = msgSender();

        // check nfthub has been set
        require(address(nfthub) != address(0), "Nfthub not set");
        require(
            address(referenceContractAddress) != address(0),
            "Reference not set"
        );

        // check sponsorship
        require(
            _sponsorship >= sponsorshipRequired,
            "Insufficient sponsorship"
        );
        treasury.checkSponsorship(_creator, _sponsorship);

        // check the number of NFTs to mint is within limits
        /// @dev we want different tokenURIs for originals and copies
        /// @dev ..the copies are appended to the end of the array
        /// @dev ..so half the array length is the number of tokens.
        require(_tokenURIs.length <= cardLimit * 5, "Hit mint limit");
        require(_tokenURIs.length % 5 == 0, "TokenURI Length Error");

        // check stakeholder addresses
        // artist
        if (approvedArtistsOnly) {
            require(
                _artistAddress == address(0) ||
                    treasury.checkPermission(ARTIST, _artistAddress),
                "Artist not approved"
            );
        }

        // affiliate
        require(
            _cardAffiliateAddresses.length == 0 ||
                _cardAffiliateAddresses.length * 5 == _tokenURIs.length,
            "Card Affiliate Length Error"
        );
        if (approvedAffiliatesOnly) {
            require(
                _affiliateAddress == address(0) ||
                    treasury.checkPermission(AFFILIATE, _affiliateAddress),
                "Affiliate not approved"
            );
            // card affiliates
            for (uint256 i = 0; i < _cardAffiliateAddresses.length; i++) {
                require(
                    _cardAffiliateAddresses[i] == address(0) ||
                        treasury.checkPermission(
                            CARD_AFFILIATE,
                            _cardAffiliateAddresses[i]
                        ),
                    "Card affiliate not approved"
                );
            }
        }

        // check market creator is approved
        if (marketCreationGovernorsOnly) {
            require(
                treasury.checkPermission(GOVERNOR, _creator),
                "Not approved"
            );
        }

        _checkTimestamps(_timestamps);

        // create the market and emit the appropriate events
        // two events to avoid stack too deep error
        address _newAddress = Clones.clone(referenceContractAddress);
        emit LogMarketCreated1(
            _newAddress,
            address(treasury),
            address(nfthub),
            referenceContractVersion
        );
        emit LogMarketCreated2(
            _newAddress,
            IRCMarket.Mode(_mode),
            _tokenURIs,
            _ipfsHash,
            _timestamps,
            nfthub.totalSupply()
        );

        // tell Treasury about new market
        // before initialize as during initialize the market may call the treasury
        treasury.addMarket(_newAddress, marketPausedDefaultState);

        // update internals
        marketAddresses[IRCMarket.Mode(_mode)].push(_newAddress);
        ipfsHash[_newAddress] = _ipfsHash;
        slugToAddress[_slug] = _newAddress;
        addressToSlug[_newAddress] = _slug;

        // initialize the market
        IRCMarket(_newAddress).initialize(
            IRCMarket.Mode(_mode),
            _timestamps,
            (_tokenURIs.length / 5),
            _artistAddress,
            _affiliateAddress,
            _cardAffiliateAddresses,
            _creator,
            _realitioQuestion,
            nftsToAward
        );

        // store token URIs
        for (uint256 i = 0; i < _tokenURIs.length; i++) {
            tokenURIs[_newAddress][i] = _tokenURIs[i];
        }

        // pay sponsorship, if applicable
        if (_sponsorship > 0) {
            IRCMarket(_newAddress).sponsor(_creator, _sponsorship);
        }

        return _newAddress;
    }

    function _checkTimestamps(uint32[] memory _timestamps) internal view {
        // check timestamps
        require(_timestamps.length == 3, "Incorrect number of array elements");
        // check market opening time
        if (advancedWarning != 0) {
            // different statements to give clearer revert messages
            require(
                _timestamps[0] >= block.timestamp,
                "Market opening time not set"
            );
            require(
                _timestamps[0] - advancedWarning > block.timestamp,
                "Market opens too soon"
            );
        }
        // check market locking time
        if (maximumDuration != 0) {
            require(
                _timestamps[1] < block.timestamp + maximumDuration,
                "Market locks too late"
            );
        }
        require(
            _timestamps[0] + minimumDuration < _timestamps[1] &&
                block.timestamp + minimumDuration < _timestamps[1],
            "Market lock must be after opening"
        );
        // check oracle resolution time (no more than 1 week after market locking to get result)
        require(
            _timestamps[1] + (1 weeks) > _timestamps[2] &&
                _timestamps[1] <= _timestamps[2],
            "Oracle resolution time error"
        );
    }

    /// @notice To get adjustable market settings
    /// @dev The market calls this after creation, we can't send much else to initialize
    /// @dev putting in a single function reduces the number of calls required.
    function getMarketSettings()
        external
        view
        override
        returns (
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        return (
            minimumPriceIncreasePercent,
            maxRentIterations,
            maxRentIterationsToLockMarket,
            limitNFTsToWinners
        );
    }

    /// @notice Called by the markets to mint the original NFTs
    /// @param _card the card id to be minted
    function mintMarketNFT(uint256 _card) external override onlyMarkets {
        uint256 nftHubMintCount = nfthub.totalSupply();
        address _market = msgSender();
        nfthub.mint(_market, nftHubMintCount, tokenURIs[_market][_card]);
        emit LogMintNFT(_card, _market, nftHubMintCount);
    }

    /// @notice allows the market to mint a copy of the NFT for users on the leaderboard
    /// @param _user the user to award the NFT to
    /// @param _cardId the non-unique cardId to copy
    /// @param _tokenId the unique NFT tokenId
    /// @param _winner true if this was a winning outcome
    function mintCopyOfNFT(
        address _user,
        uint256 _cardId,
        uint256 _tokenId,
        bool _winner
    ) external override onlyMarkets {
        address _market = msgSender();
        uint256 _newTokenId = nfthub.totalSupply();
        uint256 _numberOfCards = IRCMarket(_market).numberOfCards();
        uint256 _tokenURIIndex;
        if (_winner) {
            _tokenURIIndex = _cardId + (_numberOfCards * 3);
        } else {
            _tokenURIIndex = _cardId + (_numberOfCards * 4);
        }
        nfthub.mint(_user, _newTokenId, tokenURIs[_market][_tokenURIIndex]);
        emit LogMintNFTCopy(_tokenId, _user, _newTokenId);
    }

    /// @notice At the end of the market updates the tokenURI to apply the Winning/Losing traits
    /// @param _cardId the non unique cardId (used to find the tokenURI)
    /// @param _tokenId the unique NFT id
    /// @param _winner true if this was a winning outcome
    function updateTokenOutcome(
        uint256 _cardId,
        uint256 _tokenId,
        bool _winner
    ) external override onlyMarkets {
        address _market = msgSender();
        uint256 _numberOfCards = IRCMarket(_market).numberOfCards();
        uint256 _tokenURIIndex;
        if (_winner) {
            _tokenURIIndex = _cardId + _numberOfCards;
        } else {
            _tokenURIIndex = _cardId + (_numberOfCards * 2);
        }
        nfthub.setTokenURI(_tokenId, tokenURIs[_market][_tokenURIIndex]);
    }

    /*
         ▲  
        ▲ ▲ 
              */
}
