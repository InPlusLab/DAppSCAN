// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.8.0;

// External Interfaces
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

// External Libraries
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@pooltogether/fixed-point/contracts/FixedPoint.sol";

// Local Interfaces
// import "./interfaces/TokenListenerInterface.sol";

// Local Libraries
import "./libraries/ExtendedSafeCast.sol";

/**
 * @title TokenDrop - Calculates Asset Distribution using Measure Token
 * @notice Calculates distribution of POOL rewards for users deposting into PoolTogether PrizePools using the Pod smart contract.
 * @dev A simplified version of the PoolTogether TokenFaucet that simplifies an asset token distribution using totalSupply calculations.
 * @author Kames Cox-Geraghty
 */
contract TokenDrop is Initializable {
    /***********************************|
    |   Libraries                       |
    |__________________________________*/
    using SafeMath for uint256;
    using ExtendedSafeCast for uint256;

    /***********************************|
    |   Constants                       |
    |__________________________________*/
    /// @notice The token that is being disbursed
    IERC20Upgradeable public asset;

    /// @notice The token that is user to measure a user's portion of disbursed tokens
    IERC20Upgradeable public measure;

    /// @notice The cumulative exchange rate of measure token supply : dripped tokens
    uint112 public exchangeRateMantissa;

    /// @notice The total amount of tokens that have been dripped but not claimed
    uint112 public totalUnclaimed;

    /// @notice The timestamp at which the tokens were last dripped
    uint32 public lastDripTimestamp;

    // Factory
    address public factory;

    /***********************************|
    |   Events                          |
    |__________________________________*/
    event Dripped(uint256 newTokens);

    event Deposited(address indexed user, uint256 amount);

    event Claimed(address indexed user, uint256 newTokens);

    /***********************************|
    |   Structs                         |
    |__________________________________*/
    struct UserState {
        uint128 lastExchangeRateMantissa;
        uint256 balance;
    }

    /**
     * @notice The data structure that tracks when a user last received tokens
     */
    mapping(address => UserState) public userStates;

    /***********************************|
    |   Initialize                      |
    |__________________________________*/
    /**
     * @notice Initialize TokenDrop Smart Contract
     */
    // SWC-105-Unprotected Ether Withdrawal: L82-88
    function initialize(address _measure, address _asset) external {
        measure = IERC20Upgradeable(_measure);
        asset = IERC20Upgradeable(_asset);

        // Set Factory Deployer
        factory = msg.sender;
    }

    /***********************************|
    |   Public/External                 |
    |__________________________________*/

    /**
     * @notice Should be called before "measure" tokens are transferred or burned
     * @param from The user who is sending the tokens
     * @param to The user who is receiving the tokens
     *@param token The token token they are burning
     */
    function beforeTokenTransfer(
        address from,
        address to,
        address token
    ) external {
        // must be measure and not be minting
        if (token == address(measure)) {
            drop();

            // Calcuate to tokens balance
            _captureNewTokensForUser(to);

            // If NOT minting calcuate from tokens balance
            if (from != address(0)) {
                _captureNewTokensForUser(from);
            }
        }
    }

    /**
     * @notice Add Asset to TokenDrop and update with drop()
     * @dev Add Asset to TokenDrop and update with drop()
     * @param amount User account
     */
    function addAssetToken(uint256 amount) external returns (bool) {
        // Transfer asset/reward token from msg.sender to TokenDrop
        asset.transferFrom(msg.sender, address(this), amount);

        // Update TokenDrop asset balance
        drop();

        // Return BOOL for transaction gas savings
        return true;
    }

    /**
     * @notice Claim asset rewards
     * @dev Claim asset rewards
     * @param user User account
     */
     // SWC-107-Reentrancy: L141-155
    function claim(address user) external returns (uint256) {
        drop();
        _captureNewTokensForUser(user);
        uint256 balance = userStates[user].balance;
        userStates[user].balance = 0;
        totalUnclaimed = uint256(totalUnclaimed).sub(balance).toUint112();

        // Transfer asset/reward token to user
        asset.transfer(user, balance);

        // Emit Claimed
        emit Claimed(user, balance);

        return balance;
    }

    /**
     * @notice Drips new tokens.
     * @dev Should be called immediately before any measure token mints/transfers/burns
     * @return The number of new tokens dripped.
     */

    // change to drop
    function drop() public returns (uint256) {
        uint256 assetTotalSupply = asset.balanceOf(address(this));
        uint256 newTokens = assetTotalSupply.sub(totalUnclaimed);

        // if(newTokens > 0)
        if (newTokens > 0) {
            // Check measure token totalSupply()
            uint256 measureTotalSupply = measure.totalSupply();

            // Check measure supply exists
            if (measureTotalSupply > 0) {
                uint256 indexDeltaMantissa =
                    FixedPoint.calculateMantissa(newTokens, measureTotalSupply);
                uint256 nextExchangeRateMantissa =
                    uint256(exchangeRateMantissa).add(indexDeltaMantissa);

                exchangeRateMantissa = nextExchangeRateMantissa.toUint112();
                totalUnclaimed = uint256(totalUnclaimed)
                    .add(newTokens)
                    .toUint112();
            }
            // Emit Dripped
            emit Dripped(newTokens);
        }

        return newTokens;
    }

    /***********************************|
    |   Private/Internal                |
    |__________________________________*/

    /**
     * @notice Captures new tokens for a user
     * @dev This must be called before changes to the user's balance (i.e. before mint, transfer or burns)
     * @param user The user to capture tokens for
     * @return The number of new tokens
     */
    function _captureNewTokensForUser(address user) private returns (uint128) {
        UserState storage userState = userStates[user];
        if (exchangeRateMantissa == userState.lastExchangeRateMantissa) {
            // ignore if exchange rate is same
            return 0;
        }
        uint256 deltaExchangeRateMantissa =
            uint256(exchangeRateMantissa).sub(
                userState.lastExchangeRateMantissa
            );
        uint256 userMeasureBalance = measure.balanceOf(user);
        uint128 newTokens =
            FixedPoint
                .multiplyUintByMantissa(
                userMeasureBalance,
                deltaExchangeRateMantissa
            )
                .toUint128();

        userStates[user] = UserState({
            lastExchangeRateMantissa: exchangeRateMantissa,
            balance: uint256(userState.balance).add(newTokens).toUint128()
        });

        return newTokens;
    }

    function supportsInterface(bytes4 interfaceId)
        external
        view
        returns (bool)
    {
        return true;
    }
}
