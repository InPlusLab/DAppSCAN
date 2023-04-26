// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC1820Registry.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/Initializable.sol";

contract WithdrawalDelayerTest is ReentrancyGuard, Initializable {
    address public hermezRollupAddress;

    bytes4 private constant _TRANSFERFROM_SIGNATURE = bytes4(
        keccak256(bytes("transferFrom(address,address,uint256)"))
    );

    event Deposit(
        address indexed owner,
        address indexed token,
        uint192 amount,
        uint64 depositTimestamp
    );

    struct DepositState {
        uint192 amount;
        uint64 depositTimestamp;
    }
    mapping(bytes32 => DepositState) public deposits;

    function withdrawalDelayerInitializer(
        uint64 _initialWithdrawalDelay,
        address _initialHermezRollup,
        address _initialHermezKeeperAddress,
        address _initialHermezGovernanceDAOAddress,
        address payable _initialWhiteHackGroupAddress
    ) public initializer {
        hermezRollupAddress = _initialHermezRollup;
    }

    /**
     * Function to make a deposit in the WithdrawalDelayer smartcontract, only the Hermez rollup smartcontract can do it
     * @dev In case of an Ether deposit, the address `0x0` will be used and the corresponding amount must be sent in the
     * `msg.value`. In case of an ERC20 this smartcontract must have the approval to expend the token to
     * deposit to be able to make a transferFrom to itself.
     * @param _owner is who can claim the deposit once the withdrawal delay time has been exceeded
     * @param _token address of the token deposited (`0x0` in case of Ether)
     * @param _amount deposit amount
     * Events: `Deposit`
     */
    function deposit(
        address _owner,
        address _token,
        uint192 _amount
    ) external payable nonReentrant {
        require(
            msg.sender == hermezRollupAddress,
            "WithdrawalDelayer::deposit: ONLY_ROLLUP"
        );
        if (msg.value != 0) {
            require(
                _token == address(0x0),
                "WithdrawalDelayer::deposit: WRONG_TOKEN_ADDRESS"
            );
            require(
                _amount == msg.value,
                "WithdrawalDelayer::deposit: WRONG_AMOUNT"
            );
        } else {
            require(
                IERC20(_token).allowance(hermezRollupAddress, address(this)) >=
                    _amount,
                "WithdrawalDelayer::deposit: NOT_ENOUGH_ALLOWANCE"
            );
            /* solhint-disable avoid-low-level-calls */
            (bool success, bytes memory data) = address(_token).call(
                abi.encodeWithSelector(
                    _TRANSFERFROM_SIGNATURE,
                    hermezRollupAddress,
                    address(this),
                    _amount
                )
            );
            // `transferFrom` method may return (bool) or nothing.
            require(
                success && (data.length == 0 || abi.decode(data, (bool))),
                "WithdrawalDelayer::deposit: TOKEN_TRANSFER_FAILED"
            );
        }
        _processDeposit(_owner, _token, _amount);
    }

    /**
     * @notice Internal call to make a deposit
     * @param _owner is who can claim the deposit once the withdrawal delay time has been exceeded
     * @param _token address of the token deposited (`0x0` in case of Ether)
     * @param _amount deposit amount
     * Events: `Deposit`
     */
    function _processDeposit(
        address _owner,
        address _token,
        uint192 _amount
    ) internal {
        // We identify a deposit with the keccak of its owner and the token
        bytes32 depositId = keccak256(abi.encodePacked(_owner, _token));
        uint192 newAmount = deposits[depositId].amount + _amount;
        require(
            newAmount >= deposits[depositId].amount,
            "WithdrawalDelayer::_processDeposit: DEPOSIT_OVERFLOW"
        );

        deposits[depositId].amount = newAmount;
        deposits[depositId].depositTimestamp = uint64(now);

        emit Deposit(
            _owner,
            _token,
            _amount,
            deposits[depositId].depositTimestamp
        );
    }

    /**
     * @notice This function allows the HermezKeeperAddress to change the withdrawal delay time, this is the time that
     * anyone needs to wait until a withdrawal of the funds is allowed. Since this time is calculated at the time of
     * withdrawal, this change affects existing deposits. Can never exceed `MAX_WITHDRAWAL_DELAY`
     * @dev It changes `_withdrawalDelay` if `_newWithdrawalDelay` it is less than or equal to MAX_WITHDRAWAL_DELAY
     * @param _newWithdrawalDelay new delay time in seconds
     * Events: `NewWithdrawalDelay` event.
     */
    function changeWithdrawalDelay(uint64 _newWithdrawalDelay) external {}
}
