pragma solidity ^0.5.0;

import "./aliana/GFAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./aliana/IAliana.sol";

/// @title all functions related to creating kittens
contract FakeAliana is GFAccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IAliana public aliana;

    // Info of each user that stakes LP tokens.
    mapping(address => bool) mixedFakeCard;

    event MixFake(address indexed user, uint256 id, uint256 newID);

    constructor(IAliana _alianaAddr) public {
        require(_alianaAddr.isAliana(), "FakeAliana: isAliana false");
        aliana = _alianaAddr;
    }

    function _mixFrom(address _from, uint256 _tokenId)
        internal
        whenNotPaused
        returns (uint256)
    {
        require(!mixedFakeCard[_from], "FakeAliana: insufficient balance");
        require(
            aliana.ownerOf(_tokenId) == _from,
            "FakeAliana: must be the owner"
        );
        mixedFakeCard[_from] = true;
        emit MixFake(_from, _tokenId, _tokenId);
        return _tokenId;
    }

    function mix(uint256 _tokenId) public returns (uint256) {
        return _mixFrom(msg.sender, _tokenId);
    }

    function haveFake(address _addr) public view returns (bool) {
        return !mixedFakeCard[_addr];
    }

    function receiveApproval(
        address _sender,
        uint256 _value,
        address _tokenContract,
        bytes memory _extraData
    ) public {
        require(_value >= 0, "FakeAliana: approval negative");
        uint256 action;
        assembly {
            action := mload(add(_extraData, 0x20))
        }
        require(action == 1, "FakeAliana: unknow action");
        if (action == 1) {
            // mix
            require(
                _tokenContract == address(aliana),
                "FakeAliana: approval and want mint use aliana, but used token isn't Aliana"
            );
            uint256 tokenId;
            assembly {
                tokenId := mload(add(_extraData, 0x40))
            }
            _mixFrom(_sender, tokenId);
        }
    }
}
