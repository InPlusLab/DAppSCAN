// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

/**
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 * 
 * The renounceOwnership removed to prevent accidents
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}


/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

contract ThorusLottery is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable treasury;
    IERC20 public immutable thorus;
    IERC20 public immutable dai;
    uint256 public immutable ticketPrice;
    uint256 public rewardOffered;

    bool public buyingAllowed = false;
    bool public claimingAllowed = false;
    bool public ticketsWithdrawn = false;

    uint256 public immutable winningCount; //including the first one
    uint256 public firstWinningNumber;
    uint256 public lastWinningNumber;
    uint256 public settlementBlockNumber;

    uint256 public immutable firstWinningPermille; //reward for 1st
    uint256 public immutable secondWinningPermille; //reward for 2nd
    uint256 public immutable thirdWinningPermille; //reward for 3rd
    uint256 public immutable lastWinningPermille; //reward for the rest

    event BuyingStarted();
    event BuyingStopped();
    event SettleRandomResult();
    event TicketsWithdrawn();
    event RewardSet();
    event ClaimingStarted();
    event Buy(uint256 amount, address indexed user);
    event Claim(uint256 amount, address indexed user);

    struct Ticket {
        address owner;
        bool isClaimed;
    }

    Ticket[] public tickets;
    uint256[] public ticketNumbers;
    mapping(address => uint256[]) public ownedTickets;

    constructor(
        address _treasury,
        IERC20 _thorus,
        IERC20 _dai,
        uint256 _ticketPrice,
        uint256 _winningCount,
        uint256 _firstWinningPermille,
        uint256 _secondWinningPermille,
        uint256 _thirdWinningPermille,
        uint256 _lastWinningPermille
        ) {
        require(
            address(_thorus) != address(0) && _treasury != address(0) && address(_dai) != address(0),
            "zero address in constructor"
        );
        require(_winningCount >= 3, "at least 3 winners");
        require(
            _firstWinningPermille + _secondWinningPermille + _thirdWinningPermille + _lastWinningPermille * (_winningCount - 3) == 1000,
            "wrong permilles"
        );
        treasury = _treasury;
        thorus = _thorus;
        dai = _dai;
        ticketPrice = _ticketPrice;
        winningCount = _winningCount;
        firstWinningPermille = _firstWinningPermille;
        secondWinningPermille = _secondWinningPermille;
        thirdWinningPermille = _thirdWinningPermille;
        lastWinningPermille = _lastWinningPermille;
    }

    function allowBuying() external onlyOwner {
        require(!buyingAllowed, "buying already allowed");
        require(!ticketsWithdrawn, "tickets already withdrawn");

        buyingAllowed = true;
        emit BuyingStarted();
    }

    function disallowBuying() external onlyOwner {
        require(buyingAllowed, "buying already disallowed");
        
        buyingAllowed = false;
        emit BuyingStopped();
    }

    function setRewardOffered(uint256 _rewardOffered) external onlyOwner {
        require(!buyingAllowed, "buying still allowed");
        require(!claimingAllowed, "claiming already allowed");
        require(dai.balanceOf(address(this)) >= _rewardOffered, "transfer needed funds first!");
        require(_rewardOffered > rewardOffered, "new reward lower");

        rewardOffered = _rewardOffered;
        emit RewardSet();
    }

    function allowClaiming() external onlyOwner {
        require(!claimingAllowed, "claiming already allowed");
        require(ticketsWithdrawn, "tickets not yet withdrawn");
        require(rewardOffered > 0, "reward not yet set");
        uint256 excessAmount = dai.balanceOf(address(this)) - rewardOffered;
        if(excessAmount > 0)
            dai.safeTransfer(treasury, excessAmount);

        claimingAllowed = true;
        emit ClaimingStarted();
    }

    function ticketsCount() external view returns (uint256) {
        return tickets.length;
    }

    function buyTickets(uint256 amount) external nonReentrant {
        require(buyingAllowed, "buying not allowed");
        require(amount <= 100, "exceed maximum limit");

        thorus.safeTransferFrom(msg.sender, treasury, amount * ticketPrice);
        for(uint256 i=0; i<amount; i++) {
            tickets.push(
                Ticket({
                    owner: msg.sender,
                    isClaimed: false
                })
            );
            ownedTickets[msg.sender].push(tickets.length - 1);

            if (ticketNumbers.length == 0) {
                ticketNumbers.push(0);
            } else {
                uint256 randomIndex = uint256(keccak256(abi.encodePacked(
                    block.difficulty,
                    block.timestamp,
                    block.number,
                    tickets.length,
                    thorus.totalSupply()
                ))) % ticketNumbers.length;
                uint256 tempNumber = ticketNumbers[randomIndex];
                ticketNumbers[randomIndex] = tickets.length - 1;
                ticketNumbers.push(tempNumber);
            }
        }
        emit Buy(amount, msg.sender);
    }

    function settleRandomResult() external onlyOwner {
        require(!buyingAllowed, "buying still allowed");
        require(!ticketsWithdrawn, "tickets already withdrawn");
        require(tickets.length > 0, "no tickets sold yet");
        require(settlementBlockNumber == 0 || block.number - settlementBlockNumber >= 256, "settlementBlockNumber block is already set");
    
        settlementBlockNumber = block.number + 10;
        emit SettleRandomResult();
    }

    function withdrawWinningTickets() external onlyOwner {
        require(block.number > settlementBlockNumber , "settlementBlockNumber block is not arrived yet");
        require(block.number - settlementBlockNumber < 256, "settlementBlockNumber block is expired");
        firstWinningNumber =  uint256(blockhash(settlementBlockNumber)) % tickets.length;
        lastWinningNumber = firstWinningNumber + winningCount;
        ticketsWithdrawn = true;
        emit TicketsWithdrawn();
    }

    function isWinning(uint256 ticketIndex) public view returns (bool) {
        if(firstWinningNumber <= ticketNumbers[ticketIndex] && ticketNumbers[ticketIndex] < lastWinningNumber)
            return true;
        if(lastWinningNumber > tickets.length && ticketNumbers[ticketIndex] < (lastWinningNumber % tickets.length))
            return true;
        return false;
    }

    function isFirstWinning(uint256 ticketIndex) public view returns (bool) {
        if(firstWinningNumber == ticketNumbers[ticketIndex])
            return true;
        return false;
    }

    function isSecondWinning(uint256 ticketIndex) public view returns (bool) {
        if(firstWinningNumber + 1 == ticketNumbers[ticketIndex])
            return true;
        if(firstWinningNumber + 1 == tickets.length && ticketNumbers[ticketIndex] == 0)
            return true;
        return false;
    }

    function isThirdWinning(uint256 ticketIndex) public view returns (bool) {
        if(firstWinningNumber + 2 == ticketNumbers[ticketIndex])
            return true;
        if(firstWinningNumber + 1 == tickets.length && ticketNumbers[ticketIndex] == 1)
            return true;
        if(firstWinningNumber + 2 == tickets.length && ticketNumbers[ticketIndex] == 0)
            return true;
        return false;
    }

    function ownerWinningTicketsCount(address owner) public view returns (uint256) {
        uint256 count = 0;
        for(uint256 i=0; i<ownedTickets[owner].length; i++) {
            uint256 ticketIndex = ownedTickets[owner][i];
            if(isWinning(ticketIndex)) count++;
        }
        return count;
    }

    function ownerTicketsCount(address owner) public view returns (uint256) {
        return ownedTickets[owner].length;
    }

    function ownerClaimableTicketsCount(address owner) public view returns (uint256) {
        uint256 count = 0;
        for(uint256 i=0; i<ownedTickets[owner].length; i++) {
            uint256 ticketIndex = ownedTickets[owner][i];
            if(isWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) count++;
        }
        return count;
    }

    function getFirstWinning() public view returns (address) {
        if(!ticketsWithdrawn)
            return address(0);
        for(uint256 i=0; i<tickets.length; i++) {
            if(isFirstWinning(i))
                return tickets[i].owner;
        }
        return address(0);
    }

    function getSecondWinning() public view returns (address) {
        if(!ticketsWithdrawn)
            return address(0);
        for(uint256 i=0; i<tickets.length; i++) {
            if(isSecondWinning(i))
                return tickets[i].owner;
        }
        return address(0);
    }

    function getThirdWinning() public view returns (address) {
        if(!ticketsWithdrawn)
            return address(0);
        for(uint256 i=0; i<tickets.length; i++) {
            if(isThirdWinning(i))
                return tickets[i].owner;
        }
        return address(0);
    }

    function getWinning() public view returns (address[] memory) {
        address[] memory result = new address[](winningCount-3);
        if(!ticketsWithdrawn)
            return result;
        uint256 j = 0;
        for(uint256 i=0; i<tickets.length; i++) {
            if(isWinning(i) && !isFirstWinning(i) && !isSecondWinning(i) && !isThirdWinning(i)) {
                result[j] = tickets[i].owner;
                j++;
            }

        }

        return result;
    }

    function claimTickets(uint256[] calldata ticketIndexes) external nonReentrant {
        require(claimingAllowed, "claiming not allowed");
        uint256 reward = 0;
        for(uint256 i=0; i<ticketIndexes.length; i++) {
            uint256 ticketIndex = ticketIndexes[i];
            require(tickets[ticketIndex].owner == msg.sender, "user not owner of the ticket");
            if(isFirstWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) {
                tickets[ticketIndex].isClaimed = true;
                reward += rewardOffered * firstWinningPermille / 1000;
            } else if(isSecondWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) {
                tickets[ticketIndex].isClaimed = true;
                reward += rewardOffered * secondWinningPermille / 1000;
            } else if(isThirdWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) {
                tickets[ticketIndex].isClaimed = true;
                reward += rewardOffered * thirdWinningPermille / 1000;
            } else if(isWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) {
                tickets[ticketIndex].isClaimed = true;
                reward += rewardOffered * lastWinningPermille / 1000;
            }
        }
        dai.safeTransfer(msg.sender, reward);
        emit Claim(reward, msg.sender);
    }

    function claimTickets() external nonReentrant {
        require(claimingAllowed, "claiming not allowed");
        uint256 reward = 0;
        for(uint256 i=0; i<ownedTickets[msg.sender].length; i++) {
            uint256 ticketIndex = ownedTickets[msg.sender][i];
            if(isFirstWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) {
                tickets[ticketIndex].isClaimed = true;
                reward += rewardOffered * firstWinningPermille / 1000;
            } else if(isSecondWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) {
                tickets[ticketIndex].isClaimed = true;
                reward += rewardOffered * secondWinningPermille / 1000;
            } else if(isThirdWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) {
                tickets[ticketIndex].isClaimed = true;
                reward += rewardOffered * thirdWinningPermille / 1000;
            } else if(isWinning(ticketIndex) && !tickets[ticketIndex].isClaimed) {
                tickets[ticketIndex].isClaimed = true;
                reward += rewardOffered * lastWinningPermille / 1000;
            }
        }
        dai.safeTransfer(msg.sender, reward);
        emit Claim(reward, msg.sender);
    }
}
