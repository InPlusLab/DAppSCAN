pragma solidity 0.5.13;

import "@openzeppelin/contracts/token/ERC721/ERC721Full.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@nomiclabs/buidler/console.sol";
import "./interfaces/ICash.sol";
import "./interfaces/IRealitio.sol";

/// @title RealityCards
/// @author Andrew Stanger

contract RealityCards is ERC721Full, Ownable {

    using SafeMath for uint256;

    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    ///// CONTRACT SETUP /////
    /// @dev = how many outcomes/teams/NFTs etc 
    uint256 public numberOfTokens;
    /// @dev counts how many NFTs have been minted 
    /// @dev when nftMintCount = numberOfTokens, increment state
    // SWC-135-Code With No Effects: L27
    uint256 private nftMintCount;
    /// @dev the question ID of the question on realitio
    bytes32 public questionId;
    /// @dev only for _revertToPreviousOwner to prevent gas limits
    uint256 constant private MAX_ITERATIONS = 10;
    enum States {NFTSNOTMINTED, OPEN, LOCKED, WITHDRAW}
    States public state; 

    ///// CONTRACT VARIABLES /////
    IRealitio public realitio;
    ICash public cash; 

    ///// PRICE, DEPOSITS, RENT /////
    /// @dev in attodai (so $100 = 100000000000000000000)
    mapping (uint256 => uint256) public price; 
    /// @dev keeps track of all the deposits for each token, for each owner
    mapping (uint256 => mapping (address => uint256) ) public deposits; 
    /// @dev keeps track of all the rent paid by each user. So that it can be returned in case of an invalid market outcome.
    mapping (address => uint256) public collectedPerUser;
    /// @dev keeps track of all the rent paid for each token, front end only
    mapping (uint256 => uint256) public collectedPerToken;
    /// @dev an easy way to track the above across all tokens
    uint256 public totalCollected; 

    ///// TIME /////
    /// @dev how many seconds each user has held each token for, for determining winnings  
    mapping (uint256 => mapping (address => uint256) ) public timeHeld;
    /// @dev sums all the timeHelds for each. Not required, but saves on gas when paying out. Should always increment at the same time as timeHeld
    mapping (uint256 => uint256) public totalTimeHeld; 
    /// @dev used to determine the rent due. Rent is due for the period (now - timeLastCollected), at which point timeLastCollected is set to now.
    mapping (uint256 => uint256) public timeLastCollected; 
    /// @dev when a token was bought. Used to enforce minimum of one hour rental, also used in front end. Rent collection does not need this, only needs timeLastCollected.
    mapping (uint256 => uint256) public timeAcquired; 

    ///// PREVIOUS OWNERS /////
    /// @dev keeps track of all previous owners of a token, including the price, so that if the current owner's deposit runs out,
    /// @dev ...ownership can be reverted to a previous owner with the previous price. Index 0 is NOT used, this tells the contract to foreclose.
    /// @dev this does NOT keep a reliable list of all owners, if it reverts to a previous owner then the next owner will overwrite the owner that was in that slot.
    mapping (uint256 => mapping (uint256 => rental) ) public ownerTracker;  
    /// @dev tracks the position of the current owner in the ownerTracker mapping
    mapping (uint256 => uint256) public currentOwnerIndex; 
    /// @dev the struct for ownerTracker
    struct rental { address owner;
                    uint256 price; }
    /// @dev array of all owners of a token (for front end)
    mapping (uint256 => address[]) public allOwners;
    /// @dev preventing duplicates in allOwners
    mapping (uint256 => mapping (address => bool)) private inAllOwners;

    ///// MARKET RESOLUTION VARIABLES /////
    uint256 public winningOutcome; 
    //// @dev when the question can be answered on Realitio. 
    uint32 public marketExpectedResolutionTime; 
    /// @dev If false, normal payout. If true, return all funds. Default true
    bool public questionResolvedInvalid = true; 
    /// @dev prevent users withdrawing twice
    mapping (address => bool) public userAlreadyWithdrawn;

    ////////////////////////////////////
    //////// CONSTRUCTOR ///////////////
    ////////////////////////////////////

    constructor(
        address _owner, 
        uint256 _numberOfTokens, 
        ICash _addressOfCashContract, 
        IRealitio _addressOfRealitioContract, 
        uint32 _marketExpectedResolutionTime, 
        uint256 _templateId, 
        string memory _question, 
        address _arbitrator, 
        uint32 _timeout) 
        ERC721Full("realitycards.io", "RC") public
    {
        // reassign ownership (because deployed using public seed)
        transferOwnership(_owner);

        // assign arguments to public variables
        numberOfTokens = _numberOfTokens;
        marketExpectedResolutionTime = _marketExpectedResolutionTime;
        
        // external contract variables:
        realitio = _addressOfRealitioContract;
        cash = _addressOfCashContract;

        // Create the question on Realitio
        questionId = _postQuestion(_templateId, _question, _arbitrator, _timeout, _marketExpectedResolutionTime, 0);
    } 

    ////////////////////////////////////
    //////// EVENTS ////////////////////
    ////////////////////////////////////

    event LogNewRental(address indexed newOwner, uint256 indexed newPrice, uint256 indexed tokenId);
    event LogPriceChange(uint256 indexed newPrice, uint256 indexed tokenId);
    event LogForeclosure(address indexed prevOwner, uint256 indexed tokenId);
    event LogRentCollection(uint256 indexed rentCollected, uint256 indexed tokenId);
    event LogReturnToPreviousOwner(uint256 indexed tokenId, address indexed previousOwner);
    event LogDepositWithdrawal(uint256 indexed daiWithdrawn, uint256 indexed tokenId, address indexed returnedTo);
    event LogDepositIncreased(uint256 indexed daiDeposited, uint256 indexed tokenId, address indexed sentBy);
    event LogContractLocked(bool indexed didTheEventFinish);
    event LogWinnerKnown(uint256 indexed winningOutcome);
    event LogWinningsPaid(address indexed paidTo, uint256 indexed amountPaid);
    event LogRentReturned(address indexed returnedTo, uint256 indexed amountReturned);
    event LogTimeHeldUpdated(uint256 indexed newTimeHeld, address indexed owner, uint256 indexed tokenId);


    ////////////////////////////////////
    //////// INITIAL SETUP /////////////
    ////////////////////////////////////

    function mintNfts(string calldata _uri) external checkState(States.NFTSNOTMINTED) {
        _mint(address(this), nftMintCount); 
        _setTokenURI(nftMintCount, _uri);
        nftMintCount = nftMintCount.add(1);
        if (nftMintCount == numberOfTokens) {
            _incrementState();
        }
    }

    ////////////////////////////////////
    /////////// MODIFIERS //////////////
    ////////////////////////////////////

    modifier checkState(States currentState) {
        require(state == currentState, "Incorrect state");
        _;
    }

    /// @notice checks the token exists
    modifier tokenExists(uint256 _tokenId) {
        require(_tokenId < numberOfTokens, "This token does not exist");
       _;
    }

    /// @notice what it says on the tin
    modifier amountNotZero(uint256 _dai) {
        require(_dai > 0, "Amount must be above zero");
       _;
    }

    /// @notice what it says on the tin
    modifier onlyTokenOwner(uint256 _tokenId) {
        require(msg.sender == ownerOf(_tokenId), "Not owner");
       _;
    }

    ////////////////////////////////////
    //////// VIEW FUNCTIONS ////////////
    ////////////////////////////////////

    /// @dev called in collectRent function, and various other view functions 
    function rentOwed(uint256 _tokenId) public view returns (uint256) {
        return price[_tokenId].mul(now.sub(timeLastCollected[_tokenId])).div(1 days);
    }

    /// @dev for front end only
    /// @return how much the current owner has left of their deposit after deducting rent owed but not paid
    function currentOwnerRemainingDeposit(uint256 _tokenId) public view returns (uint256) {
        uint256 _rentOwed = rentOwed(_tokenId);
        address _currentOwner = ownerOf(_tokenId);
        if(_rentOwed >= deposits[_tokenId][_currentOwner]) {
            return 0;
        } else {
            return deposits[_tokenId][_currentOwner].sub(_rentOwed);
        }
    }

    /// @dev for front end only
    /// @return how much the user has deposited (note: user not owner)
    // SWC-135-Code With No Effects: L198-204
    function userRemainingDeposit(uint256 _tokenId) external view returns (uint256) {
        if(ownerOf(_tokenId) == msg.sender) {
            return currentOwnerRemainingDeposit(_tokenId);
        } else {
            return deposits[_tokenId][msg.sender];
        }
    }

    /// @dev for front end only
    /// @return rental expiry time given current contract state
    function rentalExpiryTime(uint256 _tokenId) external view returns (uint256) {
        uint256 pps;
        pps = price[_tokenId].div(1 days);
        // SWC-135-Code With No Effects: L212-214
        if (pps == 0) {
            return now; //if price is so low that pps = 0 just return current time as a fallback
        }
        else {
            return now + currentOwnerRemainingDeposit(_tokenId).div(pps);
        }
    }

    /// @dev for front end and _payoutWinnings function
    function getWinnings(uint256 _winningOutcome) public view returns (uint256) {
        uint256 _winnersTimeHeld = timeHeld[_winningOutcome][msg.sender];
        uint256 _numerator = totalCollected.mul(_winnersTimeHeld);
        uint256 _winnings = _numerator.div(totalTimeHeld[_winningOutcome]);    
        return _winnings;    
    }
    
    ////////////////////////////////////
    ///// EXTERNAL DAI FUNCTIONS ///////
    ////////////////////////////////////

    /// @notice common function for all outgoing DAI transfers
    function _sendCash(address _to, uint256 _amount) internal { 
        require(cash.transfer(_to,_amount), "Cash transfer failed"); 
    }

    /// @notice common function for all incoming DAI transfers
    function _receiveCash(address _from, uint256 _amount) internal {  
        require(cash.transferFrom(_from, address(this), _amount), "Cash transfer failed");
    }

    ////////////////////////////////////
    //// EXTERNAL REALITIO FUNCTIONS ///
    ////////////////////////////////////

    /// @notice posts the question to realit.io
    function _postQuestion(uint256 template_id, string memory question, address arbitrator, uint32 timeout, uint32 opening_ts, uint256 nonce) internal returns (bytes32) {
        return realitio.askQuestion(template_id, question, arbitrator, timeout, opening_ts, nonce);
    }

    /// @notice gets the winning outcome from realitio
    /// @dev the returned value is equivilent to tokenId
    /// @dev this function call will revert if it has not yet resolved
    function _getWinner() internal view returns(uint256) {
        bytes32 _winningOutcome = realitio.resultFor(questionId);
        return uint256(_winningOutcome);
    }

    /// @notice has the question been finalized on realitio?
    function _isQuestionFinalized() internal view returns (bool) {
        return realitio.isFinalized(questionId);
    }

    ////////////////////////////////////
    //// MARKET RESOLUTION FUNCTIONS ///
    ////////////////////////////////////

    /// @notice checks whether the competition has ended (1 hour grace), if so moves to LOCKED state
    /// @dev can be called by anyone 
    function lockContract() external checkState(States.OPEN) {
        require(marketExpectedResolutionTime < (now - 1 hours), "Market has not finished");
        // do a final rent collection before the contract is locked down
        collectRentAllTokens();
        _incrementState();
        emit LogContractLocked(true);
    }
    /// @notice checks whether the Realitio question has resolved, and if yes, gets the winner
    /// @dev can be called by anyone 
    function determineWinner() external checkState(States.LOCKED) {
        require(_isQuestionFinalized() == true, "Oracle not resolved");
        // get the winner. This will revert if answer is not resolved.
        winningOutcome = _getWinner();
        // check if question resolved invalid
        if (winningOutcome !=  ((2**256)-1)) {
            questionResolvedInvalid = false;
        }
        _incrementState();
        emit LogWinnerKnown(winningOutcome);
    }

    /// @notice pays out winnings, or returns funds, based on questionResolvedInvalid bool
    function withdraw() external checkState(States.WITHDRAW) {
        require(!userAlreadyWithdrawn[msg.sender], "Already withdrawn");
        userAlreadyWithdrawn[msg.sender] = true;
        if (!questionResolvedInvalid) {
            _payoutWinnings();
        } else {
             _returnRent();
        }
    }

    /// @notice pays winnings
    function _payoutWinnings() internal {
        uint256 _winningsToTransfer = getWinnings(winningOutcome);
        require(_winningsToTransfer > 0, "Not a winner");
        _sendCash(msg.sender, _winningsToTransfer);
        emit LogWinningsPaid(msg.sender, _winningsToTransfer);
    }

    /// @notice returns all funds to users in case of invalid outcome
    function _returnRent() internal {
        uint256 _rentCollected = collectedPerUser[msg.sender];
        require(_rentCollected > 0, "Paid no rent");
        _sendCash(msg.sender, _rentCollected);
        emit LogRentReturned(msg.sender, _rentCollected);
    }

    /// @notice withdraw full deposit after markets have resolved
    /// @dev the other withdraw deposit functions are locked when markets have closed so must use this one
    /// @dev can be called in either locked or withdraw state
    /// @dev this function is also different in that it does 
    /// @dev ... not attempt to collect rent or transfer ownership to a previous owner
    function withdrawDepositAfterMarketEnded() external {
        require(state != States.NFTSNOTMINTED, "Incorrect state");
        require(state != States.OPEN, "Incorrect state");
        for (uint i = 0; i < numberOfTokens; i++) {

            uint256 _depositToReturn = deposits[i][msg.sender];

            if (_depositToReturn > 0) {
                deposits[i][msg.sender] = 0;
                _sendCash(msg.sender, _depositToReturn);
                emit LogDepositWithdrawal(_depositToReturn, i, msg.sender);
            }
        }
    }

    ////////////////////////////////////
    ///// MAIN FUNCTIONS- EXTERNAL /////
    ////////////////////////////////////
    /// @dev basically functions that have checkState(States.OPEN) modifier

    /// @notice collects rent for all tokens
    /// @dev cannot be external because it is called within the lockContract function, therefore public
    function collectRentAllTokens() public checkState(States.OPEN) {
       for (uint i = 0; i < numberOfTokens; i++) {
            _collectRent(i);
        }
    }
    
    /// @notice to rent a token
    function newRental(uint256 _newPrice, uint256 _tokenId, uint256 _deposit) external checkState(States.OPEN) tokenExists(_tokenId) amountNotZero(_deposit) {
        uint256 _currentPricePlusTenPercent = price[_tokenId].mul(11).div(10);
        uint256 _oneHoursDeposit = _newPrice.div(24);
        require(_newPrice >= _currentPricePlusTenPercent, "Price not 10% higher");
        require(_deposit >= _oneHoursDeposit, "One hour's rent minimum");
        require(_newPrice >= 0.01 ether, "Minimum rental 0.01 Dai");
        
        _collectRent(_tokenId);
        _depositDai(_deposit, _tokenId);

        address _currentOwner = ownerOf(_tokenId);

        if (_currentOwner == msg.sender) { // bought by current owner- just change price
            _changePrice(_newPrice, _tokenId);
        } else {   // bought by new user- the normal flow
            // update internals
            currentOwnerIndex[_tokenId] = currentOwnerIndex[_tokenId].add(1); 
            ownerTracker[_tokenId][currentOwnerIndex[_tokenId]].price = _newPrice;
            ownerTracker[_tokenId][currentOwnerIndex[_tokenId]].owner = msg.sender; 
            timeAcquired[_tokenId] = now;
            // just for front end:
            if (!inAllOwners[_tokenId][msg.sender]) {
                inAllOwners[_tokenId][msg.sender] = true;
                allOwners[_tokenId].push(msg.sender);
            }
            // externals
            _transferTokenTo(_currentOwner, msg.sender, _newPrice, _tokenId);
            emit LogNewRental(msg.sender, _newPrice, _tokenId); 
        }
    }

    /// @notice add new dai deposit to an existing rental
    /// @dev it is possible a user's deposit could be reduced to zero following _collectRent
    /// @dev they would then increase their deposit despite no longer owning it
    /// @dev this is ok, they can still withdraw via withdrawDeposit. 
    /// @dev can be called by anyone- you can top up someone else's deposit if you wish!
    function depositDai(uint256 _dai, uint256 _tokenId) external checkState(States.OPEN) amountNotZero(_dai) tokenExists(_tokenId) {
        _collectRent(_tokenId);
        _depositDai(_dai, _tokenId);
    }

    /// @notice increase the price of an existing rental
    /// @dev 10% price increase not required for existing owners
    function changePrice(uint256 _newPrice, uint256 _tokenId) external checkState(States.OPEN) tokenExists(_tokenId) onlyTokenOwner(_tokenId) {
        require(_newPrice > price[_tokenId], "New price must be higher"); 
        _collectRent(_tokenId);
        _changePrice(_newPrice, _tokenId);
    }
    
    /// @notice withdraw deposit
    /// @dev do not need to be the current owner
    /// @dev public because called by exit
    function withdrawDeposit(uint256 _daiToWithdraw, uint256 _tokenId) public checkState(States.OPEN) tokenExists(_tokenId) amountNotZero(_daiToWithdraw) {
        _collectRent(_tokenId);
        uint256 _remainingDeposit = deposits[_tokenId][msg.sender];
        // deposits may be lower (or zero) then when function called due to _collectRent 
        if (_remainingDeposit > 0) { 
            if (_remainingDeposit < _daiToWithdraw) {
                _daiToWithdraw = _remainingDeposit;
            }
            _withdrawDeposit(_daiToWithdraw, _tokenId);
            emit LogDepositWithdrawal(_daiToWithdraw, _tokenId, msg.sender);
        }
    }

    /// @notice withdraw full deposit
    /// @dev do not need to be the current owner
    /// @dev no modifiers because they are on withdrawDeposit
    function exit(uint256 _tokenId) external {
        withdrawDeposit(deposits[_tokenId][msg.sender], _tokenId);
    }

    /// @notice withdraw full deposit for all tokens
    /// @dev do not need to be the current owner
    /// @dev no modifiers because they are on withdrawDeposit
    function exitAll() external {
        for (uint i = 0; i < numberOfTokens; i++) {
            uint256 _remainingDeposit = deposits[i][msg.sender];
            if (_remainingDeposit > 0) { 
                withdrawDeposit(_remainingDeposit, i);
            }
        }
    }

    ////////////////////////////////////
    ///// MAIN FUNCTIONS- INTERNAL /////
    ////////////////////////////////////

    /// @notice collects rent for a specific token
    /// @dev also calculates and updates how long the current user has held the token for
    /// @dev is not a problem if called externally, but making internal over public to save gas
    function _collectRent(uint256 _tokenId) internal {
        //only collect rent if the token is owned (ie, if owned by the contract this implies unowned)
        if (ownerOf(_tokenId) != address(this)) {
            
            uint256 _rentOwed = rentOwed(_tokenId);
            address _currentOwner = ownerOf(_tokenId);
            uint256 _timeOfThisCollection;
            
            if (_rentOwed >= deposits[_tokenId][_currentOwner]) {
                // run out of deposit. Calculate time it was actually paid for, then revert to previous owner 
                _timeOfThisCollection = timeLastCollected[_tokenId].add(((now.sub(timeLastCollected[_tokenId])).mul(deposits[_tokenId][_currentOwner]).div(_rentOwed)));
                _rentOwed = deposits[_tokenId][_currentOwner]; // take what's left     
                _revertToPreviousOwner(_tokenId);
                
            } else  {
                // normal collection
                _timeOfThisCollection = now;
            }

            // decrease deposit by rent owed
            deposits[_tokenId][_currentOwner] = deposits[_tokenId][_currentOwner].sub(_rentOwed);

            // update time held and amount collected variables
            uint256 _timeHeldToIncrement = (_timeOfThisCollection.sub(timeLastCollected[_tokenId])); 
            // note that if _revertToPreviousOwner was called above, _currentOwner will no longer refer to the
            // ... actual current owner. This is correct- we are updating the variables of the user who just
            // ... had their rent collected, not the new owner, if there is one
            timeHeld[_tokenId][_currentOwner] = timeHeld[_tokenId][_currentOwner].add(_timeHeldToIncrement);
            totalTimeHeld[_tokenId] = totalTimeHeld[_tokenId].add(_timeHeldToIncrement);
            collectedPerUser[_currentOwner] = collectedPerUser[_currentOwner].add(_rentOwed);
            collectedPerToken[_tokenId] = collectedPerToken[_tokenId].add(_rentOwed);
            totalCollected = totalCollected.add(_rentOwed);

            emit LogTimeHeldUpdated(timeHeld[_tokenId][_currentOwner], _currentOwner, _tokenId);
            emit LogRentCollection(_rentOwed, _tokenId);
        }

        // timeLastCollected is updated regardless of whether the token is owned, so that the clock starts ticking
        // ... when the first owner buys it, because this function is run before ownership changes upon calling
        // ... newRental
        timeLastCollected[_tokenId] = now;
    }

    /// @dev depositDai is split into two, because it needs to be called direct from newRental
    /// @dev ... without collecing rent first (otherwise it would be collected twice, possibly causing logic errors)
    function _depositDai(uint256 _dai, uint256 _tokenId) internal {
        deposits[_tokenId][msg.sender] = deposits[_tokenId][msg.sender].add(_dai);
        _receiveCash(msg.sender, _dai);
        emit LogDepositIncreased(_dai, _tokenId, msg.sender);
    }

    /// @dev changePrice is split into two, because it needs to be called direct from newRental
    /// @dev ... without collecing rent first (otherwise it would be collected twice, possibly causing logic errors)
    function _changePrice(uint256 _newPrice, uint256 _tokenId) internal {
        // below is the only instance when price is modifed outside of the _transferTokenTo function
        price[_tokenId] = _newPrice;
        ownerTracker[_tokenId][currentOwnerIndex[_tokenId]].price = _newPrice;
        emit LogPriceChange(price[_tokenId], _tokenId);
    }

    /// @notice actually withdraw the deposit and call _revertToPreviousOwner if necessary
    function _withdrawDeposit(uint256 _daiToWithdraw, uint256 _tokenId) internal {
        assert(deposits[_tokenId][msg.sender] >= _daiToWithdraw);
        address _currentOwner = ownerOf(_tokenId);

        // must rent for minimum of 1 hour for current owner
        if(_currentOwner == msg.sender) {
            uint256 _oneHour = 3600;
            uint256 _secondsOwned = now.sub(timeAcquired[_tokenId]);
            if (_secondsOwned < _oneHour) { 
                uint256 _oneHoursDeposit = price[_tokenId].div(24);
                uint256 _secondsStillToPay = _oneHour.sub(_secondsOwned);
                uint256 _minDepositToLeave = _oneHoursDeposit.mul(_secondsStillToPay).div(_oneHour);
                uint256 _maxDaiToWithdraw = deposits[_tokenId][msg.sender].sub(_minDepositToLeave);
                if (_maxDaiToWithdraw < _daiToWithdraw) {
                    _daiToWithdraw = _maxDaiToWithdraw;
                }
            }
        }

        deposits[_tokenId][msg.sender] = deposits[_tokenId][msg.sender].sub(_daiToWithdraw);
        
        if(_currentOwner == msg.sender && deposits[_tokenId][msg.sender] == 0) {
            _revertToPreviousOwner(_tokenId);
        }
        _sendCash(msg.sender, _daiToWithdraw);
    }

    /// @notice if a users deposit runs out, either return to previous owner or foreclose
    function _revertToPreviousOwner(uint256 _tokenId) internal {
        uint256 _index;
        address _previousOwner;

        // loop max ten times before just assigning it to that owner, to prevent block limit
        for (uint i=0; i < MAX_ITERATIONS; i++)  {
            currentOwnerIndex[_tokenId] = currentOwnerIndex[_tokenId].sub(1); // currentOwnerIndex will now point to  previous owner
            _index = currentOwnerIndex[_tokenId]; // just for readability
            _previousOwner = ownerTracker[_tokenId][_index].owner;

            // if no previous owners. price -> zero, foreclose
            if (_index == 0) {
                _foreclose(_tokenId);
                break;
            } else if (deposits[_tokenId][_previousOwner] > 0) {
                break;
            }  
        }   

        // if the above loop did not end in foreclose, then transfer to previous owner
        if (ownerOf(_tokenId) != address(this)) {
            address _currentOwner = ownerOf(_tokenId);
            uint256 _oldPrice = ownerTracker[_tokenId][_index].price;
            _transferTokenTo(_currentOwner, _previousOwner, _oldPrice, _tokenId);
            emit LogReturnToPreviousOwner(_tokenId, _previousOwner);
        }
    }

    /// @notice return token to the contract and return price to zero
    function _foreclose(uint256 _tokenId) internal {
        address _currentOwner = ownerOf(_tokenId);
        // third field is price, ie price goes to zero
        _transferTokenTo(_currentOwner, address(this), 0, _tokenId);
        emit LogForeclosure(_currentOwner, _tokenId);
    }

    /// @notice transfer ERC 721 between users
    /// @dev there is no event emitted as this is handled in ERC721.sol
    function _transferTokenTo(address _currentOwner, address _newOwner, uint256 _newPrice, uint256 _tokenId) internal {
        require(_currentOwner != address(0) && _newOwner != address(0) , "Cannot send to/from zero address");
        price[_tokenId] = _newPrice;
        _transferFrom(_currentOwner, _newOwner, _tokenId);
    }

    ////////////////////////////////////
    ///////// OTHER FUNCTIONS //////////
    ////////////////////////////////////

    /// @dev should only be called thrice
    function _incrementState() internal {
        assert(uint256(state) < 4);
        state = States(uint(state) + 1);
    }

    /// @dev change state to WITHDRAW to lock contract and return all funds
    /// @dev in case Oracle never resolves, or a bug is found 
    function circuitBreaker() external {
        require(msg.sender == owner() || now > (marketExpectedResolutionTime + 4 weeks), "Not owner or too early");
        questionResolvedInvalid = true;
        state = States.WITHDRAW;
    }

    /// @dev only the contract can transfer the NFTs
    function transferFrom(address from, address to, uint256 tokenId) public {
        require(false, "Only the contract can make transfers");
        from;
        to;
        tokenId;
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public {
        require(false, "Only the contract can make transfers");
        from;
        to;
        tokenId;
        _data;
    }
}

