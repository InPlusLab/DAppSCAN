// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../interfaces/IRelayEncoder.sol";
import "../interfaces/IxTokens.sol";
import "../interfaces/IXcmTransactor.sol";
import "../interfaces/ILedger.sol";



contract Controller {
    // ledger controller account
    uint16 public rootDerivativeIndex;

    // relay side account id
    bytes32 public relayAccount;

    // vKSM precompile
    IERC20 internal vKSM;

    // relay call builder precompile
    IRelayEncoder internal relayEncoder;

    // xcm transactor precompile
    IXcmTransactor internal xcmTransactor;

    // xTokens precompile
    IxTokens internal xTokens;

    // Second layer derivative-proxy account to index
    mapping(address => uint16) public senderToIndex;
    mapping(uint16 => bytes32) public indexToAccount;

    uint16 public tododelete;

    enum WEIGHT {
        AS_DERIVATIVE,              // 410_000_000
        BOND_BASE,                  // 600_000_000
        BOND_EXTRA_BASE,            // 1_100_000_000
        UNBOND_BASE,                // 1_250_000_000
        WITHDRAW_UNBONDED_BASE,     // 500_000_000
        WITHDRAW_UNBONDED_PER_UNIT, // 60_000
        REBOND_BASE,                // 1_200_000_000
        REBOND_PER_UNIT,            // 40_000
        CHILL_BASE,                 // 900_000_000
        NOMINATE_BASE,              // 1_000_000_000
        NOMINATE_PER_UNIT,          // 31_000_000
        TRANSFER_TO_PARA_BASE,      // 700_000_000
        TRANSFER_TO_RELAY_BASE      // 4_000_000_000
    }

    uint64 public MAX_WEIGHT;// = 1_835_300_000;

    uint64[] public weights;

    event WeightUpdated (
        uint8 index,
        uint64 newValue
    );

    event Bond (
        address caller,
        bytes32 stash,
        bytes32 controller,
        uint256 amount
    );

    event BondExtra (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    event Unbond (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    event Rebond (
        address caller,
        bytes32 stash,
        uint256 amount
    );

    event Withdraw (
        address caller,
        bytes32 stash
    );

    event Nominate (
        address caller,
        bytes32 stash,
        bytes32[] validators
    );

    event Chill (
        address caller,
        bytes32 stash
    );

    event TransferToRelaychain (
        address from,
        bytes32 to,
        uint256 amount
    );

    event TransferToParachain (
        bytes32 from,
        address to,
        uint256 amount
    );


    modifier onlyRegistred() {
        require(senderToIndex[msg.sender] != 0, "sender isn't registred");
        _;
    }

    function initialize() external {} //stub

    /**
    * @notice Initialize ledger contract.
    * @param _rootDerivativeIndex - stash account id
    * @param _relayAccount - controller account id
    * @param _vKSM - vKSM contract address
    * @param _relayEncoder - relayEncoder(relaychain calls builder) contract address
    * @param _xcmTransactor - xcmTransactor(relaychain calls relayer) contract address
    * @param _xTokens - minimal allowed nominator balance
    */
    function init(
        uint16 _rootDerivativeIndex,
        bytes32 _relayAccount,
        address _vKSM,
        address _relayEncoder,
        address _xcmTransactor,
        address _xTokens
    ) external {
        relayAccount = _relayAccount;
        rootDerivativeIndex = _rootDerivativeIndex;

        vKSM = IERC20(_vKSM);
        relayEncoder = IRelayEncoder(_relayEncoder);
        xcmTransactor = IXcmTransactor(_xcmTransactor);
        xTokens = IxTokens(_xTokens);
    }


    function getWeight(WEIGHT weightType) public returns(uint64) {
        return weights[uint256(weightType)];
    }


    function setMaxWeight(uint64 maxWeight) external {
        MAX_WEIGHT = maxWeight;
    }

    function setWeights(
        uint128[] calldata _weights
    ) external {
        require(_weights.length == uint256(type(WEIGHT).max) + 1, "wrong weights size");
        for (uint256 i = 0; i < _weights.length; ++i) {
            if ((_weights[i] >> 64) > 0) {
                if (weights.length == i) {
                    weights.push(0);
                }

                weights[i] = uint64(_weights[i]);
                emit WeightUpdated(uint8(i), weights[i]);
            }
        }
    }


    function newSubAccount(uint16 index, bytes32 accountId, address paraAddress) external {
        require(indexToAccount[index + 1] == bytes32(0), "already registred");

        senderToIndex[paraAddress] = index + 1;
        indexToAccount[index + 1] = accountId;
    }


    function nominate(bytes32[] calldata validators) external onlyRegistred {
        uint256[] memory convertedValidators = new uint256[](validators.length);
        for (uint256 i = 0; i < validators.length; ++i) {
            convertedValidators[i] = uint256(validators[i]);
        }
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.NOMINATE_BASE) + getWeight(WEIGHT.NOMINATE_PER_UNIT) * uint64(validators.length),
            relayEncoder.encode_nominate(convertedValidators)
        );

        emit Nominate(msg.sender, getSenderAccount(), validators);
    }

    function bond(bytes32 controller, uint256 amount) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.BOND_BASE),
            relayEncoder.encode_bond(uint256(controller), amount, bytes(hex"00"))
        );

        emit Bond(msg.sender, getSenderAccount(), controller, amount);
    }

    function bondExtra(uint256 amount) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.BOND_EXTRA_BASE),
            relayEncoder.encode_bond_extra(amount)
        );

        emit BondExtra(msg.sender, getSenderAccount(), amount);
    }

    function unbond(uint256 amount) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.UNBOND_BASE),
            relayEncoder.encode_unbond(amount)
        );

        emit Unbond(msg.sender, getSenderAccount(), amount);
    }

    function withdrawUnbonded() external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.WITHDRAW_UNBONDED_BASE) + getWeight(WEIGHT.WITHDRAW_UNBONDED_PER_UNIT) * 10,
            relayEncoder.encode_withdraw_unbonded(10/* TODO fix*/)
        );

        emit Withdraw(msg.sender, getSenderAccount());
    }

    function rebond(uint256 amount) external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.REBOND_BASE) + getWeight(WEIGHT.REBOND_PER_UNIT) * 10 /*TODO fix*/,
            relayEncoder.encode_rebond(amount)
        );

        emit Rebond(msg.sender, getSenderAccount(), amount);
    }

    function chill() external onlyRegistred {
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.CHILL_BASE),
            relayEncoder.encode_chill()
        );

        emit Chill(msg.sender, getSenderAccount());
    }

    function transferToParachain(uint256 amount) external onlyRegistred {
        // to - msg.sender, from - getSenderIndex()
        callThroughDerivative(
            getSenderIndex(),
            getWeight(WEIGHT.TRANSFER_TO_PARA_BASE),
            encodeReverseTransfer(msg.sender, amount)
        );

        emit TransferToParachain(getSenderAccount(), msg.sender, amount);
    }

    function transferToRelaychain(uint256 amount) external onlyRegistred {
        // to - getSenderIndex(), from - msg.sender
        vKSM.transferFrom(msg.sender, address(this), amount);
        IxTokens.Multilocation memory destination;
        destination.parents = 1;
        destination.interior = new bytes[](1);
        destination.interior[0] = bytes.concat(bytes1(hex"01"), getSenderAccount(), bytes1(hex"00")); // X2, NetworkId: Any
        xTokens.transfer(address(vKSM), amount + 18900000000, destination, getWeight(WEIGHT.TRANSFER_TO_RELAY_BASE));

        emit TransferToRelaychain(msg.sender, getSenderAccount(), amount);
    }


    function getSenderIndex() internal returns(uint16) {
        return senderToIndex[msg.sender] - 1;
    }

    function getSenderAccount() internal returns(bytes32) {
        return indexToAccount[senderToIndex[msg.sender]];
    }

    function callThroughDerivative(uint16 index, uint64 weight, bytes memory call) internal {
        bytes memory le_index = new bytes(2);
        le_index[0] = bytes1(uint8(index));
        le_index[1] = bytes1(uint8(index >> 8));

        uint64 total_weight = weight + getWeight(WEIGHT.AS_DERIVATIVE);
        require(total_weight <= MAX_WEIGHT, "too much weight");

        xcmTransactor.transact_through_derivative(0, rootDerivativeIndex, address(vKSM),
            total_weight,
            bytes.concat(hex"1001", le_index, call)
        );
    }

    function encodeReverseTransfer(address to, uint256 amount) internal returns(bytes memory) {
        return bytes.concat(
            hex"630201000100a10f0100010300",
            abi.encodePacked(to),
            hex"010400000000",
            scaleCompactUint(amount),
            hex"00000000"
        );
    }

    function toLeBytes(uint256 value, uint256 len) internal returns(bytes memory) {
        bytes memory out = new bytes(len);
        for (uint256 idx = 0; idx < len; ++idx) {
            out[idx] = bytes1(uint8(value));
            value = value >> 8;
        }
        return out;
    }

    function scaleCompactUint(uint256 value) internal returns(bytes memory) {
        if (value < 1<<6) {
            return toLeBytes(value << 2, 1);
        }
        else if(value < 1 << 14) {
            return toLeBytes((value << 2) + 1, 2);
        }
        else if(value < 1 << 30) {
            return toLeBytes((value << 2) + 2, 4);
        }
        else {
            uint256 numBytes = 0;
            {
                uint256 m = value;
                for (; numBytes < 256 && m != 0; ++numBytes) {
                    m = m >> 8;
                }
            }

            bytes memory out = new bytes(numBytes + 1);
            out[0] = bytes1(uint8(((numBytes - 4) << 2) + 3));
            for (uint256 i = 0; i < numBytes; ++i) {
                out[i + 1] = bytes1(uint8(value & 0xFF));
                value = value >> 8;
            }
            return out;
        }
    }
}
