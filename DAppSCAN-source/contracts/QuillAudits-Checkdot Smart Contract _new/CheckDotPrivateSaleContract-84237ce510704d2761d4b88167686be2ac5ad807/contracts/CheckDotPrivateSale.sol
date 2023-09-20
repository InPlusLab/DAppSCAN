// SPDX-License-Identifier: UNLICENSED
// SWC-103-Floating Pragma: L3
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CheckDotPrivateSale {
    using SafeMath for uint256;

    address private                         _owner;
    address private                         _cdtTokenAddress;
    mapping(address => uint256) private     _wallets_investment;

    uint256 public                          _ethSolded;
    uint256 public                          _cdtSolded;
    uint256 public                          _cdtPereth;
    uint256 public                          _maxethPerWallet;
    bool public                             _paused = false;
    bool public                             _claim = false;

    event NewAmountPresale(uint256 srcAmount, uint256 cdtPereth, uint256 totalCdt);
    event StateChange();

    /**
     * @dev Constructing the contract basic informations, containing the CDT token addr, the ratio price eth:cdt
     * and the max authorized eth amount per wallet
     */
    constructor(address checkDotTokenAddr, uint256 cdtPereth, uint256 maxethPerWallet) {
        require(msg.sender != address(0), "Deploy from the zero address");
        _owner = msg.sender;
        _ethSolded = 0;
        _cdtPereth = cdtPereth;
        _cdtTokenAddress = checkDotTokenAddr;
        _maxethPerWallet = maxethPerWallet;
    }

    /**
     * @dev Check that the transaction sender is the CDT owner
     */
    modifier onlyOwner() {
        require(msg.sender == _owner, "Only the owner can do this action");
        _;
    }

    /**
     * @dev Receive eth payment for the presale raise
     */
    receive() external payable {
        require(_paused == false, "Presale is paused");
        uint256 totalInvested = _wallets_investment[address(msg.sender)].add(msg.value);
        require(totalInvested <= _maxethPerWallet, "You depassed the limit of max eth per wallet for the presale.");
        _transfertCDT(msg.value);
    }

    /**
     * @dev Set the presale in pause state (no more deposits are accepted once it's turned back)
     */
    function setPaused(bool value) public payable onlyOwner {
        _paused = value;
        emit StateChange();
    }

    /**
     * @dev Set the presale claim mode 
     */
    function setClaim(bool value) public payable onlyOwner {
        _claim = value;
        emit StateChange();
    }

    /**
     * @dev Claim the CDT once the presale is done
     */
    function claimCdt() public
    {
        IERC20 cdtToken = IERC20(_cdtTokenAddress);

        require(_claim == true, "You cant claim your CDT yet");
        uint256 srcAmount =  _wallets_investment[address(msg.sender)];
        require(srcAmount > 0, "You dont have any CDT to claim");
        
        uint256 cdtAmount = (srcAmount.mul(_cdtPereth)).div(10 ** 18);
         require(
            cdtToken.balanceOf(address(this)) >= cdtAmount,
            "No CDT amount required on the contract"
        );
        _wallets_investment[address(msg.sender)] = 0;
        cdtToken.transfer(msg.sender, cdtAmount);
    }

    /**
     * @dev Return the max authorized eth amount per wallet
     */
    function getMaxEthPerWallet() public view returns(uint256) {
        return _maxethPerWallet;
    }

    /**
     * @dev Return the ratio price eth:cdt
     */
    function getCdtPerEth() public view returns(uint256) {
        return _cdtPereth;
    }

    /**
     * @dev Return the amount raised from the Presale (as ETH)
     */
    function getTotalRaisedEth() public view returns(uint256) {
        return _ethSolded;
    }

    /**
     * @dev Return the amount raised from the Presale (as CDT)
     */
    function getTotalRaisedCdt() public view returns(uint256) {
        return _cdtSolded;
    }

    /**
     * @dev Return the total amount invested from a specific address
     */
    function getAddressInvestment(address addr) public view returns(uint256) {
        return  _wallets_investment[addr];
    }

    /**
     * @dev Transfer the specific CDT amount to the payer address
     */
    function _transfertCDT(uint256 _srcAmount) private {
        IERC20 cdtToken = IERC20(_cdtTokenAddress);
        uint256 cdtAmount = (_srcAmount.mul(_cdtPereth)).div(10 ** 18);

        emit NewAmountPresale(_srcAmount, _cdtPereth, cdtAmount);

        require(
            cdtToken.balanceOf(address(this)) >= cdtAmount.add(_cdtSolded),
            "No CDT amount required on the contract"
        );

        _ethSolded += _srcAmount;
        _cdtSolded += cdtAmount;
        _wallets_investment[msg.sender] += _srcAmount;
    }

    /**
     * @dev Authorize the contract owner to withdraw the raised funds from the presale
     */
    function withdraw() public payable onlyOwner {
        payable(msg.sender).transfer(address(this).balance);
    }

    /**
     * @dev Authorize the contract owner to withdraw the remaining CDT from the presale
     */
    function withdrawRemainingCDT() public payable onlyOwner {
        IERC20 cdtToken = IERC20(_cdtTokenAddress);

        cdtToken.transfer(msg.sender, cdtToken.balanceOf(address(this)));
    }
}