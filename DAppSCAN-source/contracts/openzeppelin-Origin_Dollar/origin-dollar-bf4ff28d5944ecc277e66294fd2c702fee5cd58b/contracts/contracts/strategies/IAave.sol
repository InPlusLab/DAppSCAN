pragma solidity 0.5.11;

/**
 * @dev Interface for Aaves A Token
 * Documentation: https://developers.aave.com/#atokens
 */
interface IAaveAToken {
    /**
     * @notice Non-standard ERC20 function to redeem an _amount of aTokens for the underlying
     * asset, burning the aTokens during the process.
     * @param _amount Amount of aTokens
     */
    function redeem(uint256 _amount) external;

    /**
     * @notice returns the current total aToken balance of _user all interest collected included.
     * To obtain the user asset principal balance with interests excluded , ERC20 non-standard
     * method principalBalanceOf() can be used.
     */
    function balanceOf(address _user) external view returns (uint256);
}

/**
 * @dev Interface for Aaves Lending Pool
 * Documentation: https://developers.aave.com/#lendingpool
 */
interface IAaveLendingPool {
    /**
     * @dev Deposits an `amount` of underlying asset into the reserve, receiving in return overlying aTokens.
     * - E.g. User deposits 100 USDC and gets in return 100 aUSDC
     * @param asset The address of the underlying asset to deposit
     * @param amount The amount to be deposited
     * @param onBehalfOf The address that will receive the aTokens, same as msg.sender if the user
     *   wants to receive them on his own wallet, or a different address if the beneficiary of aTokens
     *   is a different wallet
     * @param referralCode Code used to register the integrator originating the operation, for potential rewards.
     *   0 if the action is executed directly by the user, without any middle-man
     **/
    function deposit(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    /**
     * @dev Withdraws an `amount` of underlying asset from the reserve, burning the equivalent aTokens owned
     * E.g. User has 100 aUSDC, calls withdraw() and receives 100 USDC, burning the 100 aUSDC
     * @param asset The address of the underlying asset to withdraw
     * @param amount The underlying amount to be withdrawn
     *   - Send the value type(uint256).max in order to withdraw the whole aToken balance
     * @param to Address that will receive the underlying, same as msg.sender if the user
     *   wants to receive it on his own wallet, or a different address if the beneficiary is a
     *   different wallet
     * @return The final amount withdrawn
     **/
    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256);
}

/**
 * @dev Interface for Aaves Lending Pool
 * Documentation: https://developers.aave.com/#lendingpooladdressesprovider
 */
interface ILendingPoolAddressesProvider {
    /**
     * @notice Get the current address for Aave LendingPool
     * @dev Lending pool is the core contract on which to call deposit
     */
    function getLendingPool() external view returns (address);

    /**
     * @notice Get the address for lendingPoolCore
     * @dev IMPORTANT - this is where _reserve must be approved before deposit
     */
    function getLendingPoolCore() external view returns (address payable);
}
