pragma solidity ^0.6.0;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/Initializable.sol";

import "./Interfaces.sol";
import { ReentrancyGuardPausable } from "../ReentrancyGuardPausable.sol";
import "../UpgradeableOwnable.sol";


interface IVaultConfig {
  /// @dev Return the bps rate for reserve pool.
  function getReservePoolBps() external view returns (uint256);
}

interface IAlpacaVault is IERC20 {

  function config() external view returns (address);
  function vaultDebtVal() external view returns (uint256);
  function lastAccrueTime() external view returns (uint256);
  function reservePool() external view returns (uint256);

  /// @dev Return the total ERC20 entitled to the token holders. Be careful of unaccrued interests.
  function totalToken() external view returns (uint256);

  /// @dev Add more ERC20 to the bank. Hope to get some good returns.
  function deposit(uint256 amountToken) external payable;

  /// @dev Withdraw ERC20 from the bank by burning the share tokens.
  function withdraw(uint256 share) external;

  /// @dev Request funds from user through Vault
  function requestFunds(address targetedToken, uint amount) external;

  function pendingInterest(uint256 value) external view returns (uint256);

}

interface IFairLaunch {
  function poolLength() external view returns (uint256);

  function addPool(
    uint256 _allocPoint,
    address _stakeToken,
    bool _withUpdate
  ) external;

  function setPool(
    uint256 _pid,
    uint256 _allocPoint,
    bool _withUpdate
  ) external;

  function pendingAlpaca(uint256 _pid, address _user) external view returns (uint256);

  function updatePool(uint256 _pid) external;

  function deposit(address _for, uint256 _pid, uint256 _amount) external;

  function withdraw(address _for, uint256 _pid, uint256 _amount) external;

  function withdrawAll(address _for, uint256 _pid) external;

  function harvest(uint256 _pid) external;

  function userInfo(uint256 _pid, address user) external view returns (uint256, uint256, uint256, address);
}

