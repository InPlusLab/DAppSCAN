pragma solidity 0.5.16;

import "openzeppelin-solidity-2.3.0/contracts/token/ERC20/IERC20.sol";

// Making the original MasterChef as an interface leads to compilation fail.
// Use Contract instead of Interface here
contract IMasterChef {
    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. Cakes to distribute per block.
        uint256 lastRewardBlock; // Last block number that Cakes distribution occurs.
        uint256 accCakePerShare; // Accumulated Cakes per share, times 1e12. See below.
    }

    address public cake;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => PoolInfo) public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Deposit LP tokens to MasterChef for Cake allocation.
    function deposit(uint256 _pid, uint256 _amount) external {}

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external {}
}
