pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./token/IMintableToken.sol";
import "./aliana/GFAccessControl.sol";

// LPMint is the master of Mintlone tokens. He can make Mint and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once Mint is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract LPMint is GFAccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of Mints
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * accMintPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. Update accMintPerShare and lastRewardBlock
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Address of LP token contract.
    IERC20 lpToken;
    // Accumulated Mints per share, times 1e12. See below.
    uint256 public accMintPerShare;
    // Last block reward block height
    uint256 public lastRewardBlock;
    // Reward per block
    uint256 public rewardPerBlock;

    // The Mintlone TOKEN
    IMintableToken public mintToken;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) public userInfo;

    event RewardAdded(uint256 amount, bool isBlockReward);
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(IMintableToken _mintToken, IERC20 _lpToken) public {
        mintToken = _mintToken;
        lastRewardBlock = block.number;
        lpToken = _lpToken;
        // times 1e10. See below.
        uint256 defaultPerDayIn5SecBlock = 100;
        setRewardPerBlock(
            defaultPerDayIn5SecBlock.mul(1e18).div((24 * 60 * 60) / 5)
        );
    }

    function setRewardPerBlock(uint256 _rewardPerBlock) public onlyCEO {
        updateBlockReward();
        rewardPerBlock = _rewardPerBlock;
    }

    // View function to see pending reward on frontend.
    function pendingReward(address _user) external view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        if (rewardPerBlock == 0) {
            return 0;
        }
        uint256 lpSupply = lpToken.balanceOf(address(this));
        if (block.number <= lastRewardBlock || lpSupply == 0) {
            return 0;
        }
        return
            user
                .amount
                .mul(
                    accMintPerShare.add(
                        block
                            .number
                            .sub(lastRewardBlock)
                            .mul(rewardPerBlock)
                            .mul(1e12)
                            .div(lpSupply)
                    )
                )
                .div(1e12)
                .sub(user.rewardDebt);
    }

    // Add reward variables to be up-to-date.
    function addReward(uint256 _amount) public onlyWhitelisted {
        uint256 lpSupply = lpToken.balanceOf(address(this));
        if (lpSupply == 0 || _amount == 0) {
            return;
        }
        emit RewardAdded(_amount, false);
        accMintPerShare = accMintPerShare.add(_amount.mul(1e12).div(lpSupply));
    }

    // Update reward variables to be up-to-date.
    function updateBlockReward() public {
        if (block.number <= lastRewardBlock || rewardPerBlock == 0) {
            return;
        }
        uint256 lpSupply = lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 reward = block.number.sub(lastRewardBlock).mul(rewardPerBlock);
        lastRewardBlock = block.number;
        accMintPerShare = accMintPerShare.add(reward.mul(1e12).div(lpSupply));
    }

    // Deposit LP tokens to LPMint for Mint allocation.
    function deposit(uint256 _amount) public {
        _depositFrom(msg.sender, _amount);
    }

    // Deposit LP tokens to LPMint for Mint allocation.
    function _depositFrom(address _from, uint256 _amount)
        internal
        whenNotPaused
    {
        updateBlockReward();
        UserInfo storage user = userInfo[_from];
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accMintPerShare).div(1e12).sub(
                user.rewardDebt
            );
            if (pending > 0) {
                safeMintTransfer(_from, pending);
            }
        }
        if (_amount > 0) {
            lpToken.safeTransferFrom(address(_from), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(accMintPerShare).div(1e12);
        emit Deposit(_from, _amount);
    }

    // Withdraw LP tokens from LPMint.
    function withdraw(uint256 _amount) public whenNotPaused {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updateBlockReward();
        uint256 pending = user.amount.mul(accMintPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeMintTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(accMintPerShare).div(1e12);
        emit Withdraw(msg.sender, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, amount);
    }

    // Safe Mint transfer function, just in case if rounding error causes pool to not have enough Mints.
    function safeMintTransfer(address _to, uint256 _amount) internal {
        uint256 MintBalance = mintToken.balanceOf(address(this));
        if (_amount > MintBalance) {
            require(
                mintToken.transfer(_to, MintBalance),
                "failed to transfer Mint token"
            );
        } else {
            require(
                mintToken.transfer(_to, _amount),
                "failed to transfer Mint token"
            );
        }
    }

    event ReceiveApproval(
        address _sender,
        uint256 _value,
        address _tokenContract,
        bytes _extraData,
        uint256 action
    );

    function receiveApproval(
        address _sender,
        uint256 _value,
        address _tokenContract,
        bytes memory _extraData
    ) public {
        require(_value > 0, "approval zero");
        uint256 action;
        assembly {
            action := mload(add(_extraData, 0x20))
        }
        emit ReceiveApproval(
            _sender,
            _value,
            _tokenContract,
            _extraData,
            action
        );
        require(action == 3, "unknow action");
        if (action == 3) {
            // buy
            require(
                _tokenContract == address(lpToken),
                "approval and want deposit, but used token isn't GFT"
            );
            uint256 amount;
            assembly {
                amount := mload(add(_extraData, 0x40))
            }
            _depositFrom(_sender, amount);
        }
    }
}
