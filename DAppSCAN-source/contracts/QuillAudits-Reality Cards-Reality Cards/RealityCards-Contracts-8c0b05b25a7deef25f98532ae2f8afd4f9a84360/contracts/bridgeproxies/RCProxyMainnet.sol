pragma solidity 0.5.13;

import "hardhat/console.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import '../interfaces/IRealitio.sol';
import '../interfaces/IRCProxyXdai.sol';
import '../interfaces/IBridge.sol';
import '../interfaces/IAlternateReceiverBridge.sol';
import '../interfaces/IERC20Dai.sol';
import '../interfaces/IERC721.sol';

/// @title Reality Cards Proxy- Mainnet side
/// @author Andrew Stanger & Marvin Kruse
/// @notice If you have found a bug, please contact andrew@realitycards.io- no hack pls!!
contract RCProxyMainnet is Ownable
{
    ////////////////////////////////////
    //////// VARIABLES /////////////////
    ////////////////////////////////////

    /// @dev contract variables
    IRealitio public realitio;
    IBridge public bridge;
    IAlternateReceiverBridge public alternateReceiverBridge;
    IERC20Dai public dai;
    IERC721 public nfthub;

    /// @dev governance variables
    address public proxyXdaiAddress;
    address public nftHubAddress;
    address public arbitrator;
    uint32 public timeout;
    
    /// @dev market resolution variables
    mapping (address => bytes32) public questionIds;

    /// @dev dai deposits
    uint256 internal depositNonce;
    bool depositsEnabled = true;

    ////////////////////////////////////
    ////////// CONSTRUCTOR /////////////
    ////////////////////////////////////

    constructor(address _bridgeMainnetAddress, address _realitioAddress, address _nftHubAddress, address _alternateReceiverAddress, address _daiAddress) public {
        setBridgeMainnetAddress(_bridgeMainnetAddress);
        setRealitioAddress(_realitioAddress);
        setNftHubAddress(_nftHubAddress);
        setAlternateReceiverAddress(_alternateReceiverAddress);
        setDaiAddress(_daiAddress); 
        setArbitrator(0xd47f72a2d1d0E91b0Ec5e5f5d02B2dc26d00A14D); // kleros
        setTimeout(86400); // 24 hours
    }

    ////////////////////////////////////
    //////////// EVENTS ////////////////
    ////////////////////////////////////

    event LogQuestionPostedToOracle(address indexed marketAddress, bytes32 indexed questionId);
    event DaiDeposited(address indexed user, uint256 amount, uint256 nonce);

    ////////////////////////////////////
    /////// GOVERNANCE - SETUP /////////
    ////////////////////////////////////
    
    /// @dev address of xdai oracle proxy, called by the xdai side of the arbitrary message bridge
    /// @dev not set in constructor, address not known at deployment
    function setProxyXdaiAddress(address _newAddress) onlyOwner external {
        proxyXdaiAddress = _newAddress;
    }

    /// @dev address of arbitrary message bridge, mainnet side
    function setBridgeMainnetAddress(address _newAddress) onlyOwner public {
        bridge = IBridge(_newAddress);
    }

    /// @dev address of alternate receiver bridge, mainnet side
    function setNftHubAddress(address _newAddress) onlyOwner public {
        nfthub = IERC721(_newAddress);
    }

    /// @dev address of alternate receiver bridge, mainnet side
    function setAlternateReceiverAddress(address _newAddress) onlyOwner public {
        alternateReceiverBridge = IAlternateReceiverBridge(_newAddress);
    }

    /// @dev address of dai contract, must also approve the ARB
    function setDaiAddress(address _newAddress) onlyOwner public {
        dai = IERC20Dai(_newAddress);
        dai.approve(address(alternateReceiverBridge), 2**256 - 1);
    }

    ////////////////////////////////////
    /////// GOVERNANCE - ORACLE ////////
    ////////////////////////////////////

    /// @dev address reality.eth contracts
    function setRealitioAddress(address _newAddress) onlyOwner public {
        realitio = IRealitio(_newAddress);
    }

    /// @dev address of arbitrator, in case of continued disputes on reality.eth
    function setArbitrator(address _newAddress) onlyOwner public {
        arbitrator = _newAddress;
    }

    /// @dev how long reality.eth waits for disputes before finalising
    function setTimeout(uint32 _newTimeout) onlyOwner public {
        timeout = _newTimeout;
    }

    /// @dev admin can post question if not already posted
    /// @dev for situations where bridge failed
    function postQuestionToOracleAdmin(address _marketAddress, string calldata _question, uint32 _oracleResolutionTime) onlyOwner external {
        require(questionIds[_marketAddress] == 0, "Already posted");
        bytes32 _questionId = realitio.askQuestion(2, _question, arbitrator, timeout, _oracleResolutionTime, 0);
        questionIds[_marketAddress] = _questionId;
        emit LogQuestionPostedToOracle(_marketAddress, _questionId);
    }

    ////////////////////////////////////
    //// GOVERNANCE - NFT UPGRADES /////
    ////////////////////////////////////

    /// @dev admin can create NFTs
    /// @dev for situations where bridge failed
    function upgradeCardAdmin(uint256 _newTokenId, string calldata _tokenUri, address _owner) onlyOwner external {
        nfthub.mintNft(_newTokenId, _tokenUri, _owner);
    }  

    ////////////////////////////////////
    ///// GOVERNANCE - DAI BRIDGE //////
    ////////////////////////////////////

    function enableOrDisableDeposits() onlyOwner external {
        depositsEnabled = depositsEnabled ? false : true;
    }
    
    ////////////////////////////////////
    ///// CORE FUNCTIONS - ORACLE //////
    ////////////////////////////////////
    
    ///@notice called by xdai proxy via bridge, posts question to Oracle
    function postQuestionToOracle(address _marketAddress, string calldata _question, uint32 _oracleResolutionTime) external {
        require(msg.sender == address(bridge), "Not bridge");
        require(bridge.messageSender() == proxyXdaiAddress, "Not proxy");
        require(questionIds[_marketAddress] == 0, "Already posted");
        bytes32 _questionId = realitio.askQuestion(2, _question, arbitrator, timeout, _oracleResolutionTime, 0);
        questionIds[_marketAddress] = _questionId;
        emit LogQuestionPostedToOracle(_marketAddress, _questionId);
    }

    /// @notice has the oracle finalised 
    function isFinalized(address _marketAddress) public view returns(bool) {
        bytes32 _questionId = questionIds[_marketAddress];
        bool _isFinalized = realitio.isFinalized(_questionId);
        return _isFinalized;
    }

    /// @dev can be called by anyone, reads winner from Oracle and sends to xdai proxy via bridge
    /// @dev can be called more than once in case bridge fails, xdai proxy will reject a second successful call
    function getWinnerFromOracle(address _marketAddress) external {
        require(isFinalized(_marketAddress), "Oracle not finalised");
        bytes32 _questionId = questionIds[_marketAddress];
        bytes32 _winningOutcome = realitio.resultFor(_questionId);
        bytes4 _methodSelector = IRCProxyXdai(address(0)).setWinner.selector;
        bytes memory data = abi.encodeWithSelector(_methodSelector, _marketAddress, _winningOutcome);
        bridge.requireToPassMessage(proxyXdaiAddress,data,400000);
    }

    ////////////////////////////////////
    /// CORE FUNCTIONS - NFT UPGRADES //
    ////////////////////////////////////

    /// @notice mints NFT with metadata as sent by proxy
    function upgradeCard(uint256 _newTokenId, string calldata _tokenUri, address _owner) external {
        require(msg.sender == address(bridge), "Not bridge");
        require(bridge.messageSender() == proxyXdaiAddress, "Not proxy");
        nfthub.mintNft(_newTokenId, _tokenUri, _owner);
    }  

    ////////////////////////////////////
    //// CORE FUNCTIONS - DAI BRIDGE ///
    ////////////////////////////////////

    /// @dev user deposit assuming prior approval
    function depositDai(uint256 _amount) external {
        _depositDai(msg.sender, _amount); 
    }

    /// @dev user deposit without prior approval
    function permitAndDepositDai(address holder, address spender, uint256 nonce, uint256 expiry, bool allowed, uint8 v, bytes32 r, bytes32 s, uint256 _amount) external {
        require(allowed, "only possible if allowance is set");
        dai.permit(holder, spender, nonce, expiry, allowed, v, r, s);
        _depositDai(holder, _amount);
    }

    /// @dev send Dai to xDai proxy and emit event for offchain validator 
    function _depositDai(address _sender, uint256 _amount) internal {
        require(depositsEnabled, "Deposits disabled");
        require(dai.transferFrom(_sender, address(this), _amount), "Token transfer failed");
        alternateReceiverBridge.relayTokens(address(this), proxyXdaiAddress, _amount);
        emit DaiDeposited(_sender, _amount, depositNonce++);
    }
}
