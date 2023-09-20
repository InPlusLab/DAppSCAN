
//                                                                           ,,---.
//                                                                         .-^^,_  `.
//                                                                    ;`, / 3 ( o\   }
//         __             __                     ___              __  \  ;   \`, /  ,'
//        /\ \__         /\ \                  /'___\ __         /\ \ ;_/^`.__.-"  ,'
//    ____\ \ ,_\    __  \ \ \/'\      __     /\ \__//\_\    ____\ \ \___     `---'
//   /',__\\ \ \/  /'__`\ \ \ , <    /'__`\   \ \ ,__\/\ \  /',__\\ \  _ `\
//  /\__, `\\ \ \_/\ \L\.\_\ \ \\`\ /\  __/  __\ \ \_/\ \ \/\__, `\\ \ \ \ \
//  \/\____/ \ \__\ \__/.\_\\ \_\ \_\ \____\/\_\\ \_\  \ \_\/\____/ \ \_\ \_\
//   \/___/   \/__/\/__/\/_/ \/_/\/_/\/____/\/_/ \/_/   \/_/\/___/   \/_/\/_/

// stakefish ETH2 Batch Deposit contract
// this contract allows deposit of multiple validators in one tx
// and also collects the validator fee for stakefish

// SPDX-License-Identifier: Apache-2.0
// SWC-102-Outdated Compiler Version: L19
pragma solidity 0.6.11;

import "../node_modules/@openzeppelin/contracts/utils/Pausable.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/math/SafeMath.sol";

// Deposit contract interface
interface IDepositContract {
    /// @notice A processed deposit event.
    event DepositEvent(
        bytes pubkey,
        bytes withdrawal_credentials,
        bytes amount,
        bytes signature,
        bytes index
    );

    /// @notice Submit a Phase 0 DepositData object.
    /// @param pubkey A BLS12-381 public key.
    /// @param withdrawal_credentials Commitment to a public key for withdrawals.
    /// @param signature A BLS12-381 signature.
    /// @param deposit_data_root The SHA-256 hash of the SSZ-encoded DepositData object.
    /// Used as a protection against malformed input.
    function deposit(
        bytes calldata pubkey,
        bytes calldata withdrawal_credentials,
        bytes calldata signature,
        bytes32 deposit_data_root
    ) external payable;

    /// @notice Query the current deposit root hash.
    /// @return The deposit root hash.
    function get_deposit_root() external view returns (bytes32);

    /// @notice Query the current deposit count.
    /// @return The deposit count encoded as a little endian 64-bit number.
    function get_deposit_count() external view returns (bytes memory);
}


contract BatchDeposit is Pausable, Ownable {
    using SafeMath for uint256;

    address depositContract;
    uint256 private _fee;

    uint256 constant PUBKEY_LENGTH = 48;
    uint256 constant SIGNATURE_LENGTH = 96;
    uint256 constant CREDENTIALS_LENGTH = 32;
    uint256 constant MAX_VALIDATORS = 100;
    uint256 constant DEPOSIT_AMOUNT = 32 ether;

    event FeeChanged(uint256 previousFee, uint256 newFee);
    event Withdrawn(address indexed payee, uint256 weiAmount);
    event FeeCollected(address indexed payee, uint256 weiAmount);

    constructor(address depositContractAddr, uint256 initialFee) public {
        require(initialFee % 1 gwei == 0, "Fee must be a multiple of GWEI");

        depositContract = depositContractAddr;
        _fee = initialFee;
    }

    /**
     * @dev Performs a batch deposit, asking for an additional fee payment.
     */
    //  SWC-114-Transaction Order Dependence: L86 - L122
    function batchDeposit(
        bytes calldata pubkeys, 
        bytes calldata withdrawal_credentials, 
        bytes calldata signatures, 
        bytes32[] calldata deposit_data_roots
    ) 
        external payable whenNotPaused 
    {
        // sanity checks
        require(msg.value % 1 gwei == 0, "BatchDeposit: Deposit value not multiple of GWEI");
        require(msg.value >= DEPOSIT_AMOUNT, "BatchDeposit: Amount is too low");

        uint256 count = deposit_data_roots.length;
        require(count > 0, "BatchDeposit: You should deposit at least one validator");
        require(count <= MAX_VALIDATORS, "BatchDeposit: You can deposit max 100 validators at a time");

        require(pubkeys.length == count * PUBKEY_LENGTH, "BatchDeposit: Pubkey count don't match");
        require(signatures.length == count * SIGNATURE_LENGTH, "BatchDeposit: Signatures count don't match");
        require(withdrawal_credentials.length == 1 * CREDENTIALS_LENGTH, "BatchDeposit: Withdrawal Credentials count don't match");

        uint256 expectedAmount = _fee.add(DEPOSIT_AMOUNT).mul(count);
        require(msg.value == expectedAmount, "BatchDeposit: Amount is not aligned with pubkeys number");

        emit FeeCollected(msg.sender, _fee.mul(count));

        for (uint256 i = 0; i < count; ++i) {
            bytes memory pubkey = bytes(pubkeys[i*PUBKEY_LENGTH:(i+1)*PUBKEY_LENGTH]);
            bytes memory signature = bytes(signatures[i*SIGNATURE_LENGTH:(i+1)*SIGNATURE_LENGTH]);

            IDepositContract(depositContract).deposit{value: DEPOSIT_AMOUNT}(
                pubkey,
                withdrawal_credentials,
                signature,
                deposit_data_roots[i]
            );
        }
    }

    /**
     * @dev Withdraw accumulated fee in the contract
     *
     * @param receiver The address where all accumulated funds will be transferred to.
     * Can only be called by the current owner.
     */
    function withdraw(address payable receiver) public onlyOwner {       
        require(receiver != address(0), "You can't burn these eth directly");

        uint256 amount = address(this).balance;
        emit Withdrawn(receiver, amount);
        receiver.transfer(amount);
    }

    /**
     * @dev Change the validator fee (`newOwner`).
     * Can only be called by the current owner.
     */
    function changeFee(uint256 newFee) public onlyOwner {
        require(newFee != _fee, "Fee must be different from current one");
        require(newFee % 1 gwei == 0, "Fee must be a multiple of GWEI");

        emit FeeChanged(_fee, newFee);
        _fee = newFee;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Returns the current fee
     */
    function fee() public view returns (uint256) {
        return _fee;
    }
  
    /**
     * Disable renunce ownership
     */
    function renounceOwnership() public override onlyOwner {
        revert("Ownable: renounceOwnership is disabled");
    }
}
