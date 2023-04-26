pragma solidity 0.5.13;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "hardhat/console.sol";
import "../../interfaces/IRealitio.sol";
import "../../interfaces/IFactory.sol";
import "../../interfaces/ITreasury.sol";
import '../../interfaces/IRCProxyXdai.sol';
import '../../interfaces/IRCNftHubXdai.sol';
import '../../lib/NativeMetaTransaction.sol';

// only difference is price is doubled 
contract RCMarketXdaiV2 is Initializable, NativeMetaTransaction {

    using SafeMath for uint256;

    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    ///// CONTRACT SETUP /////
    /// @dev = how many outcomes/teams/NFTs etc 
    uint256 public numberOfTokens;
    /// @dev only for _revertToUnderbidder to prevent gas limits
    uint256 public constant MAX_ITERATIONS = 10;
    uint256 public constant MAX_UINT256 = 2**256 - 1;
    enum States {CLOSED, OPEN, LOCKED, WITHDRAW}
    States public state; 
    /// @dev type of event. 0 = classic, 1 = winner takes all, 2 = hot potato 
    uint256 public mode;
    /// @dev so the Factory can check its a market
    bool public constant isMarket = true;
    /// @dev counts the total NFTs minted across all events at the time market created
    /// @dev nft tokenId = card Id + totalNftMintCount
    uint256 public totalNftMintCount;

    ///// CONTRACT VARIABLES /////
    ITreasury public treasury;
    IFactory public factory;
    IRCProxyXdai public proxy;
    IRCNftHubXdai public nfthub;

    ///// PRICE, DEPOSITS, RENT /////
    /// @dev in attodai (so 100xdai = 100000000000000000000)
    mapping (uint256 => uint256) public price; 
    /// @dev keeps track of all the rent paid by each user. So that it can be returned in case of an invalid market outcome.
    mapping (address => uint256) public collectedPerUser;
    /// @dev keeps track of all the rent paid for each token, for card specific affiliate payout
    mapping (uint256 => uint256) public collectedPerToken;
    /// @dev an easy way to track the above across all tokens
    uint256 public totalCollected; 
    /// @dev the minimum required price increase
    uint256 public minimumPriceIncrease;
    /// @dev minimum rental duration (1 day divisor: i.e. 24 = 1 hour, 48 = 30 mins)
    uint256 public minRentalDivisor;
    /// @dev prevents user from cancelling and re-renting in the same block
    mapping (address => uint256) public ownershipLostTimestamp;

    ///// ORDERBOOK /////
    /// @dev stores the orderbook. Doubly linked list. 
    mapping (uint256 => mapping(address => Bid)) public orderbook; // tokenID // user address // Bid
    struct Bid{
  		uint256 price;
        uint256 timeHeldLimit; // users can optionally set a maximum time to hold it for, after which it reverts
        address next; // who it will return to when current owner exits (i.e, next = going down the list)
        address prev; // who it returned from (i.e., prev = going up the list)
    }
 
    ///// TIME /////
    /// @dev how many seconds each user has held each token for, for determining winnings  
    mapping (uint256 => mapping (address => uint256) ) public timeHeld;
    /// @dev sums all the timeHelds for each. Used when paying out. Should always increment at the same time as timeHeld
    mapping (uint256 => uint256) public totalTimeHeld; 
    /// @dev used to determine the rent due. Rent is due for the period (now - timeLastCollected), at which point timeLastCollected is set to now.
    mapping (uint256 => uint256) public timeLastCollected; 
    /// @dev to track the max timeheld of each token (for giving NFT to winner)
    mapping (uint256 => uint256) public longestTimeHeld;
    /// @dev to track who has owned it the most (for giving NFT to winner)
    mapping (uint256 => address) public longestOwner;
    /// @dev tells the contract to exit position after min rental duration (or immediately, if already rented for this long)
    /// @dev if not current owner, prevents ownership reverting back to you

    ///// TIMESTAMPS ///// 
    /// @dev when the market opens 
    uint32 public marketOpeningTime; 
    /// @dev when the market locks 
    uint32 public marketLockingTime; 
    /// @dev when the question can be answered on realitio
    /// @dev only needed for circuit breaker
    uint32 public oracleResolutionTime;

    ///// PAYOUT VARIABLES /////
    uint256 public winningOutcome;
    /// @dev prevent users withdrawing twice
    mapping (address => bool) public userAlreadyWithdrawn;
    /// @dev the artist
    address public artistAddress;
    uint256 public artistCut;
    bool public artistPaid = false;
    /// @dev the affiliate
    address public affiliateAddress;
    uint256 public affiliateCut;
    bool public affiliatePaid = false;
    /// @dev the winner
    uint256 public winnerCut;
    /// @dev the market creator
    address public marketCreatorAddress;
    uint256 public creatorCut;
    bool public creatorPaid = false;
    /// @dev card specific recipients
    address[] public cardAffiliateAddresses;
    uint256 public cardAffiliateCut;
    bool public cardAffiliatePaid = false;

    ////////////////////////////////////
    //////// EVENTS ////////////////////
    ////////////////////////////////////

    event LogNewRental(address indexed newOwner, uint256 indexed newPrice, uint256 timeHeldLimit, uint256 indexed tokenId);
    event LogForeclosure(address indexed prevOwner, uint256 indexed tokenId);
    event LogRentCollection(uint256 indexed rentCollected, uint256 indexed tokenId, address indexed owner);
    event LogCardTransferredToUnderbidder(uint256 indexed tokenId, address indexed previousOwner);
    event LogContractLocked(bool indexed didTheEventFinish);
    event LogWinnerKnown(uint256 indexed winningOutcome);
    event LogWinningsPaid(address indexed paidTo, uint256 indexed amountPaid);
    event LogStakeholderPaid(address indexed paidTo, uint256 indexed amountPaid);
    event LogRentReturned(address indexed returnedTo, uint256 indexed amountReturned);
    event LogTimeHeldUpdated(uint256 indexed newTimeHeld, address indexed owner, uint256 indexed tokenId);
    event LogStateChange(uint256 indexed newState);
    event LogUpdateTimeHeldLimit(address indexed owner, uint256 newLimit, uint256 tokenId);
    event LogExit(address indexed owner, uint256 tokenId, bool exit);
    event LogSponsor(uint256 indexed amount);
    event LogNftUpgraded(uint256 indexed currentTokenId, uint256 indexed newTokenId);
    event LogPayoutDetails(address indexed artistAddress, address marketCreatorAddress, address affiliateAddress, address[] cardAffiliateAddresses, uint256 indexed artistCut, uint256 winnerCut, uint256 creatorCut, uint256 affiliateCut, uint256 cardAffiliateCut);
    event LogTransferCardToLongestOwner(uint256 tokenId, address longestOwner);

    ////////////////////////////////////
    //////// CONSTRUCTOR ///////////////
    ////////////////////////////////////
    
    /// @param _mode 0 = normal, 1 = winner takes all, 2 = hot potato
    /// @param _timestamps for market opening, locking, and oracle resolution
    /// @param _numberOfTokens how many Cards in this market
    /// @param _totalNftMintCount total existing Cards across all markets
    /// @param _artistAddress where to send artist's cut, if any
    /// @param _affiliateAddress where to send affiliate's cut, if any
    /// @param _cardAffiliateAddresses where to send card specific affiliate's cut, if any
    /// @param _marketCreatorAddress where to send market creator's cut, if any
    function initialize(
        uint256 _mode,
        uint32[] memory _timestamps,
        uint256 _numberOfTokens,
        uint256 _totalNftMintCount,
        address _artistAddress,
        address _affiliateAddress,
        address[] memory _cardAffiliateAddresses,
        address _marketCreatorAddress
    ) public initializer {
        assert(_mode <= 2);

        // initialise MetaTransactions
        _initializeEIP712("RealityCardsMarket","1");

        // external contract variables:
        factory = IFactory(msg.sender);
        treasury = factory.treasury();
        proxy = factory.proxy();
        nfthub = factory.nfthub();
        
        // initialiiize!
        winningOutcome = MAX_UINT256; // default invalid

        // assign arguments to public variables
        mode = _mode;
        numberOfTokens = _numberOfTokens;
        totalNftMintCount = _totalNftMintCount;
        marketOpeningTime = _timestamps[0];
        marketLockingTime = _timestamps[1];
        oracleResolutionTime = _timestamps[2];
        artistAddress = _artistAddress;
        marketCreatorAddress = _marketCreatorAddress;
        affiliateAddress = _affiliateAddress;
        cardAffiliateAddresses = _cardAffiliateAddresses;
        uint256[5] memory _potDistribution = factory.getPotDistribution();
        minimumPriceIncrease = factory.minimumPriceIncrease();
        minRentalDivisor = treasury.minRentalDivisor();
        artistCut = _potDistribution[0];
        winnerCut = _potDistribution[1];
        creatorCut = _potDistribution[2];
        affiliateCut = _potDistribution[3];
        cardAffiliateCut = _potDistribution[4];

        // reduce artist cut to zero if zero adddress set
        if (_artistAddress == address(0)) {
            artistCut = 0;
        }

        // reduce affiliate cut to zero if zero adddress set
        if (_affiliateAddress == address(0)) {
            affiliateCut = 0;
        }

        // check the validity of card affiliate array. 
        // if not valid, reduce payout to zero
        if (_cardAffiliateAddresses.length == _numberOfTokens) {
            for (uint i = 0; i < _numberOfTokens; i++) { 
                if (_cardAffiliateAddresses[i] == address(0)) {
                    cardAffiliateCut = 0;
                }
            }
        } else {
            cardAffiliateCut = 0;
        }

        // if winner takes all mode, set winnerCut to max
        if (_mode == 1) {
            winnerCut = (((uint256(1000).sub(artistCut)).sub(creatorCut)).sub(affiliateCut)).sub(cardAffiliateCut);
        } 

        // move to OPEN immediately if market opening time in the past
        if (marketOpeningTime <= now) {
            _incrementState();
        }
        
        emit LogPayoutDetails(_artistAddress, _marketCreatorAddress, _affiliateAddress, cardAffiliateAddresses, artistCut, winnerCut, creatorCut, affiliateCut, cardAffiliateCut);
    } 

    ////////////////////////////////////
    /////////// MODIFIERS //////////////
    ////////////////////////////////////

    modifier checkState(States currentState) {
        require(state == currentState, "Incorrect state");
        _;
    }

    /// @dev automatically opens market if appropriate
    modifier autoUnlock() {
        if (marketOpeningTime <= now && state == States.CLOSED) {
            _incrementState();
        }
        _;
    }

    /// @dev automatically locks market if appropriate
    modifier autoLock() {
        _;
        if (marketLockingTime <= now) {
            lockMarket();
        }
    }

    /// @notice what it says on the tin
    modifier amountNotZero(uint256 _dai) {
        require(_dai > 0, "Amount must be above zero");
       _;
    }

    /// @notice what it says on the tin
    modifier onlyTokenOwner(uint256 _tokenId) {
        require(msgSender() == ownerOf(_tokenId), "Not owner");
       _;
    }

    ////////////////////////////////////
    //// ORACLE PROXY CONTRACT CALLS ///
    ////////////////////////////////////

    /// @dev send NFT to mainnet
    /// @dev upgrades not possible if market not approved
    function upgradeCard(uint256 _tokenId) external checkState(States.WITHDRAW) onlyTokenOwner(_tokenId) {
        require(!factory.trapIfUnapproved() || factory.isMarketApproved(address(this)), "Upgrade blocked");
        string memory _tokenUri = tokenURI(_tokenId);
        address _owner = ownerOf(_tokenId);
        uint256 _actualTokenId = _tokenId.add(totalNftMintCount);
        proxy.saveCardToUpgrade(_actualTokenId, _tokenUri, _owner);
        _transferCard(ownerOf(_tokenId), address(this), _tokenId);
        emit LogNftUpgraded(_tokenId, _actualTokenId);
    }

    /// @notice gets the winning outcome from realitio
    /// @dev the returned value is equivilent to tokenId
    /// @dev this function call will revert if it has not yet resolved
    function _getWinner() internal view returns(uint256) {
        uint256 _winningOutcome = proxy.getWinner(address(this));
        return _winningOutcome;
    }

    /// @notice has the question been finalized on realitio?
    function _isQuestionFinalized() internal view returns (bool) {
        return proxy.isFinalized(address(this));
    }

    ////////////////////////////////////
    /////// NFT HUB CONTRACT CALLS /////
    ////////////////////////////////////

    /// @notice gets the owner of the NFT via their Card Id
    function ownerOf(uint256 _tokenId) public view returns(address) {
        uint256 _actualTokenId = _tokenId.add(totalNftMintCount);
        return nfthub.ownerOf(_actualTokenId);
    }

    /// @notice gets tokenURI via their Card Id
    function tokenURI(uint256 _tokenId) public view returns(string memory) {
        uint256 _actualTokenId = _tokenId.add(totalNftMintCount);
        return nfthub.tokenURI(_actualTokenId);
    }

    /// @notice transfer ERC 721 between users
    function _transferCard(address _from, address _to, uint256 _tokenId) internal {
        require(_from != address(0) && _to != address(0) , "Cannot send to/from zero address");
        uint256 _actualTokenId = _tokenId.add(totalNftMintCount);
        assert(nfthub.transferNft(_from, _to, _actualTokenId));
    }

    ////////////////////////////////////
    //// MARKET RESOLUTION FUNCTIONS ///
    ////////////////////////////////////

    /// @notice checks whether the competition has ended, if so moves to LOCKED state
    /// @dev can be called by anyone 
    /// @dev public because possibly called within newRental
    function lockMarket() public checkState(States.OPEN) {
        require(marketLockingTime < now, "Market has not finished");
        // do a final rent collection before the contract is locked down
        collectRentAllCards();
        _incrementState();
        emit LogContractLocked(true);
    }

    /// @notice checks whether the Realitio question has resolved, and if yes, gets the winner
    /// @dev can be called by anyone 
    function determineWinner() external checkState(States.LOCKED) {
        require(_isQuestionFinalized(), "Oracle not resolved");
        // get the winner. This will revert if answer is not resolved.
        winningOutcome = _getWinner();
        _incrementState();
        // transfer NFTs to the longest owners
        _processCardsAfterEvent(); 
        emit LogWinnerKnown(winningOutcome);
    }

    /// @notice pays out winnings, or returns funds
    /// @dev public because called by withdrawWinningsAndDeposit
    function withdraw() external checkState(States.WITHDRAW) {
        require(!userAlreadyWithdrawn[msgSender()], "Already withdrawn");
        userAlreadyWithdrawn[msgSender()] = true;
        if (totalTimeHeld[winningOutcome] > 0) {
            _payoutWinnings();
        } else {
             _returnRent();
        }
    }

    /// @notice pays winnings
    function _payoutWinnings() internal {
        uint256 _winningsToTransfer;
        uint256 _remainingCut = ((((uint256(1000).sub(artistCut)).sub(affiliateCut))).sub(cardAffiliateCut).sub(winnerCut)).sub(creatorCut); 
        // calculate longest owner's extra winnings, if relevant
        if (longestOwner[winningOutcome] == msgSender() && winnerCut > 0){
            _winningsToTransfer = (totalCollected.mul(winnerCut)).div(1000);
        }
        // calculate normal winnings, if any
        uint256 _remainingPot = (totalCollected.mul(_remainingCut)).div(1000);
        uint256 _winnersTimeHeld = timeHeld[winningOutcome][msgSender()];
        uint256 _numerator = _remainingPot.mul(_winnersTimeHeld);
        _winningsToTransfer = _winningsToTransfer.add(_numerator.div(totalTimeHeld[winningOutcome]));
        require(_winningsToTransfer > 0, "Not a winner");
        _payout(msgSender(), _winningsToTransfer);
        emit LogWinningsPaid(msgSender(), _winningsToTransfer);
    }

    /// @notice returns all funds to users in case of invalid outcome
    function _returnRent() internal {
        // deduct artist share and card specific share if relevant but NOT market creator share or winner's share (no winner, market creator does not deserve)
        uint256 _remainingCut = ((uint256(1000).sub(artistCut)).sub(affiliateCut)).sub(cardAffiliateCut);      
        uint256 _rentCollected = collectedPerUser[msgSender()];
        require(_rentCollected > 0, "Paid no rent");
        uint256 _rentCollectedAdjusted = (_rentCollected.mul(_remainingCut)).div(1000);
        _payout(msgSender(), _rentCollectedAdjusted);
        emit LogRentReturned(msgSender(), _rentCollectedAdjusted);
    }

    /// @notice all payouts happen through here
    function _payout(address _recipient, uint256 _amount) internal {
        assert(treasury.payout(_recipient, _amount));
    }

    /// @notice gives each Card to the longest owner
    function _processCardsAfterEvent() internal {
        for (uint i = 0; i < numberOfTokens; i++) {
            if (longestOwner[i] != address(0)) {
                // if never owned, longestOwner[i] will = zero
                _transferCard(ownerOf(i), longestOwner[i], i);
                emit LogTransferCardToLongestOwner(i, longestOwner[i]);
            } 
        }
    }

    /// @dev the below functions pay stakeholders (artist, creator, affiliate, card specific affiliates)
    /// @dev they are not called within determineWinner() because of the risk of an
    /// @dev ....  address being a contract which refuses payment, then nobody could get winnings

    /// @notice pay artist
    function payArtist() external checkState(States.WITHDRAW) {
        require(!artistPaid, "Artist already paid");
        artistPaid = true;
        _processStakeholderPayment(artistCut, artistAddress);
    }

    /// @notice pay market creator
    function payMarketCreator() external checkState(States.WITHDRAW) {
        require(totalTimeHeld[winningOutcome] > 0, "No winner");
        require(!creatorPaid, "Creator already paid");
        creatorPaid = true;
        _processStakeholderPayment(creatorCut, marketCreatorAddress);
    }

    /// @notice pay affiliate
    function payAffiliate() external checkState(States.WITHDRAW) {
        require(!affiliatePaid, "Affiliate already paid");
        affiliatePaid = true;
        _processStakeholderPayment(affiliateCut, affiliateAddress);
    }

    function _processStakeholderPayment(uint256 _cut, address _recipient) internal {
        if (_cut > 0) {
            uint256 _payment = (totalCollected.mul(_cut)).div(1000);
            _payout(_recipient, _payment);
            emit LogStakeholderPaid(_recipient, _payment);
        }
    }

    /// @notice pay card recipients
    /// @dev does not call _processStakeholderPayment because it works differently
    function payCardAffiliate() external checkState(States.WITHDRAW) {
        require(!cardAffiliatePaid, "Card recipients already paid");
        cardAffiliatePaid = true;
        if (cardAffiliateCut > 0) {
            for (uint i = 0; i < numberOfTokens; i++) {
                uint256 _cardAffiliatePayment = (collectedPerToken[i].mul(cardAffiliateCut)).div(1000);
                if (_cardAffiliatePayment > 0) {
                    _payout(cardAffiliateAddresses[i], _cardAffiliatePayment);
                }
                emit LogStakeholderPaid(cardAffiliateAddresses[i], _cardAffiliatePayment);
            }
        }
    }

    ////////////////////////////////////
    ///// CORE FUNCTIONS- EXTERNAL /////
    ////////////////////////////////////
    /// @dev basically functions that have checkState(States.OPEN) modifier

    /// @notice collects rent for all tokens
    /// @dev cannot be external because it is called within the lockContract function, therefore public
    function collectRentAllCards() public checkState(States.OPEN) {
       for (uint i = 0; i < numberOfTokens; i++) {
            _collectRent(i);
        }
    }

    /// @notice rent every Card at the minimum price
    function rentAllCards(uint256 _maxSumOfPrices) external {
        // check that not being front run
        uint256 _actualSumOfPrices;
        for (uint i = 0; i < numberOfTokens; i++) {
            _actualSumOfPrices = _actualSumOfPrices.add(price[i]);
        }
        require(_actualSumOfPrices <= _maxSumOfPrices, "Prices too high");

        for (uint i = 0; i < numberOfTokens; i++) {
            if (ownerOf(i) != msgSender()) {
                uint _newPrice;
                if (price[i]>0) {
                    _newPrice = (price[i].mul(minimumPriceIncrease.add(100))).div(100);
                } else {
                    _newPrice = 1 ether;
                }
                newRental(_newPrice, 0, address(0), i);
            }
        }
    }

    /// @notice to rent a Card
    function newRental(uint256 _newPrice, uint256 _timeHeldLimit, address _startingPosition, uint256 _tokenId) public payable autoUnlock() autoLock() checkState(States.OPEN) {
        require(_newPrice >= 1 ether, "Minimum rental 1 Dai");
        require(_tokenId < numberOfTokens, "This token does not exist");
        require(ownershipLostTimestamp[msgSender()] != now, "Cannot lose and re-rent in same block");

        _newPrice = _newPrice.mul(2);

        collectRentAllCards();

         // process deposit, if sent
        if (msg.value > 0) {
            assert(treasury.deposit.value(msg.value)(msgSender()));
        }

        // check sufficient deposit
        uint256 _minRentalTime = uint256(1 days).div(minRentalDivisor);
        require(treasury.deposits(msgSender()) >= _newPrice.div(_minRentalTime), "Insufficient deposit");

        // check _timeHeldLimit
        if (_timeHeldLimit == 0) {
            _timeHeldLimit = MAX_UINT256; // so 0 defaults to no limit
        }
        require(_timeHeldLimit >= timeHeld[_tokenId][msgSender()].add(_minRentalTime), "Limit too low"); // must be after collectRent so timeHeld is up to date

        // add to orderbook or update existing entry as appropriate
        if (orderbook[_tokenId][msgSender()].price == 0) {
            _newBid(_newPrice, _tokenId, _timeHeldLimit, _startingPosition);
        } else {
            _updateBid(_newPrice, _tokenId, _timeHeldLimit, _startingPosition);
        }

        emit LogNewRental(msgSender(), _newPrice, _timeHeldLimit, _tokenId); 
    }

    /// @notice to change your timeHeldLimit without having to re-rent
    function updateTimeHeldLimit(uint256 _timeHeldLimit, uint256 _tokenId) external checkState(States.OPEN) {
        collectRentAllCards();
        
        if (_timeHeldLimit == 0) {
            _timeHeldLimit = MAX_UINT256; // so 0 defaults to no limit
        }
        uint256 _minRentalTime = uint256(1 days).div(minRentalDivisor);
        require(_timeHeldLimit >= timeHeld[_tokenId][msgSender()].add(_minRentalTime), "Limit too low"); // must be after collectRent so timeHeld is up to date

        orderbook[_tokenId][msgSender()].timeHeldLimit = _timeHeldLimit;
        emit LogUpdateTimeHeldLimit(msgSender(), _timeHeldLimit, _tokenId); 
    }

    /// @notice stop renting a token and/or remove from orderbook
    /// @dev public because called by exitAll()
    /// @dev doesn't need to be current owner so user can prevent ownership returning to them
    function exit(uint256 _tokenId) public checkState(States.OPEN) {
        // if current owner, collect rent, revert if necessary
        if (ownerOf(_tokenId) == msgSender()) {
            // collectRent first, so correct rent to now is taken
            _collectRent(_tokenId);

            // if still the current owner after collecting rent, revert to underbidder
            if (ownerOf(_tokenId) == msgSender()) {
                _revertToUnderbidder(_tokenId);
            // if not current owner no further action necessary because they will have been deleted from the orderbook
            } else {
                assert(orderbook[_tokenId][msgSender()].price == 0);
            }
        // if not owner, just delete from orderbook
        } else {
            orderbook[_tokenId][orderbook[_tokenId][msgSender()].next].prev = orderbook[_tokenId][msgSender()].prev;
            orderbook[_tokenId][orderbook[_tokenId][msgSender()].prev].next = orderbook[_tokenId][msgSender()].next;
            delete orderbook[_tokenId][msgSender()];
        }
        emit LogExit(msgSender(), _tokenId, true); 
    }

    /// @notice stop renting all tokens
    function exitAll() external {
        for (uint i = 0; i < numberOfTokens; i++) {
            exit(i);
        }
    }

    /// @notice ability to add liqudity to the pot without being able to win. 
    function sponsor() external payable {
        require(msg.value > 0, "Must send something");
        require(state != States.LOCKED, "Incorrect state");
        require(state != States.WITHDRAW, "Incorrect state");
        // send funds to the Treasury
        assert(treasury.sponsor.value(msg.value)());
        totalCollected = totalCollected.add(msg.value);
        // just so user can get it back if invalid outcome
        collectedPerUser[msgSender()] = collectedPerUser[msgSender()].add(msg.value); 
        // allocate equally to each token, in case card specific affiliates
        for (uint i = 0; i < numberOfTokens; i++) {
            collectedPerToken[i] =  collectedPerToken[i].add(msg.value.div(numberOfTokens));
        }
        emit LogSponsor(msg.value); 
    }

    ////////////////////////////////////
    ///// CORE FUNCTIONS- INTERNAL /////
    ////////////////////////////////////

    /// @notice collects rent for a specific token
    /// @dev also calculates and updates how long the current user has held the token for
    /// @dev is not a problem if called externally, but making internal over public to save gas
    function _collectRent(uint256 _tokenId) internal {
        uint256 _timeOfThisCollection = now;

        //only collect rent if the token is owned (ie, if owned by the contract this implies unowned)
        if (ownerOf(_tokenId) != address(this)) {
            uint256 _rentOwed = price[_tokenId].mul(now.sub(timeLastCollected[_tokenId])).div(1 days);
            address _collectRentFrom = ownerOf(_tokenId);
            uint256 _deposit = treasury.deposits(_collectRentFrom);
            
            // get the maximum rent they can pay based on timeHeldLimit
            uint256 _rentOwedLimit;
            uint256 _timeHeldLimit = orderbook[_tokenId][_collectRentFrom].timeHeldLimit;
            if (_timeHeldLimit == MAX_UINT256) {
                _rentOwedLimit = MAX_UINT256;
            } else {
                _rentOwedLimit = price[_tokenId].mul(_timeHeldLimit.sub(timeHeld[_tokenId][_collectRentFrom])).div(1 days);
            }

            // if rent owed is too high, reduce
            if (_rentOwed >= _deposit || _rentOwed >= _rentOwedLimit)  {
                // case 1: rentOwed is reduced to _deposit
                if (_deposit <= _rentOwedLimit)
                {
                    _timeOfThisCollection = timeLastCollected[_tokenId].add(((now.sub(timeLastCollected[_tokenId])).mul(_deposit).div(_rentOwed)));
                    _rentOwed = _deposit; // take what's left     
                // case 2: rentOwed is reduced to _rentOwedLimit
                } else {
                    _timeOfThisCollection = timeLastCollected[_tokenId].add(((now.sub(timeLastCollected[_tokenId])).mul(_rentOwedLimit).div(_rentOwed)));
                    _rentOwed = _rentOwedLimit; // take up to the max   
                }
                _revertToUnderbidder(_tokenId);
            } 

            if (_rentOwed > 0) {
                // decrease deposit by rent owed at the Treasury
                assert(treasury.payRent(_collectRentFrom, _rentOwed));
                // update internals
                uint256 _timeHeldToIncrement = (_timeOfThisCollection.sub(timeLastCollected[_tokenId]));
                timeHeld[_tokenId][_collectRentFrom] = timeHeld[_tokenId][_collectRentFrom].add(_timeHeldToIncrement);
                totalTimeHeld[_tokenId] = totalTimeHeld[_tokenId].add(_timeHeldToIncrement);
                collectedPerUser[_collectRentFrom] = collectedPerUser[_collectRentFrom].add(_rentOwed);
                collectedPerToken[_tokenId] = collectedPerToken[_tokenId].add(_rentOwed);
                totalCollected = totalCollected.add(_rentOwed);

                // longest owner tracking
                if (timeHeld[_tokenId][_collectRentFrom] > longestTimeHeld[_tokenId]) {
                    longestTimeHeld[_tokenId] = timeHeld[_tokenId][_collectRentFrom];
                    longestOwner[_tokenId] = _collectRentFrom;
                }

                emit LogTimeHeldUpdated(timeHeld[_tokenId][_collectRentFrom], _collectRentFrom, _tokenId);
                emit LogRentCollection(_rentOwed, _tokenId, _collectRentFrom);
            } 
        }

        // timeLastCollected is updated regardless of whether the token is owned, so that the clock starts ticking
        // ... when the first owner buys it, because this function is run before ownership changes upon calling newRental
        timeLastCollected[_tokenId] = _timeOfThisCollection;
    }

    /// @dev user is not in the orderbook
    function _newBid(uint256 _newPrice, uint256 _tokenId, uint256 _timeHeldLimit, address _startingPosition) internal 
    {
        // check user not in the orderbook
        assert(orderbook[_tokenId][msgSender()].price == 0);
        uint256 _minPriceToOwn = (price[_tokenId].mul(minimumPriceIncrease.add(100))).div(100);
        // case 1: user is sufficiently above highest bidder (or only bidder)
        if(ownerOf(_tokenId) == address(this) || _newPrice >= _minPriceToOwn) {
            _setNewOwner(_newPrice, _tokenId, _timeHeldLimit);
        } else {
        // case 2: user is not sufficiently above highest bidder
            _placeInList(_newPrice, _tokenId, _timeHeldLimit, _startingPosition);
        }
    }

    /// @dev user is already in the orderbook
    function _updateBid(uint256 _newPrice, uint256 _tokenId, uint256 _timeHeldLimit, address _startingPosition) internal 
    {
        uint256 _minPriceToOwn;
        // ensure user is in the orderbook
        assert(orderbook[_tokenId][msgSender()].price > 0);
        // case 1: user is currently the owner
        if(msgSender() == ownerOf(_tokenId)) { 
            _minPriceToOwn = (price[_tokenId].mul(minimumPriceIncrease.add(100))).div(100);
            // case 1A: new price is at least X% above current price- adjust price & timeHeldLimit
            if(_newPrice >= _minPriceToOwn) {
                orderbook[_tokenId][msgSender()].price = _newPrice;
                orderbook[_tokenId][msgSender()].timeHeldLimit = _timeHeldLimit;
                price[_tokenId] = _newPrice;
            // case 1B: new price is higher than current price but by less than X%- remove from list and do not add back
            } else if (_newPrice > price[_tokenId]) {
                _revertToUnderbidder(_tokenId);
            // case 1C: new price is equal or below old price
            } else {
                _minPriceToOwn = (orderbook[_tokenId][orderbook[_tokenId][msgSender()].next].price.mul(minimumPriceIncrease.add(100))).div(100);
                // case 1Ca: still the highest owner- adjust price & timeHeldLimit
                if(_newPrice >= _minPriceToOwn) {
                    orderbook[_tokenId][msgSender()].price = _newPrice;
                    orderbook[_tokenId][msgSender()].timeHeldLimit = _timeHeldLimit;
                    price[_tokenId] = _newPrice;
                // case 1Cb: user is not owner anymore-  remove from list & add back
                } else {
                    _revertToUnderbidder(_tokenId);
                    _newBid(_newPrice, _tokenId, _timeHeldLimit, _startingPosition);
                }
            }
        // case 2: user is not currently the owner- remove and add them back 
        } else {
            // remove from the list
            orderbook[_tokenId][orderbook[_tokenId][msgSender()].prev].next = orderbook[_tokenId][msgSender()].next;
            orderbook[_tokenId][orderbook[_tokenId][msgSender()].next].prev = orderbook[_tokenId][msgSender()].prev; 
            delete orderbook[_tokenId][msgSender()];
            // check if should be owner, add on top if so, otherwise _placeInList
            _minPriceToOwn = (price[_tokenId].mul(minimumPriceIncrease.add(100))).div(100);
            if(_newPrice >= _minPriceToOwn) 
            {  
                _setNewOwner(_newPrice, _tokenId, _timeHeldLimit);
            } else {
                _placeInList(_newPrice, _tokenId, _timeHeldLimit, _startingPosition);
            } 
        }
    }

    /// @dev only for when user is NOT already in the list and IS the highest bidder
    function _setNewOwner(uint256 _newPrice, uint256 _tokenId, uint256 _timeHeldLimit) internal 
    {  
        // if hot potato mode, pay current owner
        if (mode == 2) {
            // the required payment is calculated in the Treasury
            // assert(treasury.payCurrentOwner(msgSender(), ownerOf(_tokenId), price[_tokenId]));
        }

        // process new owner
        orderbook[_tokenId][msgSender()] = Bid(_newPrice, _timeHeldLimit, ownerOf(_tokenId), address(this));
        orderbook[_tokenId][ownerOf(_tokenId)].prev = msgSender();
        price[_tokenId] = _newPrice;
        _transferCard(ownerOf(_tokenId), msgSender(), _tokenId);
    }

    /// @dev only for when user is NOT already in the list and NOT the highest bidder
    function _placeInList(uint256 _newPrice, uint256 _tokenId, uint256 _timeHeldLimit, address _startingPosition) internal
    {
        // if starting position is not set, start at the top
        if (_startingPosition == address(0)) {
            _startingPosition = ownerOf(_tokenId);
            // _newPrice could be the highest, but not X% above owner, hence _newPrice must be reduced or require statement below would fail
            if (orderbook[_tokenId][_startingPosition].price <_newPrice) {
                _newPrice = orderbook[_tokenId][_startingPosition].price;
            }
        }

        // check the starting location is not too low down the list
        require(orderbook[_tokenId][_startingPosition].price >= _newPrice, "Invalid starting location");

        address _tempNext = _startingPosition;
        address _tempPrev;
        uint256 _loopCount;
        uint256 _requiredPrice;

        // loop through orderbook until bid is at least _requiredPrice above that user
        do {
            _tempPrev = _tempNext;
            _tempNext = orderbook[_tokenId][_tempPrev].next;
            _requiredPrice = (orderbook[_tokenId][_tempNext].price.mul(minimumPriceIncrease.add(100))).div(100);
            _loopCount = _loopCount.add(1);
        } while (
            _newPrice < _requiredPrice && // equal to or above is ok
            _loopCount < MAX_ITERATIONS );
        require(_loopCount < MAX_ITERATIONS, "Incorrect starting location");

        // reduce user's price to the user above them in the list if necessary, so prices are in order
        if (orderbook[_tokenId][_tempPrev].price < _newPrice) {
            _newPrice = orderbook[_tokenId][_tempPrev].price;
        }

        // add to the list
        orderbook[_tokenId][msgSender()] = Bid(_newPrice, _timeHeldLimit, _tempNext, _tempPrev);
        orderbook[_tokenId][_tempPrev].next = msgSender();
        orderbook[_tokenId][_tempNext].prev = msgSender();
    }

    /// @notice if a users deposit runs out, either return to previous owner or foreclose
    function _revertToUnderbidder(uint256 _tokenId) internal {
        address _tempNext = ownerOf(_tokenId);
        address _tempPrev;
        uint256 _tempNextDeposit;
        uint256 _requiredDeposit;
        uint256 _loopCount;

        // loop through orderbook list for user with sufficient deposit, deleting users who fail the test
        do {
            // get the address of next person in the list
            _tempPrev = _tempNext;
            _tempNext = orderbook[_tokenId][_tempPrev].next;
            // remove the previous user
            orderbook[_tokenId][_tempNext].prev = address(this);
            delete orderbook[_tokenId][_tempPrev];
            // get required  and actual deposit of next user
            _tempNextDeposit = treasury.deposits(_tempNext);
            _requiredDeposit = orderbook[_tokenId][_tempNext].price.div(minRentalDivisor);
            _loopCount = _loopCount.add(1);
        } while (
            _tempNext != address(this) && 
            _tempNextDeposit < _requiredDeposit && 
            _loopCount < MAX_ITERATIONS );
        if (_tempNext == address(this)) {
            _foreclose(_tokenId);
        } else {
             // transfer to previous owner
            address _currentOwner = ownerOf(_tokenId);
            price[_tokenId] = orderbook[_tokenId][_tempNext].price;
            ownershipLostTimestamp[ownerOf(_tokenId)] = now;
            _transferCard(_currentOwner, _tempNext, _tokenId);
            emit LogCardTransferredToUnderbidder(_tokenId, _tempNext);
        }
    }

    /// @notice return token to the contract and return price to zero
    function _foreclose(uint256 _tokenId) internal {
        address _currentOwner = ownerOf(_tokenId);
        price[_tokenId] = 0;
        _transferCard(_currentOwner, address(this), _tokenId);
        emit LogForeclosure(_currentOwner, _tokenId);
    }

     /// @dev should only be called thrice
    function _incrementState() internal {
        assert(uint256(state) < 4);
        state = States(uint256(state) + 1);
        emit LogStateChange(uint256(state));
    }

    ////////////////////////////////////
    /////////// CIRCUIT BREAKER ////////
    ////////////////////////////////////

    /// @dev alternative to determineWinner, in case Oracle never resolves for any reason
    /// @dev does not set a winner so same as invalid outcome
    /// @dev market does not need to be locked, just in case lockMarket bugs out
    function circuitBreaker() external {
        require(now > (oracleResolutionTime + 12 weeks), "Too early");
        _incrementState();
        _processCardsAfterEvent(); 
        state = States.WITHDRAW;
    }

}
