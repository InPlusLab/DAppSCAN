pragma solidity ^0.5.0;

import "./aliana/GFAccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./aliana/IAliana.sol";

/// @title all functions related to creating kittens
contract AlianaMinting is GFAccessControl {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The gae TOKEN
    IERC20 public gftToken;
    IAliana public aliana;

    struct itmap {
        mapping(uint256 => IndexValue) data;
        KeyFlag[] keys;
        uint256 size;
    }
    struct IndexValue {
        uint256 keyIndex;
        uint256 value;
    }
    struct KeyFlag {
        uint256 key;
        bool deleted;
    }

    function insert(
        itmap storage self,
        uint256 key,
        uint256 value
    ) internal returns (bool replaced) {
        uint256 keyIndex = self.data[key].keyIndex;
        self.data[key].value = value;
        if (keyIndex > 0) return true;
        else {
            keyIndex = self.keys.length++;
            self.data[key].keyIndex = keyIndex + 1;
            self.keys[keyIndex].key = key;
            self.size++;
            return false;
        }
    }

    function remove(itmap storage self, uint256 key)
        internal
        returns (bool success)
    {
        uint256 keyIndex = self.data[key].keyIndex;
        if (keyIndex == 0) return false;
        delete self.data[key];
        self.keys[keyIndex - 1].deleted = true;
        self.size--;
        return true;
    }

    function contains(itmap storage self, uint256 key)
        internal
        view
        returns (bool)
    {
        return self.data[key].keyIndex > 0;
    }

    function iterate_start(itmap storage self)
        internal
        view
        returns (uint256 keyIndex)
    {
        return iterate_next(self, uint256(-1));
    }

    function iterate_valid(itmap storage self, uint256 keyIndex)
        internal
        view
        returns (bool)
    {
        return keyIndex < self.keys.length;
    }

    function iterate_next(itmap storage self, uint256 keyIndex)
        internal
        view
        returns (uint256 r_keyIndex)
    {
        keyIndex++;
        while (keyIndex < self.keys.length && self.keys[keyIndex].deleted)
            keyIndex++;
        return keyIndex;
    }

    function iterate_get(itmap storage self, uint256 keyIndex)
        internal
        view
        returns (uint256 key, uint256 value)
    {
        key = self.keys[keyIndex].key;
        value = self.data[key].value;
    }

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        itmap amountToken;
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 balance;
        //
        // We do some fancy math here. Basically, any point in time, the amount of GFTs
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * accGFTPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. Update accGFTPerShare and lastRewardBlock
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Accumulated GFTs per share, times 1e12. See below.
    uint256 public accGFTPerShare;
    // Last block reward block height
    uint256 public lastRewardBlock;
    // Reward per block
    uint256 public rewardPerBlock;
    // This Mine total labor force
    uint256 public labor;
    // Reward to distribute
    uint256 public rewardToDistribute;
    uint256 public maxMintingNumPerAddress = 9;

    // Info of each user that stakes LP tokens.
    mapping(address => UserInfo) userInfo;

    event RewardAdded(uint256 amount, bool isBlockReward);
    event Deposit(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 pending
    );
    event Withdraw(
        address indexed user,
        uint256 indexed tokenId,
        uint256 amount,
        uint256 pending
    );
    event WithdrawPending(address indexed user, uint256 pending);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(IERC20 _gftToken, IAliana _alianaAddr) public {
        require(_alianaAddr.isAliana(), "AlianaMinting: isAliana false");
        gftToken = _gftToken;
        aliana = _alianaAddr;
        lastRewardBlock = block.number;
        // times 1e10. See below.
        uint256 defaultPerDayIn5SecBlock = 2000;
        setRewardPerBlock(
            defaultPerDayIn5SecBlock.mul(1e18).div((24 * 60 * 60) / 5)
        );
    }

    function setMaxMintingNumPerAddress(uint256 _maxMintingNumPerAddress)
        public
        onlyCEO
    {
        maxMintingNumPerAddress = _maxMintingNumPerAddress;
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
        uint256 acps = accGFTPerShare;
        if (rewardPerBlock > 0) {
            uint256 lpSupply = labor;
            if (block.number > lastRewardBlock && lpSupply > 0) {
                acps = acps.add(rewardPending().mul(1e12).div(lpSupply));
            }
        }
        return user.amount.mul(acps).div(1e12).sub(user.rewardDebt);
    }

    function rewardPending() internal view returns (uint256) {
        uint256 reward = block.number.sub(lastRewardBlock).mul(rewardPerBlock);
        uint256 gaeBalance = gftToken.balanceOf(address(this)).sub(
            rewardToDistribute
        );
        if (gaeBalance < reward) {
            return gaeBalance;
        }
        return reward;
    }

    // Update reward variables to be up-to-date.
    function updateBlockReward() public {
        if (block.number <= lastRewardBlock || rewardPerBlock == 0) {
            return;
        }
        uint256 lpSupply = labor;
        uint256 reward = rewardPending();
        if (lpSupply == 0 || reward == 0) {
            lastRewardBlock = block.number;
            return;
        }
        rewardToDistribute = rewardToDistribute.add(reward);
        emit RewardAdded(reward, true);
        lastRewardBlock = block.number;
        accGFTPerShare = accGFTPerShare.add(reward.mul(1e12).div(lpSupply));
    }

    function _depositFrom(address _from, uint256 _tokenId)
        internal
        whenNotPaused
    {
        require(
            aliana.ownerOf(_tokenId) == _from,
            "AlianaMinting: must be the owner"
        );
        UserInfo storage user = userInfo[_from];
        if (maxMintingNumPerAddress > 0) {
            require(
                user.amountToken.size < maxMintingNumPerAddress,
                "AlianaMinting: too much mining at the same time"
            );
        }
        (, , , , uint256 _amount) = aliana.getAliana(_tokenId);
        require(_amount > 0, "AlianaMinting: gene _amount must > 0");

        updateBlockReward();
        uint256 takePending;
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accGFTPerShare).div(1e12).sub(
                user.rewardDebt
            );
            if (pending > 0) {
                safeGFTTransfer(_from, pending);
            }
            takePending = pending;
        }

        aliana.transferFrom(address(_from), address(this), _tokenId);
        // SWC-104-Unchecked Call Return Value: L254
        insert(user.amountToken, _tokenId, _amount);
        user.balance = user.balance.add(1);

        user.amount = user.amount.add(_amount);
        labor = labor.add(_amount);

        user.rewardDebt = user.amount.mul(accGFTPerShare).div(1e12);
        emit Deposit(_from, _tokenId, _amount, takePending);
    }

    // Deposit LP tokens to Mine for GFT allocation.
    function deposit(uint256 _tokenId) public whenNotPaused {
        _depositFrom(msg.sender, _tokenId);
    }

    // Deposit LP tokens to Mine for GFT allocation.
    function deposits(uint256[] memory _tokenIds) public whenNotPaused {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            deposit(_tokenIds[i]);
        }
    }

    // Withdraw LP tokens from Mine.
    function withdrawPending() public {
        UserInfo storage user = userInfo[msg.sender];
        updateBlockReward();
        uint256 pending = user.amount.mul(accGFTPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeGFTTransfer(msg.sender, pending);
        }
        user.rewardDebt = user.amount.mul(accGFTPerShare).div(1e12);
        emit WithdrawPending(msg.sender, pending);
    }

    // Withdraw LP tokens from Mine.
    function withdraw(uint256 _tokenId) public {
        return _withdrawFrom(msg.sender, _tokenId);
    }

    function _withdrawFrom(address _from, uint256 _tokenId) internal {
        UserInfo storage user = userInfo[_from];
        uint256 _amount = user.amountToken.data[_tokenId].value;

        require(_amount > 0, "AlianaMinting: withdraw: not good 1");
        require(user.amount >= _amount, "AlianaMinting: withdraw: not good 2");

        updateBlockReward();
        uint256 pending = user.amount.mul(accGFTPerShare).div(1e12).sub(
            user.rewardDebt
        );
        if (pending > 0) {
            safeGFTTransfer(_from, pending);
        }

        require(
            remove(user.amountToken, _tokenId),
            "AlianaMinting: withdraw: not good, remove from amountToken"
        );
        user.balance = user.balance.sub(1);
        user.amount = user.amount.sub(_amount);
        aliana.safeTransferFrom(address(this), address(_from), _tokenId, "");

        user.rewardDebt = user.amount.mul(accGFTPerShare).div(1e12);
        labor = labor.sub(_amount);
        emit Withdraw(_from, _tokenId, _amount, pending);
    }

    // Withdraw LP tokens from Mine.
    function withdraws(uint256[] memory _tokenIds) public {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            withdraw(_tokenIds[i]);
        }
    }

    // Withdraw LP tokens from Mine.
    function withdrawsByCEO(address _from, uint256[] memory _tokenIds)
        public
        onlyCEO
    {
        for (uint256 i = 0; i < _tokenIds.length; i++) {
            _withdrawFrom(_from, _tokenIds[i]);
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        _emergencyWithdrawFrom(msg.sender);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdrawByCEO(address _from) public onlyCEO {
        _emergencyWithdrawFrom(_from);
    }

    function _emergencyWithdrawFrom(address _from) internal {
        UserInfo storage user = userInfo[_from];
        uint256 amount = user.amount;

        for (
            uint256 i = iterate_start(user.amountToken);
            iterate_valid(user.amountToken, i);
            i = iterate_next(user.amountToken, i)
        ) {
            uint256 key = 0;
            uint256 value = 0;
            (key, value) = iterate_get(user.amountToken, i);
            aliana.safeTransferFrom(address(this), address(_from), key, "");
        }

        user.amount = 0;
        user.rewardDebt = 0;
        delete user.amountToken;
        user.balance = 0;
        labor = labor.sub(amount);
        emit EmergencyWithdraw(_from, amount);
    }

    // Safe GFT transfer function, just in case if rounding error causes pool to not have enough GFTs.
    function safeGFTTransfer(address _to, uint256 _amount) internal {
        uint256 gaeBalance = gftToken.balanceOf(address(this));
        require(gaeBalance >= _amount, "AlianaMinting: insufficient balance");
        rewardToDistribute = rewardToDistribute.sub(_amount);
        require(
            gftToken.transfer(_to, _amount),
            "AlianaMinting: failed to transfer gae token"
        );
    }

    function depositedTokens(address _owner)
        public
        view
        returns (uint256[] memory ownerTokens)
    {
        require(_owner != address(0), "AlianaMinting: zero address");

        UserInfo storage user = userInfo[_owner];
        uint256[] memory result = new uint256[](user.balance);
        uint256 resultIndex = 0;
        for (
            uint256 i = iterate_start(user.amountToken);
            iterate_valid(user.amountToken, i);
            i = iterate_next(user.amountToken, i)
        ) {
            uint256 key = 0;
            uint256 value = 0;
            (key, value) = iterate_get(user.amountToken, i);
            result[resultIndex] = key;
            resultIndex++;
        }
        return result;
    }

    /**
     * @dev Gets the balance of the specified address.
     * @param _owner address to query the balance of
     * @return uint256 representing the amount owned by the passed address
     */
    function depositedBalanceOf(address _owner) public view returns (uint256) {
        require(_owner != address(0), "AlianaMinting: zero address");
        UserInfo storage user = userInfo[_owner];
        return user.balance;
    }

    function receiveApproval(
        address _sender,
        uint256 _value,
        address _tokenContract,
        bytes memory _extraData
    ) public {
        require(_value >= 0, "AlianaMinting: approval negative");
        uint256 action;
        assembly {
            action := mload(add(_extraData, 0x20))
        }
        require(action == 1, "AlianaMinting: unknow action");
        if (action == 1) {
            // deposit
            require(
                _tokenContract == address(aliana),
                "AlianaMinting: approval and want mint use aliana, but used token isn't Aliana"
            );
            uint256 tokenId;
            assembly {
                tokenId := mload(add(_extraData, 0x40))
            }
            _depositFrom(_sender, tokenId);
        }
    }
}
