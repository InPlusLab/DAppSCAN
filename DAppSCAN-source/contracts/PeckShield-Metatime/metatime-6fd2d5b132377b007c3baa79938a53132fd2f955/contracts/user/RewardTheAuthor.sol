// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "../governance/InitializableOwner.sol";
import "../interfaces/IERC20Metadata.sol";
import "../base/BasicMetaTransaction.sol";
import "../interfaces/IWETH.sol";

contract RewardTheAuthor is InitializableOwner, BasicMetaTransaction {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;

    struct UserView {
        address[] tokens; // The token corresponding to the following value
        uint256[] pendingAmounts; // Amount of reward to be claimed
        uint256[] claimedAmounts; // Amount of rewards claimed
    }

    struct TokenView {
        address token;
        string name;
        string symbol;
        uint decimals;
    }

    event Reward(
        uint256 indexed id,
        address indexed from,
        address indexed target,
        address token,
        uint256 postType,
        uint64 postId,
        uint256 amount,
        uint timestamp
    );
    event Claim(address indexed user, address token, uint256 amount);

    IWETH public _weth;

    mapping(address => mapping(address => uint256)) private _userRewards; // user:token:amount
    mapping(address => mapping(address => uint256)) private _userClaimedRewards; // user:token:amount

    EnumerableSet.AddressSet private _supportTokens;
    uint256 _rewardId;

    constructor() public {}

    function initialize(IWETH weth, address[] memory supportTokens) public {
        super._initialize();
        
        _weth = weth;

        for (uint256 i = 0; i < supportTokens.length; ++i) {
            _supportTokens.add(supportTokens[i]);
        }
    }

    function addSupportToken(address token) public onlyOwner {
        require(token != address(0), "address is zero");
        require(!_supportTokens.contains(token), "already added");

        _supportTokens.add(token);
    }

    function delSupportToken(address token) public onlyOwner {
        require(_supportTokens.contains(token), "not added");

        _supportTokens.remove(token);
    }

    function isSupportToken(address token) public view returns (bool) {
        return _supportTokens.contains(token);
    }

    function getSupportTokens() public view returns (address[] memory ls) {
        uint256 len = _supportTokens.length();
        if (len == 0) {
            return ls;
        }

        ls = new address[](len);
        for (uint256 i = 0; i < len; ++i) {
            ls[i] = _supportTokens.at(i);
        }
        return ls;
    }

    function getSupportTokenViews() public view returns (TokenView[] memory ls) {
        uint256 len = _supportTokens.length();
        if (len == 0) {
            return ls;
        }

        ls = new TokenView[](len);
        for (uint256 i = 0; i < len; ++i) {
            address token = _supportTokens.at(i);
            ls[i] = TokenView({
                token: token,
                name: IERC20Metadata(token).name(),
                symbol: IERC20Metadata(token).symbol(),
                decimals: IERC20Metadata(token).decimals()
            });
        }
        return ls;
    }

    /**
     * @dev Reward the designated author
     * @param target the author
     * @param token the token to be rewarded
     * @param postType the post type
     * @param postId the post id
     * @param amount Amount to be rewarded
     */
    function reward(
        address target,
        IERC20 token,
        uint256 postType,
        uint64 postId,
        uint256 amount
    ) public payable {
        require(_supportTokens.contains(address(token)), "Unsupported token");

        if (msg.value > 0) {
            require(address(token) == address(_weth), "bad params");

            _weth.deposit{value: msg.value}();
            amount = msg.value;
        } else {
            uint256 oldBal = token.balanceOf(address(this));
            token.safeTransferFrom(msgSender(), address(this), amount);
            amount = token.balanceOf(address(this)).sub(oldBal);
        }

        require(amount > 0, "bad amount");

        uint256 pending = _userRewards[msgSender()][address(token)];
        _userRewards[msgSender()][address(token)] = pending.add(amount);

        _rewardId++;

        emit Reward(
            _rewardId,
            msgSender(),
            target,
            address(token),
            postType,
            postId,
            amount,
            block.timestamp
        );
    }

    function claim(address token) public {
        uint256 pending = _userRewards[msgSender()][token];
        if (pending == 0) return;

        _userRewards[msgSender()][token] = 0;
        _userClaimedRewards[msgSender()][address(token)] = _userClaimedRewards[msgSender()][address(token)].add(pending);

        IERC20(token).safeTransfer(msgSender(), pending);

        emit Claim(msgSender(), token, pending);
    }

    function claimAll() public {
        address[] memory supportTokens = getSupportTokens();

        for (uint256 i = 0; i < supportTokens.length; ++i) {
            claim(supportTokens[i]);
        }
    }

    function getUserView(address user) public view returns (UserView memory) {
        address[] memory supportTokens = getSupportTokens();
        uint256[] memory pendingAmounts = new uint256[](supportTokens.length);
        uint256[] memory claimedAmounts = new uint256[](supportTokens.length);

        for (uint256 i = 0; i < supportTokens.length; ++i) {
            pendingAmounts[i] = _userRewards[user][supportTokens[i]];
            claimedAmounts[i] = _userClaimedRewards[user][supportTokens[i]];
        }

        return
            UserView({
                tokens: supportTokens,
                pendingAmounts: pendingAmounts,
                claimedAmounts: claimedAmounts
            });
    }
}
