pragma solidity ^0.6.6;

import {
    ERC20PausableUpgradeSafe,
    IERC20,
    SafeMath
} from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/ERC20Pausable.sol";
import {
    SafeERC20
} from "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/SafeERC20.sol";

import {AddressArrayUtils} from "./library/AddressArrayUtils.sol";

import {ILimaSwap} from "./interfaces/ILimaSwap.sol";
import {ILimaManager} from "./interfaces/ILimaManager.sol";
import {ILimaTokenHelper} from "./interfaces/ILimaTokenHelper.sol";
import {ILimaOracleReceiver} from "./interfaces/ILimaOracleReceiver.sol";
import {ILimaOracle} from "./interfaces/ILimaOracle.sol";

/**
 * @title LimaToken
 * @author Lima Protocol
 *
 * Standard LimaToken.
 */
contract LimaToken is ERC20PausableUpgradeSafe {
    using AddressArrayUtils for address[];
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    event Create(address _from, uint256 _amount);
    event Redeem(address _from, uint256 _amount);
    event RebalanceInit(address _sender);
    event RebalanceExecute(address _oldToken, address _newToken);
    event ReadyForRebalance();

    // address public owner;
    ILimaTokenHelper public limaTokenHelper; //limaTokenStorage

    /**
     * @dev Initializes contract
     */
    function initialize(
        string memory name,
        string memory symbol,
        address _limaTokenHelper,
        uint256 _underlyingAmount,
        uint256 _limaAmount
    ) public initializer {
        limaTokenHelper = ILimaTokenHelper(_limaTokenHelper);

        __ERC20_init(name, symbol);
        __ERC20Pausable_init();

        if (_underlyingAmount > 0 && _limaAmount > 0) {
            IERC20(limaTokenHelper.currentUnderlyingToken()).safeTransferFrom(
                msg.sender,
                address(this),
                _underlyingAmount
            );
            _mint(msg.sender, _limaAmount);
        }
    }

    /* ============ Modifiers ============ */

    modifier onlyNotRebalancing() {
        _isRebalancing(false);
        _;
    }
    modifier onlyRebalancing() {
        _isRebalancing(true);
        _;
    }

    function _isRebalancing(bool active) internal view {
        // Internal function used to reduce bytecode size
        require(
            limaTokenHelper.isRebalancing() == active,
            "LM10" //"Only when rebalancing is active/inactive"
        );
    }

    modifier onlyUnderlyingToken(address _token) {
        _isOnlyUnderlyingToken(_token);
        _;
    }

    function _isOnlyUnderlyingToken(address _token) internal view {
        // Internal function used to reduce bytecode size
        require(
            limaTokenHelper.isUnderlyingTokens(_token),
            "LM1" //"Only token that are part of Underlying Tokens"
        );
    }

    modifier onlyInvestmentToken(address _investmentToken) {
        // Internal function used to reduce bytecode size
        _isOnlyInvestmentToken(_investmentToken);
        _;
    }

    function _isOnlyInvestmentToken(address _investmentToken) internal view {
        // Internal function used to reduce bytecode size
        require(
            limaTokenHelper.isInvestmentToken(_investmentToken),
            "LM7" //nly token that are approved to invest/payout.
        );
    }

    /**
     * @dev Throws if called by any account other than the limaManager.
     */
    modifier onlyLimaManagerOrOwner() {
        _isOnlyLimaManagerOrOwner();
        _;
    }

    function _isOnlyLimaManagerOrOwner() internal view {
        require(
            limaTokenHelper.limaManager() == _msgSender() ||
                limaTokenHelper.owner() == _msgSender(),
            "LM2" // "Ownable: caller is not the limaManager or owner"
        );
    }

    modifier onlyAmunUsers() {
        _isOnlyAmunUser();
        _;
    }

    function _isOnlyAmunUser() internal view {
        if (limaTokenHelper.isOnlyAmunUserActive()) {
            require(
                limaTokenHelper.isAmunUser(msg.sender),
                "LM3" //"AmunUsers: msg sender must be part of amunUsers."
            );
        }
    }

    /* ============ View ============ */

    function getUnderlyingTokenBalance() public view returns (uint256 balance) {
        return
            IERC20(limaTokenHelper.currentUnderlyingToken()).balanceOf(
                address(this)
            );
    }

    function getUnderlyingTokenBalanceOf(uint256 _amount)
        public
        view
        returns (uint256 balanceOf)
    {
        return getUnderlyingTokenBalance().mul(_amount).div(totalSupply());
    }

    /* ============ Lima Manager ============ */

    function mint(address account, uint256 amount)
        public
        onlyLimaManagerOrOwner
    {
        _mint(account, amount);
    }

    // pausable functions
    function pause() external onlyLimaManagerOrOwner {
        _pause();
    }

    function unpause() external onlyLimaManagerOrOwner {
        _unpause();
    }

    function _approveLimaSwap(address _token, uint256 _amount) internal {
        if (
            IERC20(_token).allowance(
                address(this),
                address(limaTokenHelper.limaSwap())
            ) < _amount
        ) {
            IERC20(_token).safeApprove(
                address(limaTokenHelper.limaSwap()),
                limaTokenHelper.MAX_UINT256()
            );
        }
    }

    function _swap(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _minimumReturn
    ) internal returns (uint256 returnAmount) {
        if (address(_from) != address(_to) && _amount > 0) {
            _approveLimaSwap(_from, _amount);

            returnAmount = limaTokenHelper.limaSwap().swap(
                address(this),
                _from,
                _to,
                _amount,
                _minimumReturn
            );
            return returnAmount;
        }
        return _amount;
    }

    function _unwrap(
        address _token,
        uint256 _amount,
        address _recipient
    ) internal {
        if (_amount > 0) {
            _approveLimaSwap(_token, _amount);
            limaTokenHelper.limaSwap().unwrap(_token, _amount, _recipient);
        }
    }

    /**
     * @dev Swaps token to new token  
     */
    function swap(
        address _from,
        address _to,
        uint256 _amount,
        uint256 _minimumReturn
    ) public onlyLimaManagerOrOwner returns (uint256 returnAmount) {
        return _swap(_from, _to, _amount, _minimumReturn);
    }

    /**
     * @dev Initilises rebalances proccess and calls oracle
     * Note: Can be called every 24 h by everyone and will be repayed
     */
    function initRebalance() external onlyNotRebalancing {
        uint256 startGas = gasleft();

        require(
            limaTokenHelper.lastRebalance() +
                limaTokenHelper.rebalanceInterval() <
                now,
            "LM5" //"Rebalance only every 24 hours"
        );

        limaTokenHelper.setLastRebalance(now);
        limaTokenHelper.setIsRebalancing(true);

        IERC20(limaTokenHelper.LINK()).transfer(
            address(limaTokenHelper.oracle()),
            1 * 10**17
        ); // 0.1 LINK

        bytes32 _requestId = limaTokenHelper.oracle().requestDeliveryStatus(
            address(this)
        );
        limaTokenHelper.setRequestId(_requestId);
        emit RebalanceInit(msg.sender);
        _mint(msg.sender, limaTokenHelper.getPayback(startGas - gasleft()));
    }

    /* ============ Main Functions ============ */
    // response structure: uint8-uint24-uint8-uint24-uint8-uint24-address

    /**
     * @dev Data Provided by oracle needed for rebalance 
     * @param _requestId The requestId from oracle.
     * @param _data The packed data newToken address, minimumReturn for rebalance, 
     *              minimumReturn on governance token swap, and amount to sell for LINK.
     *              response structure: uint8-uint24-uint8-uint24-uint8-uint24-address
     */
    function receiveOracleData(bytes32 _requestId, bytes32 _data)
        public
        virtual
        onlyRebalancing
    {
        limaTokenHelper.isReceiveOracleData(_requestId, msg.sender);

        limaTokenHelper.setOracleData(_data);

        limaTokenHelper.setIsOracleDataReturned(true);

        emit ReadyForRebalance();
    }

    /**
     * @dev Rebalances LimaToken 
     * Will do swaps of potential governancetoken, underlying token to token that provides higher return
     * Will swap to LINK when needed
     * Uses data stored by receiveOracleData in getRebalancingData()
     */
    function rebalance() external onlyRebalancing {
        uint256 startGas = gasleft();
        require(limaTokenHelper.isOracleDataReturned(), "LM8"); //only rebalance data is returned

        (
            address _bestToken,
            uint256 _minimumReturn,
            uint256 _minimumReturnGov,
            uint256 _amountToSellForLink,
            uint256 _minimumReturnLink,
            address _govToken
        ) = limaTokenHelper.getRebalancingData();

        //send fee to fee wallet
        _unwrap(
            limaTokenHelper.currentUnderlyingToken(),
            limaTokenHelper.getPerformanceFee(),
            limaTokenHelper.feeWallet()
        );

        //swap link
        if (_amountToSellForLink != 0) {
            _swap(
                limaTokenHelper.currentUnderlyingToken(),
                limaTokenHelper.LINK(),
                _amountToSellForLink,
                _minimumReturnLink
            );
        }

        //swap gov
        _swap(
            _govToken,
            _bestToken,
            IERC20(_govToken).balanceOf(address(this)),
            _minimumReturnGov
        );

        //swap underlying
        _swap(
            limaTokenHelper.currentUnderlyingToken(),
            _bestToken,
            getUnderlyingTokenBalance(),
            _minimumReturn
        );
        emit RebalanceExecute(
            limaTokenHelper.currentUnderlyingToken(),
            _bestToken
        );

        limaTokenHelper.setCurrentUnderlyingToken(_bestToken);
        limaTokenHelper.setLastUnderlyingBalancePer1000(
            getUnderlyingTokenBalanceOf(1000 ether)
        );

        limaTokenHelper.setIsRebalancing(false);
        limaTokenHelper.setIsOracleDataReturned(false);

        _mint(msg.sender, limaTokenHelper.getPayback(startGas - gasleft()));
    }

    /**
     * @dev Redeem the value of LimaToken in _payoutToken.
     * @param _payoutToken The address of token to payout with.
     * @param _amount The amount to redeem.
     * @param _recipient The user address to redeem from/to.
     * @param _minimumReturn The minimum amount to return or else revert.
     */
    function forceRedeem(
        address _payoutToken,
        uint256 _amount,
        address _recipient,
        uint256 _minimumReturn
    ) external onlyLimaManagerOrOwner returns (bool) {
        return
            _redeem(
                _recipient,
                _payoutToken,
                _amount,
                _recipient,
                _minimumReturn
            );
    }

    /* ============ User ============ */

    /**
     * @dev Creates new token for holder by converting _investmentToken value to LimaToken
     * Note: User need to approve _amount on _investmentToken to this contract
     * @param _investmentToken The address of token to invest with.
     * @param _amount The amount of investment token to create lima token from.
     * @param _recipient The address to transfer the lima token to.
     * @param _minimumReturn The minimum amount to return or else revert.
     */
    function create(
        address _investmentToken,
        uint256 _amount,
        address _recipient,
        uint256 _minimumReturn
    )
        external
        onlyInvestmentToken(_investmentToken)
        onlyAmunUsers
        onlyNotRebalancing
        returns (bool)
    {
        uint256 balance = getUnderlyingTokenBalance();

        IERC20(_investmentToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        //get fee
        uint256 fee = limaTokenHelper.getFee(
            _amount,
            limaTokenHelper.mintFee()
        );
        if (fee > 0) {
            IERC20(_investmentToken).safeTransfer(
                limaTokenHelper.feeWallet(),
                fee
            );
            _amount = _amount - fee;
        }
        _amount = _swap(
            _investmentToken,
            limaTokenHelper.currentUnderlyingToken(),
            _amount,
            _minimumReturn
        );
        _amount = totalSupply().mul(_amount).div(balance);
        require(_amount > 0, "zero");

        _mint(_recipient, _amount);

        emit Create(msg.sender, _amount);
        return true;
    }

    function _redeem(
        address _investor,
        address _payoutToken,
        uint256 _amount,
        address _recipient,
        uint256 _minimumReturn
    )
        internal
        onlyInvestmentToken(_payoutToken)
        onlyNotRebalancing
        returns (bool)
    {
        uint256 underlyingAmount = getUnderlyingTokenBalanceOf(_amount);
        _burn(_investor, _amount);

        uint256 fee = limaTokenHelper.getFee(
            underlyingAmount,
            limaTokenHelper.burnFee()
        );
        if (fee > 0) {
            _unwrap(
                limaTokenHelper.currentUnderlyingToken(),
                fee,
                limaTokenHelper.feeWallet()
            );
            underlyingAmount = underlyingAmount - fee;
        }
        emit Redeem(msg.sender, _amount);

        _amount = _swap(
            limaTokenHelper.currentUnderlyingToken(),
            _payoutToken,
            underlyingAmount,
            _minimumReturn
        );
        require(_amount > 0, "zero");
        IERC20(_payoutToken).safeTransfer(_recipient, _amount);

        return true;
    }

    /**
     * @dev Redeem the value of LimaToken in _payoutToken.
     * @param _payoutToken The address of token to payout with.
     * @param _amount The amount of lima token to redeem.
     * @param _recipient The address to transfer the payout token to.
     * @param _minimumReturn The minimum amount to return or else revert.
     */
    function redeem(
        address _payoutToken,
        uint256 _amount,
        address _recipient,
        uint256 _minimumReturn
    ) external returns (bool) {
        return
            _redeem(
                msg.sender,
                _payoutToken,
                _amount,
                _recipient,
                _minimumReturn
            );
    }
}
