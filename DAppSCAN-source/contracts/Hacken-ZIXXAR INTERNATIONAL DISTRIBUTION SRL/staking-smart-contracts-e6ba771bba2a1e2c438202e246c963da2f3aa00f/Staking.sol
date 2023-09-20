// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;
//SWC-103-Floating Pragma: L2
/// @title The Staking Contract for XIDEN (XID) PoS Network
/// @author Polygon-Edge TEAM and CryptoDATA TEAM (5381)
/// @notice The Xiden network requires Node validators to stake 2 Million XID
//
//   ██╗  ██╗██╗██████╗ ███████╗███╗   ██╗    ███████╗████████╗ █████╗ ██╗  ██╗██╗███╗   ██╗ ██████╗
//   ╚██╗██╔╝██║██╔══██╗██╔════╝████╗  ██║    ██╔════╝╚══██╔══╝██╔══██╗██║ ██╔╝██║████╗  ██║██╔════╝
//    ╚███╔╝ ██║██║  ██║█████╗  ██╔██╗ ██║    ███████╗   ██║   ███████║█████╔╝ ██║██╔██╗ ██║██║  ███╗
//    ██╔██╗ ██║██║  ██║██╔══╝  ██║╚██╗██║    ╚════██║   ██║   ██╔══██║██╔═██╗ ██║██║╚██╗██║██║   ██║
//   ██╔╝ ██╗██║██████╔╝███████╗██║ ╚████║    ███████║   ██║   ██║  ██║██║  ██╗██║██║ ╚████║╚██████╔╝
//   ╚═╝  ╚═╝╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝    ╚══════╝   ╚═╝   ╚═╝  ╚═╝╚═╝  ╚═╝╚═╝╚═╝  ╚═══╝ ╚═════╝

contract Staking {
    uint128 private constant VALIDATOR_THRESHOLD = 2e6 * 10**18;
    uint32 private constant MINIMUM_REQUIRED_NUM_VALIDATORS = 4;

    // Properties
    address[] public _validators;
    mapping(address => bool) _addressToIsValidator;
    mapping(address => uint256) _addressToStakedAmount;
    mapping(address => uint256) _addressToValidatorIndex;
    uint256 private _stakedAmount;
    mapping(address => address) private _delegatedStaker;

    // Events
    event Staked(address indexed account, uint256 amount);
    event Unstaked(address indexed account, uint256 amount);

    // Please no steal
    modifier onlyStaker(address _validatorNode) {
        require(
            _delegatedStaker[_validatorNode] == msg.sender,
            "Only staker can call function"
        );
        _;
    }

    constructor() {}

    function stakedAmount() external view returns (uint256) {
        return _stakedAmount;
    }

    function validators() external view returns (address[] memory) {
        return _validators;
    }

    function isValidator(address addr) external view returns (bool) {
        return _addressToIsValidator[addr];
    }

    function accountStake(address addr) external view returns (uint256) {
        return _addressToStakedAmount[addr];
    }

    // Public functions
    receive() external payable {
        _stake(msg.sender);
    }

    function stake(address _validatorNode) external payable returns (bool) {
        require(
            msg.value >= VALIDATOR_THRESHOLD,
            "You need more funds in order to stake!"
        );
        _stake(_validatorNode);
        return true;
    }

    function unstake(address _validatorNode)
        external
        onlyStaker(_validatorNode)
    {
        _unstake(_validatorNode);
    }

    // Private functions
    function _stake(address _validatorNode) private {
        _stakedAmount += msg.value;
        _addressToStakedAmount[_validatorNode] += msg.value;

        if (
            !_addressToIsValidator[_validatorNode] &&
            _addressToStakedAmount[_validatorNode] >= VALIDATOR_THRESHOLD
        ) {
            // append to validator set
            _addressToIsValidator[_validatorNode] = true;
            _addressToValidatorIndex[_validatorNode] = _validators.length;
            _delegatedStaker[_validatorNode] = msg.sender;
            _validators.push(_validatorNode);
        }

        emit Staked(_validatorNode, msg.value);
    }

    function _unstake(address _validatorNode) private {
        require(
            _validators.length > MINIMUM_REQUIRED_NUM_VALIDATORS,
            "Number of validators can't be less than MINIMUM_REQUIRED_NUM_VALIDATORS"
        );

        uint256 amount = _addressToStakedAmount[_validatorNode];
        address delegator = _delegatedStaker[_validatorNode];
        if (_addressToIsValidator[_validatorNode]) {
            _deleteFromValidators(_validatorNode);
        }

        _stakedAmount -= amount;
        _addressToStakedAmount[_validatorNode] = 0;
        delete _delegatedStaker[_validatorNode];

        emit Unstaked(_validatorNode, amount);
        payable(delegator).transfer(amount);
    }

    function _deleteFromValidators(address staker) private {
        require(
            _addressToValidatorIndex[staker] < _validators.length,
            "index out of range"
        );

        // index of removed address
        uint256 index = _addressToValidatorIndex[staker];
        uint256 lastIndex = _validators.length - 1;

        if (index != lastIndex) {
            // exchange between the element and last to pop for delete
            address lastAddr = _validators[lastIndex];
            _validators[index] = lastAddr;
            _addressToValidatorIndex[lastAddr] = index;
        }

        _addressToIsValidator[staker] = false;
        _addressToValidatorIndex[staker] = 0;
        _validators.pop();
    }
}
