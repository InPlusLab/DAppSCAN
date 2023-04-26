pragma solidity ^0.5.16;
import "./Utils/SafeBEP20.sol";
import "./Utils/IBEP20.sol";
import "./VaultProxy.sol";
import "./VaultStorage.sol";
import "./VaultErrorReporter.sol";

contract Vault is VaultStorage {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    /// @notice Event emitted when deposit
    event Deposit(address indexed user, uint256 amount);

    /// @notice Event emitted when withrawal
    event Withdraw(address indexed user, uint256 amount);

    /// @notice Event emitted when admin changed
    event AdminTransfered(address indexed oldAdmin, address indexed newAdmin);

    constructor() public {
        admin = msg.sender;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can");
        _;
    }

    /*** Reentrancy Guard ***/

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     */
    modifier nonReentrant() {
        require(_notEntered, "re-entered");
        _notEntered = false;
        _;
        _notEntered = true; // get a gas-refund post-Istanbul
    }

    /**
     * @notice Deposit to Vault for Atlantis allocation
     * @param _amount The amount to deposit to vault
     */
    function deposit(uint256 _amount) public nonReentrant {
        UserInfo storage user = userInfo[msg.sender];

        updateVault();

        // Transfer pending tokens to user
        updateAndPayOutPending(msg.sender);

        // Transfer in the amounts from user
        if(_amount > 0) {
            stakedToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }

        user.rewardDebt = user.amount.mul(accAtlantisPerShare).div(1e18);
        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Withdraw from Vault
     * @param _amount The amount to withdraw from vault
     */
    function withdraw(uint256 _amount) public nonReentrant {
        _withdraw(msg.sender, _amount);
    }

    /**
     * @notice Claim Atlantis from Vault
     */
    function claim() public nonReentrant {
        _withdraw(msg.sender, 0);
    }

    /**
     * @notice Low level withdraw function
     * @param account The account to withdraw from vault
     * @param _amount The amount to withdraw from vault
     */
    function _withdraw(address account, uint256 _amount) internal {
        UserInfo storage user = userInfo[account];
        require(user.amount >= _amount, "withdraw: not good");

        updateVault();
        updateAndPayOutPending(account); // Update balances of account this is not withdrawal but claiming Atlantis farmed

        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            stakedToken.safeTransfer(address(account), _amount);
        }
        user.rewardDebt = user.amount.mul(accAtlantisPerShare).div(1e18);

        emit Withdraw(account, _amount);
    }

    /**
     * @notice View function to see pending Atlantis on frontend
     * @param _user The user to see pending Atlantis
     */
    function pendingAtlantis(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        return user.amount.mul(accAtlantisPerShare).div(1e18).sub(user.rewardDebt);
    }

    /**
     * @notice Update and pay out pending Atlantis to user
     * @param account The user to pay out
     */
    function updateAndPayOutPending(address account) internal {
        uint256 pending = pendingAtlantis(account);

        if(pending > 0) {
            IAtlantisStore(atlantisStore).safeAtlantisTransfer(account, pending);
            atlantisBalance = IAtlantisStore(atlantisStore).atlantisBalance();
        }
    }

    /**
     * @notice Function that updates pending rewards
     */
    function updatePendingRewards() public {
        uint256 existingRewards = IAtlantisStore(atlantisStore).atlantisBalance();
        uint256 newRewards = existingRewards.sub(atlantisBalance);

        if(newRewards > 0) {
            atlantisBalance = IAtlantisStore(atlantisStore).atlantisBalance(); // If there is no change the balance didn't change
            pendingRewards = pendingRewards.add(newRewards);
        }
    }

    /**
     * @notice Update reward variables to be up-to-date
     */
    function updateVault() internal {
        uint256 stakedTokenBalance = stakedToken.balanceOf(address(this));
        if (stakedTokenBalance == 0) { // avoids division by 0 errors
            return;
        }

        accAtlantisPerShare = accAtlantisPerShare.add(pendingRewards.mul(1e18).div(stakedTokenBalance));
        pendingRewards = 0;
    }

    /**
     * @dev Returns the address of the current admin
     */
    function getAdmin() public view returns (address) {
        return admin;
    }

    /**
     * @dev Burn the current admin
     */
    function burnAdmin() public onlyAdmin {
        emit AdminTransfered(admin, address(0));
        admin = address(0);
    }

    /**
     * @dev Set the current admin to new address
     */
    function setNewAdmin(address newAdmin) public onlyAdmin {
        require(newAdmin != address(0), "new owner is the zero address");
        emit AdminTransfered(admin, newAdmin);
        admin = newAdmin;
    }

    /*** Admin Functions ***/

    function _become(VaultProxy vaultProxy) public {
        require(msg.sender == vaultProxy.admin(), "only proxy admin can change brains");
        require(vaultProxy._acceptImplementation() == 0, "change not authorized");
    }

    function setAtlantisInfo(address _atlantisStore, address _stakedToken) public onlyAdmin {
        atlantisStore = _atlantisStore;
        stakedToken = IBEP20(_stakedToken);
        _notEntered = true;
    }

    /**
     * @dev Returns the address of the atlantis store
     */
    function getAtlantisStore() public view returns (address) {
        return address(atlantisStore);
    }
}

interface IAtlantisStore {
    function safeAtlantisTransfer(address _to, uint256 _amount) external;
    function atlantisBalance() external returns (uint256);
}