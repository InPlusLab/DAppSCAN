pragma solidity 0.5.13;

import '../../interfaces/IRCProxyMainnet.sol';
import '../../interfaces/IBridge.sol';
import '../../interfaces/ITreasury.sol';
import '../../interfaces/IRCMarket.sol';
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// a mockup to test changing the proxy, this is as per the original but always doubles the returned winner
contract RCProxyXdaiV2 is Ownable
{
    using SafeMath for uint256;
    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    ///// CONTRACT VARIABLES /////
    IBridge public bridge;

    ///// GOVERNANCE VARIABLES /////
    address public proxyMainnetAddress;
    address public factoryAddress;
    address public treasuryAddress;
    
    ///// ORACLE VARIABLES /////
    mapping (address => question) public questions;
    struct question { 
        string question;              
        uint32 oracleResolutionTime;
        bool set; }

    ///// NFT UPGRADE VARIABLES /////
    mapping (address => bool) public isMarket;
    mapping(uint256 => nft) public upgradedNfts;
    struct nft { 
        string tokenURI;
        address owner;
        bool set; }

    ///// DAI->XDAI BRIDGE VARIABLES /////
    uint256 public validatorCount;
    mapping (address => bool) public isValidator;
    mapping (uint256 => Deposit) public deposits;
    mapping (uint256 => mapping(address => bool)) public hasConfirmedDeposit;
    /// @dev so only the float can be withdrawn and no more
    uint256 public floatSize;
    struct Deposit {
        address user;
        uint256 amount;
        uint256 confirmations;
        bool confirmed;
        bool executed; }

    ////////////////////////////////////
    //////// EVENTS ////////////////////
    ////////////////////////////////////

    event LogFloatIncreased(address indexed funder, uint256 amount);
    event LogFloatWithdrawn(address indexed recipient, uint256 amount);
    event LogDepositConfirmed(uint256 indexed nonce);
    event LogDepositExecuted(uint256 indexed nonce);

    ////////////////////////////////////
    ////////// CONSTRUCTOR /////////////
    ////////////////////////////////////

    constructor(address _bridgeXdaiAddress, address _factoryAddress, address _treasuryAddress) public {
        setBridgeXdaiAddress(_bridgeXdaiAddress);
        setFactoryAddress(_factoryAddress);
        setTreasuryAddress(_treasuryAddress);
    }

    ////////////////////////////////////
    //////////// ADD MARKETS ///////////
    ////////////////////////////////////

    /// @dev so only RC NFTs can be upgraded
    function addMarket(address _newMarket) external returns(bool) {
        require(msg.sender == factoryAddress, "Not factory");
        isMarket[_newMarket] = true;
        return true;
    }
    
    ////////////////////////////////////
    /////// GOVERNANCE - SETUP /////////
    ////////////////////////////////////

    /// @dev address of mainnet oracle proxy, called by the mainnet side of the arbitrary message bridge
    /// @dev not set in constructor, address not known at deployment
    function setProxyMainnetAddress(address _newAddress) onlyOwner external {
        proxyMainnetAddress = _newAddress;
    }

    /// @dev address of arbitrary message bridge, xdai side
    function setBridgeXdaiAddress(address _newAddress) onlyOwner public {
        bridge = IBridge(_newAddress);
    }

    /// @dev address of RC factory contract, so only factory can post questions
    function setFactoryAddress(address _newAddress) onlyOwner public {
        factoryAddress = _newAddress;
    }

    /// @dev address of RC treasury contract
    function setTreasuryAddress(address _newAddress) onlyOwner public {
        treasuryAddress = _newAddress;
    }

    ////////////////////////////////////
    /////// GOVERNANCE - ORACLE ////////
    ////////////////////////////////////

    /// @dev admin override of the Oracle, if not yet settled, for amicable resolution, or bridge fails
    function setAmicableResolution(address _marketAddress, uint256 _winningOutcome) onlyOwner public {
        // call the market
        IRCMarket market = IRCMarket(_marketAddress);
        market.setWinner(_winningOutcome);
    }

    ////////////////////////////////////
    ///// GOVERNANCE - DAI BRIDGE //////
    ////////////////////////////////////

    /// @dev impossible to withdraw user funds, only added float 
    function withdrawFloat(uint256 _amount) onlyOwner external {
        // will throw an error if goes negative because safeMath
        floatSize = floatSize.sub(_amount);
        address _thisAddressNotPayable = owner();
        address payable _recipient = address(uint160(_thisAddressNotPayable));
        (bool _success, ) = _recipient.call.value(_amount)("");
        require(_success, "Transfer failed");
        emit LogFloatWithdrawn(msg.sender, _amount);
    }

    /// @dev modify validators for dai deposits
    function setValidator(address _validatorAddress, bool _add) onlyOwner external {
        if(_add) {
            if(!isValidator[_validatorAddress]) {
                isValidator[_validatorAddress] = true;
                validatorCount = validatorCount.add(1);
            }
        } else {
            if(isValidator[_validatorAddress]) {
                isValidator[_validatorAddress] = false;
                validatorCount = validatorCount.sub(1);
            }
        }
    }
    
    ////////////////////////////////////
    ///// CORE FUNCTIONS - ORACLE //////
    ////////////////////////////////////

    /// @dev called by factory upon market creation (thus impossible to be called twice), posts question to Oracle via arbitrary message bridge
    function saveQuestion(address _marketAddress, string calldata _question, uint32 _oracleResolutionTime) external {
        require(msg.sender == factoryAddress, "Not factory");
        questions[_marketAddress].question = _question;
        questions[_marketAddress].oracleResolutionTime = _oracleResolutionTime;
        questions[_marketAddress].set = true;
        postQuestionToBridge(_marketAddress);
    }

    /// @dev question is posted in a different function so it can be called again if bridge fails
    /// @dev postQuestionToOracle on mainnet proxy will block multiple successful posts 
    function postQuestionToBridge(address _marketAddress) public {
        require(questions[_marketAddress].set, "No question");
        bytes4 _methodSelector = IRCProxyMainnet(address(0)).postQuestionToOracle.selector;
        bytes memory data = abi.encodeWithSelector(_methodSelector, _marketAddress, questions[_marketAddress].question, questions[_marketAddress].oracleResolutionTime);
        bridge.requireToPassMessage(proxyMainnetAddress,data,200000);
    }
    
    /// @dev called by mainnet oracle proxy via the arbitrary message bridge, sets the winning outcome
    /// @dev market.setWinner() will revert if done twice, because wrong state
    function setWinner(address _marketAddress, uint256 _winningOutcome) external {
        require(msg.sender == address(bridge), "Not bridge");
        require(bridge.messageSender() == proxyMainnetAddress, "Not proxy");
        // call the market
        IRCMarket market = IRCMarket(_marketAddress);
        market.setWinner(_winningOutcome.mul(2));
    }
    
    ////////////////////////////////////
    /// CORE FUNCTIONS - NFT UPGRADES //
    ////////////////////////////////////

    function saveCardToUpgrade(uint256 _tokenId, string calldata _tokenUri, address _owner) external {
        require(isMarket[msg.sender], "Not market");
        // sassert because hould be impossible to call this twice because upgraded card returned to market
        assert(!upgradedNfts[_tokenId].set);
        upgradedNfts[_tokenId].tokenURI = _tokenUri;
        upgradedNfts[_tokenId].owner = _owner;
        upgradedNfts[_tokenId].set = true;
        postCardToUpgrade(_tokenId);
    }

     /// @dev card is upgraded in a different function so it can be called again if bridge fails
     /// @dev no harm if called again after successful posting because can't mint nft with same tokenId twice 
    function postCardToUpgrade(uint256 _tokenId) public {
        require(upgradedNfts[_tokenId].set, "Nft not set");
        bytes4 _methodSelector = IRCProxyMainnet(address(0)).upgradeCard.selector;
        bytes memory data = abi.encodeWithSelector(_methodSelector, _tokenId, upgradedNfts[_tokenId].tokenURI, upgradedNfts[_tokenId].owner);
        bridge.requireToPassMessage(proxyMainnetAddress,data,200000);
    }

    ////////////////////////////////////
    //// CORE FUNCTIONS - DAI BRIDGE ///
    ////////////////////////////////////

    /// @dev add a float, so no need to wait for arrival of xdai from ARB
    function() external payable {
        floatSize = floatSize.add(msg.value);
        emit LogFloatIncreased(msg.sender, msg.value);
    }

    function confirmDaiDeposit(address _user, uint256 _amount, uint256 _nonce) external {
        require(isValidator[msg.sender], "Not a validator");

        // If the deposit is new, create it
        if(deposits[_nonce].user == address(0)) {
            Deposit memory newDeposit = Deposit(_user, _amount, 0, false, false);
            deposits[_nonce] = newDeposit;
        }

        // Only valid if these match
        require(deposits[_nonce].user == _user, "Addresses don't match");
        require(deposits[_nonce].amount == _amount, "Amounts don't match");
        
        // Add 1 confirmation, if this hasn't been done already
        if(!hasConfirmedDeposit[_nonce][msg.sender]) {
            hasConfirmedDeposit[_nonce][msg.sender] = true;
            deposits[_nonce].confirmations = deposits[_nonce].confirmations.add(1);
        }

        // Confirm if enough confirms and pass over for execution
        if(!deposits[_nonce].confirmed && deposits[_nonce].confirmations >= (validatorCount.div(2)).add(1)) {
            deposits[_nonce].confirmed = true;
            executeDaiDeposit(_nonce);
            emit LogDepositConfirmed(_nonce);
        }
    }

    function executeDaiDeposit(uint256 _nonce) public {
        require(deposits[_nonce].confirmed, "Not confirmed");
        require(!deposits[_nonce].executed, "Already executed");
        uint256 _amount = deposits[_nonce].amount;
        address _user = deposits[_nonce].user;
        if (address(this).balance >= _amount) {
            ITreasury treasury = ITreasury(treasuryAddress);
            assert(treasury.deposit.value(_amount)(_user));
            deposits[_nonce].executed = true;
            emit LogDepositExecuted(_nonce);
        }
    }
}