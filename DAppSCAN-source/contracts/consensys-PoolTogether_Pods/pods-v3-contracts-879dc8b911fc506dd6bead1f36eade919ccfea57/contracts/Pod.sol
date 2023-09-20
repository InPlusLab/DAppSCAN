// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

// Libraries
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// External Interfaces
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Ineritance
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// Internal Interfaces
import "./IPod.sol";
import "./TokenDrop.sol";
import "./IPodManager.sol";

// External Interfaces
import "./interfaces/TokenFaucet.sol";
import "./interfaces/IPrizePool.sol";
import "./interfaces/IPrizeStrategyMinimal.sol";

/**
 * @title Pod (Initialize, ERC20Upgradeable, OwnableUpgradeable, IPod) - Reduce User Gas Costs and Increase Odds of Winning via Collective Deposits.
 * @notice Pods turn PoolTogether deposits into shares and enable batched deposits, reudcing gas costs and collectively increasing odds  winning.
 * @dev Pods is a ERC20 token with features like shares, batched deposits and distributing mechanisms for distiubuting "bonus" tokens to users.
 * @author Kames Geraghty
 */
contract Pod is Initializable, ERC20Upgradeable, OwnableUpgradeable, IPod {
    /***********************************|
    |   Libraries                       |
    |__________________________________*/
    using SafeMath for uint256;

    /***********************************|
    |   Constants                       |
    |__________________________________*/
    IERC20Upgradeable public token;
    IERC20Upgradeable public ticket;
    IERC20Upgradeable public pool;

    // Initialized Contracts
    TokenFaucet public faucet;
    TokenDrop public drop;

    // Private
    IPrizePool private _prizePool;

    // Manager
    IPodManager public manager;

    // Factory
    address public factory;

    /**
     * @dev Pods can include token drops for multiple assets and not just the standard POOL.
     * Generally a Pod will only inlude a TokenDrop for POOL, but it's possible that a Pod
     * may add additional TokenDrops in the future. The Pod includes a `claimPodPool` method
     * to claim POOL, but other TokenDrops would require an external method for adding an
     * "asset" token to the TokenDrop smart contract, before calling the `claim` method.
     */
    mapping(address => TokenDrop) public drops;

    /***********************************|
    |   Events                          |
    |__________________________________*/
    /**
     * @dev Emitted when user deposits into batch backlog
     */
    event Deposited(address user, uint256 amount, uint256 shares);

    /**
     * @dev Emitted when user withdraws
     */
    event Withdrawl(address user, uint256 amount, uint256 shares);

    /**
     * @dev Emitted when batch deposit is executed
     */
    event Batch(uint256 amount, uint256 timestamp);

    /**
     * @dev Emitted when account sponsers pod.
     */
    event Sponsored(address sponsor, uint256 amount);

    /**
     * @dev Emitted when POOl is claimed for a user.
     */
    event Claimed(address user, uint256 balance);

    /**
     * @dev Emitted when POOl is claimed for the POD
     */
    event PodClaimed(uint256 amount);

    /**
     * @dev Emitted when a ERC20 is withdrawn
     */
    event ERC20Withdrawn(address target, uint256 tokenId);

    /**
     * @dev Emitted when a ERC721 is withdrawn
     */
    event ERC721Withdrawn(address target, uint256 tokenId);

    /**
     * @dev Emitted when account triggers drop calculation.
     */
    event DripCalculate(address account, uint256 amount);

    /**
     * @dev Emitted when liquidty manager is transfered.
     */
    event ManagementTransferred(
        address indexed previousmanager,
        address indexed newmanager
    );

    /***********************************|
    |   Modifiers                       |
    |__________________________________*/

    /**
     * @dev Checks is the caller is an active PodManager
     */
    modifier onlyManager() {
        require(
            address(manager) == _msgSender(),
            "Manager: caller is not the manager"
        );
        _;
    }

    /**
     * @dev Pause deposits during aware period. Prevents "frontrunning" for deposits into a winning Pod.
     */
    modifier pauseDepositsDuringAwarding() {
        require(
            !IPrizeStrategyMinimal(_prizePool.prizeStrategy()).isRngRequested(),
            "Cannot deposit while prize is being awarded"
        );
        _;
    }

    /***********************************|
    |   Constructor                     |
    |__________________________________*/

    /**
     * @notice Initialize the Pod Smart Contact with the target PrizePool configuration.
     * @dev The Pod Smart Contact is created and initialized using the PodFactory.
     * @param _prizePoolTarget Target PrizePool for deposits and withdraws
     * @param _ticket Non-sponsored PrizePool ticket - is verified during initialization.
     * @param _pool PoolTogether Goverance token - distributed for users with active deposits.
     * @param _faucet TokenFaucet reference that distributes POOL token for deposits
     * @param _manager Liquidates the Pod's "bonus" tokens for the Pod's token.
     */
    function initialize(
        address _prizePoolTarget,
        address _ticket,
        address _pool,
        address _faucet,
        address _manager
    ) external initializer {
        // Prize Pool
        _prizePool = IPrizePool(_prizePoolTarget);

        // Initialize ERC20Token
        __ERC20_init_unchained(
            string(
                abi.encodePacked(
                    "Pod ",
                    ERC20Upgradeable(_prizePool.token()).name()
                )
            ),
            string(
                abi.encodePacked(
                    "p",
                    ERC20Upgradeable(_prizePool.token()).symbol()
                )
            )
        );

        // Initialize Owner
        __Ownable_init_unchained();

        // Request PrizePool Tickets
        address[] memory tickets = _prizePool.tokens();

        // Check if ticket matches existing PrizePool Ticket
        require(
            address(_ticket) == address(tickets[0]) ||
                address(_ticket) == address(tickets[1]),
            "Pod:initialize-invalid-ticket"
        );

        // Initialize Core ERC20 Tokens
        token = IERC20Upgradeable(_prizePool.token());
        ticket = IERC20Upgradeable(tickets[1]);
        pool = IERC20Upgradeable(_pool);
        faucet = TokenFaucet(_faucet);

        // Pod Liquidation Manager
        manager = IPodManager(_manager);

        // Factory
        factory = msg.sender;
    }

    /***********************************|
    |   Public/External                 |
    |__________________________________*/

    /**
     * @notice The Pod manager address.
     * @dev Returns the address of the current Pod manager.
     * @return address manager
     */
    function podManager() external view returns (address) {
        return address(manager);
    }

    /**
     * @notice Update the Pod Mangeer
     * @dev Update the Pod Manger responsible for handling liquidations.
     * @return bool true
     */
    function setManager(IPodManager newManager)
        public
        virtual
        onlyOwner
        returns (bool)
    {
        // Require Valid Address
        require(address(manager) != address(0), "Pod:invalid-manager-address");

        // Emit ManagementTransferred
        emit ManagementTransferred(address(manager), address(newManager));

        // Update Manager
        manager = newManager;

        return true;
    }

    /**
     * @notice The Pod PrizePool reference
     * @dev Returns the address of the Pod prizepool
     * @return address The Pod prizepool
     */
    function prizePool() external view override returns (address) {
        return address(_prizePool);
    }

    /**
     * @notice Deposit assets into the Pod in exchange for share tokens
     * @param to The address that shall receive the Pod shares
     * @param tokenAmount The amount of tokens to deposit.  These are the same tokens used to deposit into the underlying prize pool.
     * @return The number of Pod shares minted.
     */
    function depositTo(address to, uint256 tokenAmount)
        external
        override
        returns (uint256)
    {
        require(tokenAmount > 0, "Pod:invalid-amount");

        // Allocate Shares from Deposit To Amount
        // SWC-107-Reentrancy: L275-282
        uint256 shares = _deposit(to, tokenAmount);

        // Transfer Token Transfer Message Sender
        // SWC-104-Unchecked Call Return Value: L279
        IERC20Upgradeable(token).transferFrom(
            msg.sender,
            address(this),
            tokenAmount
        );

        // Emit Deposited
        emit Deposited(to, tokenAmount, shares);

        // Return Shares Minted
        return shares;
    }

    /**
     * @notice Withdraws a users share of the prize pool.
     * @dev The function should first withdraw from the 'float'; i.e. the funds that have not yet been deposited.
     * @param shareAmount The number of Pod shares to redeem.
     * @return The actual amount of tokens that were transferred to the user.  This is the same as the deposit token.
     */
    function withdraw(uint256 shareAmount) external override returns (uint256) {
        // Check User Balance
        require(
            balanceOf(msg.sender) >= shareAmount,
            "Pod:insufficient-shares"
        );

        // Burn Shares and Return Tokens
        uint256 tokens = _burnShares(shareAmount);

        // Emit Withdrawl
        emit Withdrawl(msg.sender, tokens, shareAmount);

        return tokens;
    }

    /**
     * @notice Deposit Pod float into PrizePool.
     * @dev Deposits the current float amount into the PrizePool and claims current POOL rewards.
     * @param batchAmount Amount to deposit in PoolTogether PrizePool.
     */
    function batch(uint256 batchAmount) external override returns (bool) {
        uint256 tokenBalance = vaultTokenBalance();

        // Pod has a float above 0
        require(tokenBalance > 0, "Pod:zero-float-balance");

        // Batch Amount is EQUAL or LESS than vault token float balance..
        // batchAmount can be below tokenBalance to keep a withdrawble float amount.
        require(batchAmount <= tokenBalance, "Pod:insufficient-float-balance");

        // Claim POOL drop backlog.
        uint256 poolAmount = claimPodPool();

        // Emit PodClaimed
        emit PodClaimed(poolAmount);

        // Approve Prize Pool
        token.approve(address(_prizePool), tokenBalance);

        // PrizePool Deposit
        _prizePool.depositTo(
            address(this),
            batchAmount,
            address(ticket),
            address(this)
        );

        // Emit Batch
        emit Batch(tokenBalance, block.timestamp);

        return true;
    }

    /**
     * @notice Withdraw non-core (token/ticket/pool) ERC20 to Pod manager.
     * @dev Withdraws an ERC20 token amount from the Pod to the PodManager for liquidation to the token and back to the Pod.
     * @param _target ERC20 token to withdraw.
     * @param amount Amount of ERC20 to transfer/withdraw.
     * @return bool true
     */
    function withdrawERC20(IERC20Upgradeable _target, uint256 amount)
        external
        override
        onlyManager
        returns (bool)
    {
        // Lock token/ticket/pool ERC20 transfers
        require(
            address(_target) != address(token) &&
                address(_target) != address(ticket) &&
                address(_target) != address(pool),
            "Pod:invalid-target-token"
        );

        // Transfer Token
        _target.transfer(msg.sender, amount);

        emit ERC20Withdrawn(address(_target), amount);

        return true;
    }

    /**
     * @dev Withdraw ER721 reward tokens
     */
    /**
     * @notice Withdraw ER721 token to the Pod owner.
     * @dev Withdraw ER721 token to the Pod owner, which is responsible for deciding what/how to manage the collectible.
     * @param _target ERC721 token to withdraw.
     * @param tokenId The tokenId of the ERC721 collectible.
     * @return bool true
     */
    function withdrawERC721(IERC721 _target, uint256 tokenId)
        external
        override
        onlyManager
        returns (bool)
    {
        // Transfer ERC721
        _target.transferFrom(address(this), msg.sender, tokenId);

        // Emit ERC721Withdrawn
        emit ERC721Withdrawn(address(_target), tokenId);

        return true;
    }

    /**
     * @notice Allows a user to claim POOL tokens for an address.  The user will be transferred their share of POOL tokens.
     * @dev Allows a user to claim POOL tokens for an address.  The user will be transferred their share of POOL tokens.
     * @param user User account
     * @param _token The target token
     * @return uint256 Amount claimed.
     */
    function claim(address user, address _token)
        external
        override
        returns (uint256)
    {
        // Get token<>tokenDrop mapping
        require(
            drops[_token] != TokenDrop(address(0)),
            "Pod:invalid-token-drop"
        );

        // Claim POOL rewards
        uint256 _balance = drops[_token].claim(user);

        emit Claimed(user, _balance);

        return _balance;
    }

    /**
     * @notice Claims POOL for PrizePool Pod deposits
     * @dev Claim POOL for PrizePool Pod and adds/transfers those token to the Pod TokenDrop smart contract.
     * @return uint256 claimed amount
     */
    function claimPodPool() public returns (uint256) {
        uint256 _claimedAmount = faucet.claim(address(this));

        // Approve POOL transfer.
        pool.approve(address(drop), _claimedAmount);

        // Add POOl to TokenDrop balance
        drop.addAssetToken(_claimedAmount);

        // Claimed Amount
        return _claimedAmount;
    }

    /**
     * @notice Setup TokenDrop reference
     * @dev Initialize the Pod Smart Contact
     * @param _token IERC20Upgradeable
     * @param _tokenDrop TokenDrop address
     * @return bool true
     */
    function setTokenDrop(address _token, address _tokenDrop)
        external
        returns (bool)
    {
        require(
            msg.sender == factory || msg.sender == owner(),
            "Pod:unauthorized-set-token-drop"
        );

        // Check if target<>tokenDrop mapping exists
        require(
            drops[_token] == TokenDrop(0),
            "Pod:target-tokendrop-mapping-exists"
        );

        // Set TokenDrop Referance
        drop = TokenDrop(_tokenDrop);

        // Set target<>tokenDrop mapping
        drops[_token] = drop;

        return true;
    }

    /***********************************|
    |   Internal                        |
    |__________________________________*/

    /**
     * @dev The internal function for the public depositTo function, which calculates a user's allocated shares from deposited amoint.
     * @param user User's address.
     * @param amount Amount of "token" deposited into the Pod.
     * @return uint256 The share allocation amount.
     */
    function _deposit(address user, uint256 amount) internal returns (uint256) {
        uint256 allocation = 0;

        // Calculate Allocation
        if (totalSupply() == 0) {
            allocation = amount;
        } else {
            allocation = (amount.mul(totalSupply())).div(balance());
        }

        // Mint User Shares
        _mint(user, allocation);

        // Return Allocation Amount
        return allocation;
    }

    /**
     * @dev The internal function for the public withdraw function, which calculates a user's token allocation from burned shares.
     * @param shares Amount of "token" deposited into the Pod.
     * @return uint256 The token amount returned for the burned shares.
     */
    function _burnShares(uint256 shares) internal returns (uint256) {
        // Calculate Percentage Returned from Burned Shares
        uint256 amount = (balance().mul(shares)).div(totalSupply());

        // Burn Shares
        _burn(msg.sender, shares);

        // Check balance
        IERC20Upgradeable _token = IERC20Upgradeable(token);
        uint256 currentBalance = _token.balanceOf(address(this));

        // Withdrawl Exceeds Current Token Balance
        if (amount > currentBalance) {
            // Calculate Withdrawl Amount
            uint256 _withdraw = amount.sub(currentBalance);

            // Withdraw from Prize Pool
            uint256 exitFee = _withdrawFromPool(_withdraw);

            // Add Exit Fee to Withdrawl Amount
            amount = amount.sub(exitFee);
        }

        // Transfer Deposit Token to Message Sender
        _token.transfer(msg.sender, amount);

        // Return Token Withdrawl Amount
        return amount;
    }

    /**
     * @dev Withdraws from Pod prizePool if the float balance can cover the total withdraw amount.
     * @param _amount Amount of tokens to withdraw in exchange for the tickets transfered.
     * @return uint256 The exit fee paid for withdraw from the prizePool instant withdraw method.
     */
    function _withdrawFromPool(uint256 _amount) internal returns (uint256) {
        IPrizePool _pool = IPrizePool(_prizePool);

        // Calculate Early Exit Fee
        (uint256 exitFee, ) =
            _pool.calculateEarlyExitFee(
                address(this),
                address(ticket),
                _amount
            );

        // Withdraw from Prize Pool
        uint256 exitFeePaid =
            _pool.withdrawInstantlyFrom(
                address(this),
                _amount,
                address(ticket),
                exitFee
            );

        // Exact Exit Fee
        return exitFeePaid;
    }

    /***********************************|
    |  Views                            |
    |__________________________________*/

    /**
     * @notice Calculate the cost of the Pod's token price per share. Until a Pod has won or been "airdropped" tokens it's 1.
     * @dev Based of the Pod's total token/ticket balance and totalSupply it calculates the pricePerShare.
     */
    function getPricePerShare() external view override returns (uint256) {
        // Check totalSupply to prevent SafeMath: division by zero
        if (totalSupply() > 0) {
            return balance().mul(1e18).div(totalSupply());
        } else {
            return 0;
        }
    }

    /**
     * @notice Calculate the cost of the user's price per share based on a Pod's token/ticket balance.
     * @dev Calculates the cost of the user's price per share based on a Pod's token/ticket balance.
     */
    function getUserPricePerShare(address user)
        external
        view
        returns (uint256)
    {
        // Check totalSupply to prevent SafeMath: division by zero
        if (totalSupply() > 0) {
            return balanceOf(user).mul(1e18).div(balance());
        } else {
            return 0;
        }
    }

    /**
     * @notice Pod current token balance.
     * @dev Request's the Pod's current token balance by calling balanceOf(address(this)).
     * @return uint256 Pod's current token balance.
     */
    function vaultTokenBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    /**
     * @notice Pod current ticket balance.
     * @dev Request's the Pod's current ticket balance by calling balanceOf(address(this)).
     * @return uint256 Pod's current ticket balance.
     */
    function vaultTicketBalance() public view returns (uint256) {
        return ticket.balanceOf(address(this));
    }

    /**
     * @notice Pod current POOL balance.
     * @dev Request's the Pod's current POOL balance by calling balanceOf(address(this)).
     * @return uint256 Pod's current POOL balance.
     */
    function vaultPoolBalance() public view returns (uint256) {
        return pool.balanceOf(address(this));
    }

    /**
     * @notice Measure's the Pod's total balance by adding the vaultTokenBalance and vaultTicketBalance
     * @dev The Pod's token and ticket balance are equal in terms of "value" and thus are used to calculate's a Pod's true balance.
     * @return uint256 Pod's token and ticket balance.
     */
    function balance() public view returns (uint256) {
        return vaultTokenBalance().add(vaultTicketBalance());
    }

    /***********************************|
    | ERC20 Overrides                   |
    |__________________________________*/

    /**
     * @notice Add TokenDrop to mint()
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     * @param from Account sending tokens
     * @param to Account recieving tokens
     * @param amount Amount of tokens sent
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        // Call _beforeTokenTransfer from contract inheritance
        super._beforeTokenTransfer(from, to, amount);

        // Update TokenDrop internals
        drop.beforeTokenTransfer(from, to, address(this));

        // Emit DripCalculate
        emit DripCalculate(from, amount);
    }
}
