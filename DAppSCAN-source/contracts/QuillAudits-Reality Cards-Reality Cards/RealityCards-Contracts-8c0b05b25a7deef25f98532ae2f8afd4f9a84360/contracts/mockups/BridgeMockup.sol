pragma solidity 0.5.13;

import "hardhat/console.sol";

import '../interfaces/IRCProxyXdai.sol';
import '../interfaces/IRCProxyMainnet.sol';

// this is only for ganache testing. Public chain deployments will use the existing Realitio contracts. 

contract BridgeMockup
{
    address public oracleProxyMainnetAddress;
    address public oracleProxyXdaiAddress;

    function requireToPassMessage(address _RCProxyAddress, bytes calldata _data, uint256 _gasLimit) external {
        _gasLimit;
        (bool _success, ) = _RCProxyAddress.call.value(0)(_data);
        // this is for a sepcific test where the oracleProxyMainnetAddress is
        // scrambled intentionally
        if (0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 != oracleProxyMainnetAddress)
        {
            require(_success,"Bridge failed");
        }
        
    }

    function messageSender() external view returns(address)  {
        // console.log("oracleProxyXdaiAddress is", oracleProxyXdaiAddress);
        if (msg.sender == oracleProxyMainnetAddress) {
            return oracleProxyXdaiAddress;
        } else {
            return oracleProxyMainnetAddress;
        }
    }

    function setProxyMainnetAddress(address _newAddress) external {
        oracleProxyMainnetAddress = _newAddress;
    }

    function setProxyXdaiAddress(address _newAddress) external {
        oracleProxyXdaiAddress = _newAddress;
    }
}