contract StratAlpaca is UpgradeableOwnable, ReentrancyGuardPausable, ISimpleStrategy, Initializable {

    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IAlpacaVault;

    bool public wantIsWBNB = false;
    IERC20 public wantToken = IERC20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    address public uniRouterAddress = 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F;

    address public wbnbAddress =
        0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    IFairLaunch public fairLaunch = IFairLaunch(0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F);
    IERC20 public alpacaToken = IERC20(0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F);
    IAlpacaVault public alpacaVault = IAlpacaVault(0x7C9e73d4C71dae564d41F78d56439bB4ba87592f);

    uint256 public lastHarvestBlock = 0;

    address[] public alpacaToWantPath;

    uint256 public poolId = 3;

    address public vault;

    mapping (address => bool) public keepers;

    event KeepersSet(address[] keepers, bool[] states);

    constructor() public {}

    /*
     * Parameters on BSC:
     * poolId: 3
     * fairLaunchAddress: 0xA625AB01B08ce023B2a342Dbb12a16f2C8489A8F
     * alpacaToken: 0x8F0528cE5eF7B51152A59745bEfDD91D97091d2F
     * alpacaVault: 0x7C9e73d4C71dae564d41F78d56439bB4ba87592f
     * wantAddress: 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56
     * bnbAddress: 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c
     * uniRouterAddress: 0x05fF2B0DB69458A0750badebc4f9e13aDd608C7F
     */
    function initialize(
        uint256 _poolId,
        address _fairLaunchAddress,
        address _alpacaToken,
        address _alpacaVault,
        address _wantAddress,
        address _wbnbAddress,
        address _uniRouterAddress,
        address _vault
    )
        external
        initializer
        onlyOwner
    {
        poolId = _poolId;
        fairLaunch = IFairLaunch(_fairLaunchAddress);
        alpacaToken = IERC20(_alpacaToken);
        alpacaVault = IAlpacaVault(_alpacaVault);

        wantToken = IERC20(_wantAddress);
        wbnbAddress = _wbnbAddress;

        if (_wantAddress == wbnbAddress) {
            wantIsWBNB = true;
            alpacaToWantPath = [_alpacaToken, wbnbAddress];
        } else {
            alpacaToWantPath = [_alpacaToken, wbnbAddress, _wantAddress];
        }

        uniRouterAddress = _uniRouterAddress;

        wantToken.safeApprove(_alpacaVault, uint256(-1));
        alpacaVault.safeApprove(_fairLaunchAddress, uint256(-1));
        alpacaToken.safeApprove(uniRouterAddress, uint256(-1));
        vault = _vault;
    }

    modifier onlyVault() {
        require (msg.sender == vault, "Must from vault");
        _;
    }

    modifier onlyVaultOrKeeper() {
        require (msg.sender == vault || keepers[msg.sender], "Must from vault/keeper");
        _;
    }

    function alpacaVaultTotalToken() public view returns (uint256) {
        uint256 reservePool = alpacaVault.reservePool();
        uint256 vaultDebtVal = alpacaVault.vaultDebtVal();
        if (now > alpacaVault.lastAccrueTime()) {
            uint256 interest = alpacaVault.pendingInterest(0);
            uint256 toReserve = interest.mul(IVaultConfig(alpacaVault.config()).getReservePoolBps()).div(10000);
            reservePool = reservePool.add(toReserve);
            vaultDebtVal = vaultDebtVal.add(interest);
        }
        return wantToken.balanceOf(address(alpacaVault)).add(vaultDebtVal).sub(reservePool);
    }
    
    function _ibDeposited() internal view returns (uint256) {
        (uint256 ibBal,,,) = fairLaunch.userInfo(poolId, address(this));
        return ibBal;
    }

    function totalBalance() external override view returns (uint256) {
        uint256 ibBal = _ibDeposited();
        return alpacaVaultTotalToken().mul(ibBal).div(alpacaVault.totalSupply());
    }

    function wantAmtToIbAmount(uint256 _wantAmt) public view returns (uint256) {
        return _wantAmt.mul(alpacaVault.totalSupply()).div(alpacaVaultTotalToken());
    }

// SWC-114-Transaction Order Dependence: L191
    function deposit(uint256 _wantAmt)
        external
        override
        onlyVault
        nonReentrantAndUnpaused
    {
        IERC20(wantToken).safeTransferFrom(
            address(msg.sender),
            address(this),
            _wantAmt
        );

        alpacaVault.deposit(_wantAmt);
        fairLaunch.deposit(address(this), poolId, alpacaVault.balanceOf(address(this)));
    }

    function withdraw(uint256 _wantAmt)
        external
        override
        onlyVault
        nonReentrantAndUnpaused
    {
        uint256 ibAmt = wantAmtToIbAmount(_wantAmt);
        fairLaunch.withdraw(address(this), poolId, ibAmt);
        alpacaVault.withdraw(alpacaVault.balanceOf(address(this)));

        uint256 actualWantAmount = wantToken.balanceOf(address(this));
        wantToken.safeTransfer(
            address(msg.sender),
            actualWantAmount
        );
    }

    function _harvest(uint256 priceMin) internal {
        if (lastHarvestBlock == block.number) {
            return;
        }

        // Do not harvest if no token is deposited (otherwise, fairLaunch will fail)
        if (_ibDeposited() == 0) {
            return;
        }

        // Collect alpacaToken
        fairLaunch.harvest(poolId);

        uint256 earnedAlpacaBalance = alpacaToken.balanceOf(address(this));
        if (earnedAlpacaBalance == 0) {
            return;
        }

        if (alpacaToken != wantToken) {
            IPancakeRouter02(uniRouterAddress).swapExactTokensForTokens(
                earnedAlpacaBalance,
                earnedAlpacaBalance.mul(priceMin).div(1e18),
                alpacaToWantPath,
                address(this),
                now.add(600)
            );
        }

        alpacaVault.deposit(IERC20(wantToken).balanceOf(address(this)));
        fairLaunch.deposit(address(this), poolId, alpacaVault.balanceOf(address(this)));

        lastHarvestBlock = block.number;
    }

    function harvest(uint256 minPrice) external override onlyVaultOrKeeper nonReentrantAndUnpaused {
        _harvest(minPrice);
    }

    /**
     * @dev Pauses the strat.
     */
    function pause(uint256 _flags) external onlyOwner {
        _pause();

        alpacaToken.safeApprove(uniRouterAddress, 0);
        wantToken.safeApprove(uniRouterAddress, 0);
    }

    /**
     * @dev Unpauses the strat.
     */
    function unpause(uint256 _flags) external onlyOwner {
        _unpause();

        alpacaToken.safeApprove(uniRouterAddress, uint256(-1));
        wantToken.safeApprove(uniRouterAddress, uint256(-1));
    }

    function setVault(address _vault) external onlyOwner {
        vault = _vault;
    }

    function setKeepers(address[] calldata _keepers, bool[] calldata _states) external onlyOwner {
        uint256 n = _keepers.length;
        for(uint256 i = 0; i < n; i++) {
            keepers[_keepers[i]] = _states[i];
        }
        emit KeepersSet(_keepers, _states);
    }

    receive() external payable {}
}