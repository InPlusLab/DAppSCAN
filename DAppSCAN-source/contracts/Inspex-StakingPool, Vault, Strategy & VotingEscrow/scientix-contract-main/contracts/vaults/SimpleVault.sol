pragma solidity ^0.6.0;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Math} from "@openzeppelin/contracts/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/Initializable.sol";

import "./Interfaces.sol";
import { ReentrancyGuardPausable } from "../ReentrancyGuardPausable.sol";
import "../UpgradeableOwnable.sol";

import "../interfaces/IyVaultV2.sol";



/**
 * @dev Implementation of a vault to deposit funds for yield optimizing.
 * This is the contract that receives funds and that users interface with.
 * It supports deposits of burning tokens and strategies with entrance fee.
 * The yield optimizing strategy itself is implemented in a separate 'Strategy.sol' contract.
 */
contract SimpleVault is ERC20, UpgradeableOwnable, ReentrancyGuardPausable, IyVaultV2Simple, Initializable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    struct StratCandidate {
        address implementation;
        uint256 proposedTime;
    }

    // The last proposed strategy to switch to.
    StratCandidate public stratCandidate;
    // The strategy currently in use by the vault.
    ISimpleStrategy public strategy;
    // The token the vault accepts and looks to maximize.
    IERC20 private assetToken;
    // The minimum time it has to pass before a strat candidate can be approved.
    uint256 public approvalDelay;

    event NewStratCandidate(address implementation);
    event UpgradeStrat(address implementation);

    bool public needWhitelist = false;
    mapping(address => bool) public isWhitelisted;

    string private vaultName;
    string private vaultSymbol;

    constructor () public ERC20("", "") {}

    /**
     * @dev Sets the value of {token} to the token that the vault will
     * hold as underlying value. It initializes the vault's own 'moo' token.
     * This token is minted when someone does a deposit. It is burned in order
     * to withdraw the corresponding portion of the underlying assets.
     * @param _token the token to maximize.
     * @param _strategy the address of the strategy.
     * @param _name the name of the vault token.
     * @param _symbol the symbol of the vault token.
     * @param _approvalDelay the delay before a new strat can be approved.
     */
    function initialize(
        address _token,
        address _strategy,
        string memory _name,
        string memory _symbol,
        uint256 _approvalDelay
    )
        external
        initializer
        onlyOwner
    {
        assetToken = IERC20(_token);
        strategy = ISimpleStrategy(_strategy);
        approvalDelay = _approvalDelay;
        assetToken.safeApprove(_strategy, uint256(-1));
        vaultName = _name;
        vaultSymbol = _symbol;
    }

    function name() public view override returns (string memory) {
        return vaultName;
    }

    function symbol() public view override returns (string memory) {
        return vaultSymbol;
    }

    function decimals() public view override(IyVaultV2Simple, ERC20) returns (uint8) {
        return 18;
    }

    function token() public view override returns (address) {
        return address(assetToken);
    }

    /**
     * @dev It calculates the total underlying value of {token} held by the system.
     */
    function totalBalance() public view returns (uint) {
        return strategy.totalBalance();
    }

    /**
     * @dev Function for calculating the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() public view returns (uint256) {
        return totalBalance().mul(1e18).div(totalSupply());
    }

    function pricePerShare() public view override returns (uint256) {
        return getPricePerFullShare();
    }

    /**
     * @dev A helper function to call deposit() with all the sender's funds.
     */
    function depositAll() external {
        deposit(assetToken.balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     * The function will update minPricePerFullShare using the actual amount deposited, assuming
     * the underlying strategy may charge entrance fee.
     */
    function deposit(uint256 _amount) public override nonReentrantAndUnpaused returns (uint256) {
        require(!needWhitelist || isWhitelisted[msg.sender], "not whitelisted");

        assetToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 balanceOld = totalBalance();
        strategy.deposit(_amount);
        uint256 balanceNew = totalBalance();

        uint256 actualAmount = balanceNew.sub(balanceOld);
        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = actualAmount;
        } else {
            shares = (actualAmount.mul(totalSupply())).div(balanceOld);
        }
        _mint(msg.sender, shares);
        return shares;
    }

    /**
     * @dev A helper function to call withdraw() with all the sender's funds.
     */
    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of share
     * tokens are burned in the process.
     */
    function _withdraw(uint256 _shares, address _recipient) internal returns (uint256) {
        require(!needWhitelist || isWhitelisted[msg.sender], "not whitelisted");

        uint256 amount = (totalBalance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        strategy.withdraw(amount);
        uint256 actualAmount = assetToken.balanceOf(address(this));
        assetToken.safeTransfer(_recipient, actualAmount);
        return actualAmount;
    }

    /**
     * @dev Function to exit the system with minPricePerFullShare constraint.
     * This prevents an attacker repeatedly asking msg.sender to deposit/withdraw and drain the fund.
     */
    function withdraw(uint256 _shares) public override nonReentrantAndUnpaused returns (uint256) {
        return _withdraw(_shares, msg.sender);
    }

    function withdraw(uint256 _shares, address _recipient) external override nonReentrantAndUnpaused returns (uint256) {
        return _withdraw(_shares, _recipient);
    }

    /**
     * @dev Sets the candidate for the new strat to use with this vault.
     * @param _implementation The address of the candidate strategy.
     */
    function proposeStrat(address _implementation) external onlyOwner {
        stratCandidate = StratCandidate({
            implementation: _implementation,
            proposedTime: block.timestamp
         });

        emit NewStratCandidate(_implementation);
    }

    function whitelist(address _account, bool _whitelisted) external onlyOwner {
        isWhitelisted[_account] = _whitelisted;
    }

    function setNeedWhitelist(bool _needWhitelist) external onlyOwner {
        needWhitelist = _needWhitelist;
    }

    /**
     * @dev It switches the active strat for the strat candidate. After upgrading, the
     * candidate implementation is set to the 0x00 address, and proposedTime to a time
     * happening in +100 years for safety.
     */
    function upgradeStrat() external onlyOwner {
        require(stratCandidate.implementation != address(0), "There is no candidate");
        require(stratCandidate.proposedTime.add(approvalDelay) < block.timestamp, "Delay has not passed");

        emit UpgradeStrat(stratCandidate.implementation);

        strategy.withdraw(totalBalance());
        assetToken.safeApprove(address(strategy), 0);
        strategy = ISimpleStrategy(stratCandidate.implementation);
        stratCandidate.implementation = address(0);
        stratCandidate.proposedTime = 5000000000;

        assetToken.safeApprove(address(strategy), uint256(-1));
        strategy.deposit(assetToken.balanceOf(address(this)));
    }
}