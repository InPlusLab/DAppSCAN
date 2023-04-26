// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IKOAccessControlsLookup} from "../access/IKOAccessControlsLookup.sol";
import {IKODAV3} from "../core/IKODAV3.sol";

/// @notice Core logic and state shared between both marketplaces
abstract contract BaseMarketplace is ReentrancyGuard, Pausable {

    event AdminUpdateModulo(uint256 _modulo);
    event AdminUpdateMinBidAmount(uint256 _minBidAmount);
    event AdminUpdateAccessControls(IKOAccessControlsLookup indexed _oldAddress, IKOAccessControlsLookup indexed _newAddress);
    event AdminUpdatePlatformPrimarySaleCommission(uint256 _platformPrimarySaleCommission);
    event AdminUpdateBidLockupPeriod(uint256 _bidLockupPeriod);
    event AdminUpdatePlatformAccount(address indexed _oldAddress, address indexed _newAddress);
    event AdminRecoverERC20(IERC20 indexed _token, address indexed _recipient, uint256 _amount);
    event AdminRecoverETH(address payable indexed _recipient, uint256 _amount);

    event BidderRefunded(uint256 indexed _id, address _bidder, uint256 _bid, address _newBidder, uint256 _newOffer);
    event BidderRefundedFailed(uint256 indexed _id, address _bidder, uint256 _bid, address _newBidder, uint256 _newOffer);

    // Only a whitelisted smart contract in the access controls contract
    modifier onlyContract() {
        _onlyContract();
        _;
    }

    function _onlyContract() private view {
        require(accessControls.hasContractRole(_msgSender()), "Caller not contract");
    }

    // Only admin defined in the access controls contract
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    function _onlyAdmin() private view {
        require(accessControls.hasAdminRole(_msgSender()), "Caller not admin");
    }

    /// @notice Address of the access control contract
    IKOAccessControlsLookup public accessControls;

    /// @notice KODA V3 token
    IKODAV3 public koda;

    /// @notice platform funds collector
    address public platformAccount;

    /// @notice precision 100.00000%
    uint256 public modulo = 100_00000;

    /// @notice Minimum bid / minimum list amount
    uint256 public minBidAmount = 0.01 ether;

    /// @notice Bid lockup period
    uint256 public bidLockupPeriod = 6 hours;

    constructor(IKOAccessControlsLookup _accessControls, IKODAV3 _koda, address _platformAccount) {
        koda = _koda;
        accessControls = _accessControls;
        platformAccount = _platformAccount;
    }

    function recoverERC20(IERC20 _token, address _recipient, uint256 _amount) public onlyAdmin {
        _token.transfer(_recipient, _amount);
        emit AdminRecoverERC20(_token, _recipient, _amount);
    }

    function recoverStuckETH(address payable _recipient, uint256 _amount) public onlyAdmin {
        (bool success,) = _recipient.call{value : _amount}("");
        require(success, "Unable to send recipient ETH");
        emit AdminRecoverETH(_recipient, _amount);
    }

    function updateAccessControls(IKOAccessControlsLookup _accessControls) public onlyAdmin {
        require(_accessControls.hasAdminRole(_msgSender()), "Sender must have admin role in new contract");
        emit AdminUpdateAccessControls(accessControls, _accessControls);
        accessControls = _accessControls;
    }

    function updateModulo(uint256 _modulo) public onlyAdmin {
        require(_modulo > 0, "Modulo point cannot be zero");
        modulo = _modulo;
        emit AdminUpdateModulo(_modulo);
    }

    function updateMinBidAmount(uint256 _minBidAmount) public onlyAdmin {
        minBidAmount = _minBidAmount;
        emit AdminUpdateMinBidAmount(_minBidAmount);
    }

    function updateBidLockupPeriod(uint256 _bidLockupPeriod) public onlyAdmin {
        bidLockupPeriod = _bidLockupPeriod;
        emit AdminUpdateBidLockupPeriod(_bidLockupPeriod);
    }

    function updatePlatformAccount(address _newPlatformAccount) public onlyAdmin {
        emit AdminUpdatePlatformAccount(platformAccount, _newPlatformAccount);
        platformAccount = _newPlatformAccount;
    }

    function pause() public onlyAdmin {
        super._pause();
    }

    function unpause() public onlyAdmin {
        super._unpause();
    }

    function _getLockupTime() internal view returns (uint256 lockupUntil) {
        lockupUntil = block.timestamp + bidLockupPeriod;
    }

    function _refundBidder(uint256 _id, address _receiver, uint256 _paymentAmount, address _newBidder, uint256 _newOffer) internal {
        (bool success,) = _receiver.call{value : _paymentAmount}("");
        if (!success) {
            emit BidderRefundedFailed(_id, _receiver, _paymentAmount, _newBidder, _newOffer);
        } else {
            emit BidderRefunded(_id, _receiver, _paymentAmount, _newBidder, _newOffer);
        }
    }

    /// @dev This allows the processing of a marketplace sale to be delegated higher up the inheritance hierarchy
    function _processSale(
        uint256 _id,
        uint256 _paymentAmount,
        address _buyer,
        address _seller
    ) internal virtual returns (uint256);

    /// @dev This allows an auction mechanic to ask a marketplace if a new listing is permitted i.e. this could be false if the edition or token is already listed under a different mechanic
    function _isListingPermitted(uint256 _id) internal virtual returns (bool);
}
