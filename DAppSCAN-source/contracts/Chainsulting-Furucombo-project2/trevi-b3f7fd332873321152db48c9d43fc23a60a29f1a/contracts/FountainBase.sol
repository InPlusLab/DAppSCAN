// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./libraries/ReentrancyGuard.sol";
import "./libraries/SafeERC20.sol";
import "./libraries/SafeMath.sol";
import "./interfaces/IArchangel.sol";
import "./interfaces/IAngel.sol";
import "./interfaces/IFountain.sol";
import "./interfaces/IFountainFactory.sol";
import "./utils/ErrorMsg.sol";
import "./FountainToken.sol";

/// @title Staking vault of lpTokens
abstract contract FountainBase is FountainToken, ReentrancyGuard, ErrorMsg {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    /// @notice The staking token of this Fountain
    IERC20 public immutable stakingToken;

    IFountainFactory public immutable factory;
    IArchangel public immutable archangel;

    /// @notice The information of angel that is cached in Fountain
    struct AngelInfo {
        bool isSet;
        uint256 pid;
        uint256 totalBalance;
    }

    /// @dev The angels that user joined
    mapping(address => IAngel[]) private _joinedAngels;
    /// @dev The information of angels
    mapping(IAngel => AngelInfo) private _angelInfos;

    event Join(address user, address angel);
    event Quit(address user, address angel);
    event Deposit(address indexed user, uint256 amount, address indexed to);
    event Withdraw(address indexed user, uint256 amount, address indexed to);
    event EmergencyWithdraw(
        address indexed user,
        uint256 amount,
        address indexed to
    );
    event Harvest(address indexed user);

    constructor(IERC20 token) public {
        stakingToken = token;
        IFountainFactory f = IFountainFactory(msg.sender);
        factory = f;
        archangel = IArchangel(f.archangel());
    }

    // Getters
    /// @notice Return contract name for error message.
    function getContractName() public pure override returns (string memory) {
        return "Fountain";
    }

    /// @notice Return the angels that user joined.
    /// @param user The user address.
    /// @return The angel list.
    function joinedAngel(address user) public view returns (IAngel[] memory) {
        return _joinedAngels[user];
    }

    /// @notice Return the information of the angel. The fountain needs to be
    /// added by angel.
    /// @param angel The angel to be queried.
    /// @return The pid in angel.
    /// @return The total balance deposited in angel.
    function angelInfo(IAngel angel) public view returns (uint256, uint256) {
        AngelInfo storage info = _angelInfos[angel];
        _requireMsg(info.isSet, "angelInfo", "Fountain: angel not set");
        return (info.pid, info.totalBalance);
    }

    /// Angel action
    /// @notice Angel may set their own pid that matches the staking token
    /// of the Fountain.
    /// @param pid The pid to be assigned.
    function setPoolId(uint256 pid) external {
        IAngel angel = IAngel(_msgSender());
        AngelInfo storage info = _angelInfos[angel];
        _requireMsg(info.isSet == false, "setPoolId", "Fountain: angel is set");
        _requireMsg(
            angel.lpToken(pid) == address(stakingToken),
            "setPoolId",
            "Fountain: token not matched"
        );
        info.isSet = true;
        info.pid = pid;
    }

    // User action
    /// @notice User may deposit their lp token. FTN token will be minted.
    /// Fountain will call angel's deposit to update user information, but the tokens
    /// stay in Fountain.
    /// @param amount The amount to be deposited.
    function deposit(uint256 amount) external {
        // Mint token
        _mint(_msgSender(), amount);

        // Transfer user staking token
        stakingToken.safeTransferFrom(_msgSender(), address(this), amount);

        emit Deposit(_msgSender(), amount, _msgSender());
    }

    // User action
    /// @notice User may deposit their lp token for others. FTN token will be minted.
    /// Fountain will call angel's deposit to update user information, but the tokens
    /// stay in Fountain.
    /// @param amount The amount to be deposited.
    /// @param to The address to be deposited.
    function depositTo(uint256 amount, address to) external {
        // Mint token
        _mint(to, amount);

        // Transfer user staking token
        stakingToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit Deposit(_msgSender(), amount, to);
    }

    /// @notice User may withdraw their lp token. FTN token will be burned.
    /// Fountain will call angel's withdraw to update user information, but the tokens
    /// will be transferred from Fountain.
    /// @param amount The amount to be withdrawn.
    function withdraw(uint256 amount) external {
        // Withdraw entire balance if amount == UINT256_MAX
        amount = amount == type(uint256).max ? balanceOf(_msgSender()) : amount;

        // Burn token
        _burn(_msgSender(), amount);

        // Transfer user staking token
        stakingToken.safeTransfer(_msgSender(), amount);
        emit Withdraw(_msgSender(), amount, _msgSender());
    }

    /// @notice User may withdraw their lp token. FTN token will be burned.
    /// Fountain will call angel's withdraw to update user information, but the tokens
    /// will be transferred from Fountain.
    /// @param amount The amount to be withdrawn.
    /// @param to The address to sent the withdrawn balance to.
    function withdrawTo(uint256 amount, address to) external {
        // Withdraw entire balance if amount == UINT256_MAX
        amount = amount == type(uint256).max ? balanceOf(_msgSender()) : amount;

        // Burn token
        _burn(_msgSender(), amount);

        // Transfer user staking token
        stakingToken.safeTransfer(to, amount);
        emit Withdraw(_msgSender(), amount, to);
    }

    /// @notice User may harvest from any angel.
    /// @param angel The angel to be harvest from.
    function harvest(IAngel angel) external {
        _harvestAngel(angel, _msgSender(), _msgSender());
        emit Harvest(_msgSender());
    }

    /// @notice User may harvest from all the joined angels.
    function harvestAll() external {
        // Call joined angel
        IAngel[] storage angels = _joinedAngels[_msgSender()];
        for (uint256 i = 0; i < angels.length; i++) {
            IAngel angel = angels[i];
            _harvestAngel(angel, _msgSender(), _msgSender());
        }
        emit Harvest(_msgSender());
    }

    /// @notice Emergency withdraw all tokens.
    function emergencyWithdraw() external {
        uint256 amount = balanceOf(_msgSender());

        // Burn token
        _burn(_msgSender(), type(uint256).max);

        // Transfer user staking token
        stakingToken.safeTransfer(_msgSender(), amount);
        emit EmergencyWithdraw(_msgSender(), amount, _msgSender());
    }

    /// @notice Join the given angel's program.
    /// @param angel The angel to be joined.
    function joinAngel(IAngel angel) external {
        _joinAngel(angel, _msgSender());
    }

    /// @notice Join the given angels' program.
    /// @param angels The angels to be joined.
    function joinAngels(IAngel[] calldata angels) external {
        for (uint256 i = 0; i < angels.length; i++) {
            _joinAngel(angels[i], _msgSender());
        }
    }

    /// @notice Quit the given angel's program.
    /// @param angel The angel to be quited.
    function quitAngel(IAngel angel) external {
        IAngel[] storage angels = _joinedAngels[_msgSender()];
        uint256 len = angels.length;
        if (angels[len - 1] == angel) {
            angels.pop();
        } else {
            for (uint256 i = 0; i < len - 1; i++) {
                if (angels[i] == angel) {
                    angels[i] = angels[len - 1];
                    angels.pop();
                    break;
                }
            }
        }
        _requireMsg(
            angels.length != len,
            "quitAngel",
            "Fountain: unjoined angel"
        );

        emit Quit(_msgSender(), address(angel));

        // Update user info at angel
        _withdrawAngel(_msgSender(), angel, balanceOf(_msgSender()));
    }

    /// @notice Quit all angels' program.
    function quitAllAngel() external {
        IAngel[] storage angels = _joinedAngels[_msgSender()];
        for (uint256 i = 0; i < angels.length; i++) {
            IAngel angel = angels[i];
            emit Quit(_msgSender(), address(angel));
            // Update user info at angel
            _withdrawAngel(_msgSender(), angel, balanceOf(_msgSender()));
        }
        delete _joinedAngels[_msgSender()];
    }

    /// @notice Withdraw for the sender and deposit for the receiver
    /// when token amount changes. When the amount is UINT256_MAX,
    /// trigger emergencyWithdraw instead of withdraw.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (from != address(0)) {
            IAngel[] storage angels = _joinedAngels[from];
            if (amount < type(uint256).max) {
                for (uint256 i = 0; i < angels.length; i++) {
                    IAngel angel = angels[i];
                    _withdrawAngel(from, angel, amount);
                }
            } else {
                for (uint256 i = 0; i < angels.length; i++) {
                    IAngel angel = angels[i];
                    _emergencyWithdrawAngel(from, angel);
                }
            }
        }
        if (to != address(0)) {
            IAngel[] storage angels = _joinedAngels[to];
            for (uint256 i = 0; i < angels.length; i++) {
                IAngel angel = angels[i];
                _depositAngel(to, angel, amount);
            }
        }
    }

    /// @notice The total staked amount should be updated in angelInfo when
    /// token is being deposited/withdrawn.
    // SWC-107-Reentrancy: L290-291
    function _depositAngel(
        address user,
        IAngel angel,
        uint256 amount
    ) internal nonReentrant {
        AngelInfo storage info = _angelInfos[angel];
        _requireMsg(
            info.isSet,
            "_depositAngel",
            "Fountain: not added by angel"
        );
        angel.deposit(info.pid, amount, user);
        info.totalBalance = info.totalBalance.add(amount);
    }

    // SWC-107-Reentrancy
    function _withdrawAngel(
        address user,
        IAngel angel,
        uint256 amount
    ) internal nonReentrant {
        AngelInfo storage info = _angelInfos[angel];
        _requireMsg(
            info.isSet,
            "_withdrawAngel",
            "Fountain: not added by angel"
        );
        angel.withdraw(info.pid, amount, user);
        info.totalBalance = info.totalBalance.sub(amount);
    }

    function _harvestAngel(
        IAngel angel,
        address from,
        address to
    ) internal nonReentrant {
        AngelInfo storage info = _angelInfos[angel];
        _requireMsg(
            info.isSet,
            "_harvestAngel",
            "Fountain: not added by angel"
        );
        angel.harvest(info.pid, from, to);
    }

    function _emergencyWithdrawAngel(address user, IAngel angel)
        internal
        nonReentrant
    {
        AngelInfo storage info = _angelInfos[angel];
        _requireMsg(
            info.isSet,
            "_emergencyAngel",
            "Fountain: not added by angel"
        );
        uint256 amount = balanceOf(user);
        angel.emergencyWithdraw(info.pid, user);
        info.totalBalance = info.totalBalance.sub(amount);
    }

    function _joinAngel(IAngel angel, address user) internal {
        IAngel[] storage angels = _joinedAngels[user];
        for (uint256 i = 0; i < angels.length; i++) {
            _requireMsg(angels[i] != angel, "_joinAngel", "Angel joined");
        }
        angels.push(angel);

        emit Join(user, address(angel));

        // Update user info at angel
        _depositAngel(user, angel, balanceOf(user));
    }
}
