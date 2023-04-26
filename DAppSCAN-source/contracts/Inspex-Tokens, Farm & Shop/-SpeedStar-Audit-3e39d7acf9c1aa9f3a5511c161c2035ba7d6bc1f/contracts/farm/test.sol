//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IStaking {
    function depositHorse(uint256 _tokenId) external;

    function withdrawHorseInStable(
        uint256 _stableTokenId,
        uint256 _horseTokenId
    ) external;

    function depositHorseInStable(uint256 _stableTokenId, uint256 _horseTokenId)
        external;

    function withdrawHorse(uint256 _tokenId) external;

    function depositStable(uint256 _tokenId) external;

    function withdrawStable(uint256 _stableTokenId) external;
}

contract Test is Ownable, IERC721Receiver {
    using SafeMath for uint256;
    using SafeERC20 for ERC20;

    uint256 public targetAmount;

    IStaking public staking;
    ERC20 public speed;
    ERC721 public horse;
    ERC721 public facility;
    uint256 public horseId;
    uint256 public stableId;

    constructor(
        address _staking,
        ERC20 _speed,
        ERC721 _horse,
        ERC721 _facility
    ) {
        staking = IStaking(_staking);
        speed = _speed;
        horse = _horse;
        facility = _facility;
    }

    function setTargetAmount(uint256 _targetAmount) external onlyOwner {
        targetAmount = _targetAmount;
    }

    function setStakeContract(address _stake) external onlyOwner {
        staking = IStaking(_stake);
    }

    function withdrawStable(uint256 _stableTokenId) external onlyOwner {
        staking.withdrawStable(_stableTokenId);
    }

    function depositStable(uint256 _tokenId) external onlyOwner {
        facility.setApprovalForAll(address(staking), true);
        staking.depositStable(_tokenId);
        stableId = _tokenId;
    }

    function depositHorseInStable(uint256 _stableTokenId, uint256 _horseTokenId)
        external
        onlyOwner
    {
        horse.setApprovalForAll(address(staking), true);
        horseId = _horseTokenId;
        staking.depositHorseInStable(_stableTokenId, _horseTokenId);
    }

    function withdrawHorseInStable(
        uint256 _stableTokenId,
        uint256 _horseTokenId
    ) public {
        console.log("Test withdrawHorseInStable", address(this));
        staking.withdrawHorseInStable(_stableTokenId, _horseTokenId);
    }

    function claimSpeed() external onlyOwner {
        speed.transfer(owner(), speed.balanceOf(address(this)));
    }

    function claimHorse(uint256 _tokenId) external onlyOwner {
        horse.safeTransferFrom(address(this), owner(), _tokenId);
    }

    function claimStable(uint256 _tokenId) external onlyOwner {
        facility.safeTransferFrom(address(this), owner(), _tokenId);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        console.log(speed.balanceOf(address(this)));
        if (speed.balanceOf(address(this)) < targetAmount) {
            horse.safeTransferFrom(address(this), address(staking), horseId);
            withdrawHorseInStable(stableId, horseId);
        }

        return this.onERC721Received.selector;
    }
}
