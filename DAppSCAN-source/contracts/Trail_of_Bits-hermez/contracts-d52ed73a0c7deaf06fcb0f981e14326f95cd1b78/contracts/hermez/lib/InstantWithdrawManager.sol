// SPDX-License-Identifier: AGPL-3.0

pragma solidity 0.6.12;

import "../interfaces/WithdrawalDelayerInterface.sol";
import "./HermezHelpers.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";

contract InstantWithdrawManager is HermezHelpers {
    using SafeMath for uint256;

    // every time a withdraw is performed, a withdrawal is wasted
    struct Bucket {
        uint256 ceilUSD; // max USD value
        uint256 blockStamp; // last time a withdrawal was added ( or removed if the bucket was full)
        uint256 withdrawals; // available withdrawals of the bucket
        uint256 blockWithdrawalRate; // every `blockWithdrawalRate` blocks add 1 withdrawal
        uint256 maxWithdrawals; // max withdrawals the bucket can hold
    }

    // Number of buckets
    uint256 private constant _NUM_BUCKETS = 5;
    // Bucket array
    Bucket[_NUM_BUCKETS] public buckets;

    // Governance address
    address public hermezGovernanceDAOAddress;

    // Safety address, in case something out of control happens can put Hermez in safe mode
    // wich means only delay withdrawals allowed
    address public safetyAddress;

    // Withdraw delay in seconds
    uint64 public withdrawalDelay;

    // ERC20 decimals signature
    //  bytes4(keccak256(bytes("decimals()")))
    bytes4 private constant _ERC20_DECIMALS = 0x313ce567;

    uint256 private constant _MAX_WITHDRAWAL_DELAY = 2 weeks;

    // Withdraw delayer interface
    WithdrawalDelayerInterface public withdrawDelayerContract;

    // Mapping tokenAddress --> (USD value)/token , default 0, means that token does not worth
    // 2^64 = 1.8446744e+19
    // fixed point codification is used, 5 digits for integer part, 14 digits for decimal
    // In other words, the USD value of a token base unit is multiplied by 1e14
    // MaxUSD value for a base unit token: 184467$
    // MinUSD value for a base unit token: 1e-14$
    mapping(address => uint64) public tokenExchange;

    uint256 private constant _EXCHANGE_MULTIPLIER = 1e14;

    function _initializeWithdraw(
        address _hermezGovernanceDAOAddress,
        address _safetyAddress,
        uint64 _withdrawalDelay,
        address _withdrawDelayerContract
    ) internal initializer {
        hermezGovernanceDAOAddress = _hermezGovernanceDAOAddress;
        safetyAddress = _safetyAddress;
        withdrawalDelay = _withdrawalDelay;
        withdrawDelayerContract = WithdrawalDelayerInterface(
            _withdrawDelayerContract
        );
    }

    modifier onlyGovernance {
        require(
            msg.sender == hermezGovernanceDAOAddress,
            "InstantWithdrawManager::onlyGovernance: ONLY_GOVERNANCE_ADDRESS"
        );
        _;
    }

    /**
     * @dev Attempt to use instant withdraw
     * @param tokenAddress Token address
     * @param amount Amount to withdraw
     */
    function _processInstantWithdrawal(address tokenAddress, uint192 amount)
        internal
        returns (bool)
    {
        // find amount in USD and then the corresponding bucketIdx
        uint256 amountUSD = _token2USD(tokenAddress, amount);

        if (amountUSD == 0) {
            return true;
        }

        // find the appropiate bucketId
        uint256 bucketIdx = _findBucketIdx(amountUSD);
        Bucket storage currentBucket = buckets[bucketIdx];

        // update the bucket and check again if are withdrawals available
        uint256 differenceBlocks = block.number.sub(currentBucket.blockStamp);

        // check if some withdrawal can be added
        if ((differenceBlocks < currentBucket.blockWithdrawalRate)) {
            if (currentBucket.withdrawals > 0) {
                // can't add any wihtdrawal, retrieve the current withdrawal
                if (currentBucket.withdrawals == currentBucket.maxWithdrawals) {
                    // if the bucket was full set the blockStamp to the current block number
                    currentBucket.blockStamp = block.number;
                }
                currentBucket.withdrawals--;
                return true;
            }
            // the bucket still empty, instant withdrawal can't be performed
            return false;
        } else {
            // add withdrawals
            uint256 addWithdrawals = differenceBlocks.div(
                currentBucket.blockWithdrawalRate
            );

            if (
                currentBucket.withdrawals.add(addWithdrawals) >=
                currentBucket.maxWithdrawals
            ) {
                // if the bucket is full, set to maxWithdrawals, and retrieve the current withdrawal
                // set the blockStamp to the current block number
                currentBucket.withdrawals = currentBucket.maxWithdrawals.sub(1);
                currentBucket.blockStamp = block.number;
            } else {
                // if the bucket is not filled, add the withdrawals minus the current one and update the blockstamp
                // blockstamp increments with a multiple of blockWithdrawalRate nearest and smaller than differenceBlocks
                // addWithdrawals is that multiple because solidity divisions always round to floor
                // this expression, can be reduced into currentBucket.blockStamp = block.number only if addWithdrawals is a multiple of blockWithdrawalRate
                currentBucket.withdrawals =
                    currentBucket.withdrawals +
                    addWithdrawals -
                    1;
                currentBucket.blockStamp = currentBucket.blockStamp.add(
                    (addWithdrawals.mul(currentBucket.blockWithdrawalRate))
                );
            }
            return true;
        }
    }

    /**
     * @dev Update bucket parameters
     * @param arrayBuckets Array of buckets to replace the current ones, this array includes the
     * following parameters: [ceilUSD, withdrawals, blockWithdrawalRate, maxWithdrawals]
     */
    function updateBucketsParameters(
        uint256[4][_NUM_BUCKETS] memory arrayBuckets
    ) external onlyGovernance {
        for (uint256 i = 0; i < _NUM_BUCKETS; i++) {
            uint256 ceilUSD = arrayBuckets[i][0];
            uint256 withdrawals = arrayBuckets[i][1];
            uint256 blockWithdrawalRate = arrayBuckets[i][2];
            uint256 maxWithdrawals = arrayBuckets[i][3];
            require(
                withdrawals <= maxWithdrawals,
                "InstantWithdrawManager::updateBucketsParameters: WITHDRAWALS_MUST_BE_LESS_THAN_MAXWITHDRAWALS"
            );
            buckets[i] = Bucket(
                ceilUSD,
                block.number,
                withdrawals,
                blockWithdrawalRate,
                maxWithdrawals
            );
        }
    }

    /**
     * @dev Update token USD value
     * @param addressArray Array of the token address
     * @param valueArray Array of USD values
     */
    function updateTokenExchange(
        address[] memory addressArray,
        uint64[] memory valueArray
    ) external onlyGovernance {
        require(
            addressArray.length == valueArray.length,
            "InstantWithdrawManager::updateTokenExchange: INVALID_ARRAY_LENGTH"
        );
        for (uint256 i = 0; i < addressArray.length; i++) {
            tokenExchange[addressArray[i]] = valueArray[i];
        }
    }

    /**
     * @dev Update WithdrawalDelay
     * @param newWithdrawalDelay New WithdrawalDelay
     * Events: `UpdateWithdrawalDelay`
     */
    function updateWithdrawalDelay(uint64 newWithdrawalDelay)
        external
        onlyGovernance
    {
        require(
            newWithdrawalDelay <= _MAX_WITHDRAWAL_DELAY,
            "InstantWithdrawManager::updateWithdrawalDelay: EXCEED_MAX_WITHDRAWAL_DELAY"
        );
        withdrawalDelay = newWithdrawalDelay;
    }

    /**
     * @dev Put the smartcontract in safe mode, only delayed withdrawals allowed,
     * also update the 'withdrawalDelay' of the 'withdrawDelayer' contract
     */
    function safeMode() external {
        require(
            (msg.sender == safetyAddress) ||
                (msg.sender == hermezGovernanceDAOAddress),
            "InstantWithdrawManager::safeMode: ONY_SAFETYADDRESS_OR_GOVERNANCE"
        );

        // all buckets to 0
        for (uint256 i = 0; i < _NUM_BUCKETS; i++) {
            buckets[i] = Bucket(0, 0, 0, 0, 0);
        }
        withdrawDelayerContract.changeWithdrawalDelay(withdrawalDelay);
    }

    /**
     * @dev Return true if a instant withdraw could be done with that 'tokenAddress' and 'amount'
     * @param tokenAddress Token address
     * @param amount Amount to withdraw
     * @return true if the instant withdrawal is allowed
     */
    function instantWithdrawalViewer(address tokenAddress, uint192 amount)
        public
        view
        returns (bool)
    {
        // find amount in USD and then the corresponding bucketIdx
        uint256 amountUSD = _token2USD(tokenAddress, amount);
        if (amountUSD == 0) return true;

        uint256 bucketIdx = _findBucketIdx(amountUSD);

        Bucket storage currentBucket = buckets[bucketIdx];
        if (currentBucket.withdrawals > 0) {
            return true;
        } else {
            uint256 differenceBlocks = block.number.sub(
                currentBucket.blockStamp
            );
            if (differenceBlocks < currentBucket.blockWithdrawalRate)
                return false;
            else return true;
        }
    }

    /**
     * @dev Converts tokens to USD
     * @param tokenAddress Token address
     * @param amount Token amount
     * @return Total USD amount
     */
    function _token2USD(address tokenAddress, uint192 amount)
        internal
        view
        returns (uint256)
    {
        if (tokenExchange[tokenAddress] == 0) return 0;

        // this multiplication never overflows 192bits * 64 bits
        uint256 baseUnitTokenUSD = (uint256(amount) *
            uint256(tokenExchange[tokenAddress])) / _EXCHANGE_MULTIPLIER;

        uint8 decimals;

        // if decimals() is not implemented 0 decimals are assumed
        (bool success, bytes memory data) = tokenAddress.staticcall(
            abi.encodeWithSelector(_ERC20_DECIMALS)
        );
        if (success) {
            decimals = abi.decode(data, (uint8));
        }

        require(
            decimals < 77,
            "InstantWithdrawManager::_token2USD: TOKEN_DECIMALS_OVERFLOW"
        );
        return baseUnitTokenUSD / (10**uint256(decimals));
    }

    /**
     * @dev Find the corresponding bucket for the input amount
     * @param amountUSD USD amount
     * @return Bucket index
     */
    function _findBucketIdx(uint256 amountUSD) internal view returns (uint256) {
        for (uint256 i = 0; i < _NUM_BUCKETS; i++) {
            if (amountUSD <= buckets[i].ceilUSD) {
                return i;
            }
        }
        revert("InstantWithdrawManager::_findBucketIdx: EXCEED_MAX_AMOUNT");
    }
}
