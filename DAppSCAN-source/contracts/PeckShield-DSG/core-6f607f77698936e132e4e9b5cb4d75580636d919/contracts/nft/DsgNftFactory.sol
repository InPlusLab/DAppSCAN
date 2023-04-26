// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";

interface IDsgNftOwner {
    function initialize(
        string memory name_, 
        string memory symbol_, 
        address feeToken, 
        address feeWallet_, 
        bool _canUpgrade, 
        string memory baseURI_
    ) external;
    
    function transferOwnership(address newOwner) external;
}

contract DsgNftFactory is Ownable {
    
    address public logicImplement;

    event DsgNftCreated(address indexed nft, address indexed logicImplement);

    event SetLogicImplement(address indexed user, address oldLogicImplement, address newLogicImplement);
    
    constructor(address _logicImplement) public {
        logicImplement = _logicImplement;
    }
    
    function createDsgNft(
        string memory name_, 
        string memory symbol_, 
        address feeToken, 
        address feeWallet_, 
        bool _canUpgrade,
        string memory baseURI,
        address owner,
        address proxyAdmin
    ) external onlyOwner returns (address) {
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(logicImplement, proxyAdmin, '');
        IDsgNftOwner nft = IDsgNftOwner(address(proxy));
        nft.initialize(name_, symbol_, feeToken, feeWallet_, _canUpgrade, baseURI);
        nft.transferOwnership(owner);
        emit DsgNftCreated(address(nft), logicImplement);
        return address(nft);
    }

    function setLogicImplement(address _logicImplement) external onlyOwner {
        require(logicImplement != _logicImplement, 'Not need update');
        emit SetLogicImplement(msg.sender, logicImplement, _logicImplement);
        logicImplement = _logicImplement;
    }
    
}
