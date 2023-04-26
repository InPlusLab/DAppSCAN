pragma solidity 0.5.13;

import '../../interfaces/IRealitio.sol';
import '../../interfaces/IRCProxyXdai.sol';
import '../../interfaces/IBridge.sol';
import "@openzeppelin/contracts/ownership/Ownable.sol";

// a mockup to test changing the proxy, this is as per the original but always returns winner of 69
contract RCProxyMainnetV2 is Ownable
{
    IRealitio public realitio;
    IBridge public bridge; 

    address public oracleProxyXdaiAddress;
    address public arbitrator;
    uint32 public timeout;
    
    mapping (address => bytes32) public questionIds;

    // CONSTRUCTOR

    constructor(address _bridgeMainnetAddress, address _realitioAddress) public {
        setBridgeXdaiAddress(_bridgeMainnetAddress);
        setRealitioAddress(_realitioAddress);
        setArbitrator(0xd47f72a2d1d0E91b0Ec5e5f5d02B2dc26d00A14D); //kleros
        setTimeout(86400); // 24 hours
    }

    // OWNED FUNCTIONS
    
    /// @dev not set in constructor, address not known at deployment
    function setProxyXdaiAddress(address _newAddress) onlyOwner external {
        oracleProxyXdaiAddress = _newAddress;
    }

    function setBridgeXdaiAddress(address _newAddress) onlyOwner public {
        bridge = IBridge(_newAddress);
    }

    function setRealitioAddress(address _newAddress) onlyOwner public {
        realitio = IRealitio(_newAddress);
    }

    function setArbitrator(address _newAddress) onlyOwner public {
        arbitrator = _newAddress;
    }

    function setTimeout(uint32 _newTimeout) onlyOwner public {
        timeout = _newTimeout;
    }
    
    // POSTING QUESTION TO THE ORACLE
    
    function postQuestionToOracle(address _marketAddress, string calldata _question, uint32 _oracleResolutionTime) external {
        require(msg.sender == address(bridge), "Not bridge");
        require(bridge.messageSender() == oracleProxyXdaiAddress, "Not proxy");
        // hard coded values
        uint256 _template_id = 2;
        uint256 _nonce = 0;
        // post to Oracle
        bytes32 _questionId = realitio.askQuestion(_template_id, _question, arbitrator, timeout, _oracleResolutionTime, _nonce);
        questionIds[_marketAddress] = _questionId;
    }
    
    // GETTING THE WINNER FROM THE ORACLE AND PASSING TO XDAI PROXY

    /// @dev can be called by anyone
    function getWinnerFromOracle(address _marketAddress) external returns(bool) {
        bytes32 _questionId = questionIds[_marketAddress];
        bool _isFinalized = realitio.isFinalized(_questionId);
        
        // if finalised, send result over to xDai proxy
        if (_isFinalized) {
            bytes32 _winningOutcome = bytes32(uint(69));
            bytes4 _methodSelector = IRCProxyXdai(address(0)).setWinner.selector;
            bytes memory data = abi.encodeWithSelector(_methodSelector, _marketAddress, _winningOutcome);
            bridge.requireToPassMessage(oracleProxyXdaiAddress,data,200000);
        }
        
        return _isFinalized;
    }  
    
}
