pragma solidity ^0.4.24;

import "../../contracts/openzeppelin-solidity/contracts/math/SafeMath.sol";
import "../../contracts/openzeppelin-solidity/contracts/ECRecovery.sol";
import "../../contracts/openzeppelin-solidity/contracts/token/ERC20/StandardToken.sol";
import "../../contracts/2key/libraries/GetCode.sol";

contract IERC20 {
    function balanceOf(address who) public view returns (uint256);
    function transfer(address to, uint256 value) public returns (bool);
    function allowance(address owner, address spender) public view returns (uint256);
    function transferFrom(address from, address to, uint256 value) public returns (bool);
    function approve(address spender, uint256 value) public returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}


contract Enigma {
    using SafeMath for uint256;
    using ECRecovery for bytes32;

    // The interface of the deployed ENG ERC20 token contract
    IERC20 public engToken;

    // The data representation of a computation task
    struct Task {
        address dappContract;
        TaskStatus status;
        string callable;
        bytes callableArgs;
        string callback;
        address worker;
        bytes sig;
        uint256 reward;
        uint256 blockNumber;
    }
    enum TaskStatus {InProgress, Executed}

    enum ReturnValue {Ok, Error}

    /**
    * The signer address of the principal node
    * This must be set when deploying the contract and remains immutable
    * Since the signer address is derived from the public key of an
    * SGX enclave, this ensures that the principal node cannot be tempered
    * with or replaced.
    */
    address principal;

    // The data representation of a worker (or node)
    struct Worker {
        address signer;
        uint8 status; // Uninitialized: 0; Active: 1; Inactive: 2
        bytes report; // Decided to store this as one  RLP encoded attribute for easier external storage in the future
        uint256 balance;
    }

    /**
    * The data representation of the worker parameters used as input for
    * the worker selection algorithm
    */
    struct WorkersParams {
        uint256 firstBlockNumber;
        address[] workerAddresses;
        uint256 seed;
    }

    /**
    * The last 5 worker parameters
    * We keep a collection of worker parameters to account for latency issues.
    * A computation task might be conceivably given out at a certain block number
    * but executed at a later block in a different epoch. It follows that
    * the contract must have access to the worker parameters effective when giving
    * out the task, otherwise the selected worker would not match. We calculated
    * that keeping the last 5 items should be more than enough to account for
    * all latent tasks. Tasks results will be rejected past this limit.
    */
    WorkersParams[5] workersParams;

    // An address-based index of all registered worker
    address[] public workerAddresses;

    // A registry of all registered workers with their attributes
    mapping(address => Worker) public workers;
    // A registry of all active and historical tasks with their attributes
    // TODO: do we keep tasks forever? if not, when do we delete them?
    mapping(bytes32 => Task) public tasks;

    // The events emitted by the contract
    event Register(address custodian, address signer, bool _success);
    event ValidatedSig(bytes sig, bytes32 hash, address workerAddr, bool _success);
    event CommitResults(address dappContract, address worker, bytes sig, uint reward, bool _success);
    event WorkersParameterized(uint256 seed, address[] workers, bool _success);
    event ComputeTask(
        address indexed dappContract,
        bytes32 indexed taskId,
        string callable,
        bytes callableArgs,
        string callback,
        uint256 fee,
        bytes32[] preprocessors,
        uint256 blockNumber,
        bool _success
    );

    constructor(address _tokenAddress, address _principal) public {
        engToken = IERC20(_tokenAddress);
        principal = _principal;
    }

    /**
    * Checks if the custodian wallet is registered as a worker
    *
    * @param user The custodian address of the worker
    */
    modifier workerRegistered(address user) {
        Worker memory worker = workers[user];
        require(worker.status > 0, "Unregistered worker.");
        _;
    }

    /**
    * Registers a new worker of change the signer parameters of an existing
    * worker. This should be called by every worker (and the principal)
    * node in order to receive tasks.
    *
    * @param signer The signer address, derived from the enclave public key
    * @param report The RLP encoded report returned by the IAS
    */
    function register(address signer, bytes report)
        public
        payable
        returns (ReturnValue)
    {
        // TODO: consider exit if both signer and custodian as matching
        // If the custodian is not already register, we add an index entry
        if (workers[msg.sender].signer == 0x0) {
            uint index = workerAddresses.length;
            workerAddresses.length++;
            workerAddresses[index] = msg.sender;
        }

        // Set the custodian attributes
        workers[msg.sender].signer = signer;
        workers[msg.sender].balance = msg.value;
        workers[msg.sender].report = report;
        workers[msg.sender].status = 1;

        emit Register(msg.sender, signer, true);

        return ReturnValue.Ok;
    }

    /**
    * Generates a unique task id
    *
    * @param dappContract The address of the deployed contract containing the callable method
    * @param callable The signature (as defined by the Ethereum ABI) of the function to compute
    * @param callableArgs The RLP serialized arguments of the callable function
    * @param blockNumber The current block number
    * @return The task id
    */
    function generateTaskId(address dappContract, string callable, bytes callableArgs, uint256 blockNumber)
        public
        pure
        returns (bytes32)
    {
        bytes32 hash = keccak256(abi.encodePacked(dappContract, callable, callableArgs, blockNumber));
        return hash;
    }

    /**
    * Give out a computation task to the network
    *
    * @param dappContract The address of the deployed contract containing the callable method
    * @param callable The signature (as defined by the Ethereum ABI) of the function to compute
    * @param callableArgs The RLP serialized arguments of the callable function
    * @param callback The signature of the function to call back with the results
    * @param fee The computation fee in ENG
    * @param preprocessors A list of preprocessors to run and inject as argument of callable
    * @param blockNumber The current block number
    */
    function compute(
        address dappContract,
        string callable,
        bytes callableArgs,
        string callback,
        uint256 fee,
        bytes32[] preprocessors,
        uint256 blockNumber
    )
        public
        returns (ReturnValue)
    {
        // TODO: Add a multiplier to the fee (like ETH => wei) in order to accept smaller denominations
        bytes32 taskId = generateTaskId(dappContract, callable, callableArgs, blockNumber);
        require(tasks[taskId].dappContract == 0x0, "Task with the same taskId already exist");

        tasks[taskId].reward = fee;
        tasks[taskId].callable = callable;
        tasks[taskId].callableArgs = callableArgs;
        tasks[taskId].callback = callback;
        tasks[taskId].status = TaskStatus.InProgress;
        tasks[taskId].dappContract = dappContract;
        tasks[taskId].blockNumber = blockNumber;

        // Emit the ComputeTask event which each node is watching for
        emit ComputeTask(
            dappContract,
            taskId,
            callable,
            callableArgs,
            callback,
            fee,
            preprocessors,
            blockNumber,
            true
        );

        // Transferring before emitting does not work
        // TODO: check the allowance first
        engToken.transferFrom(msg.sender, this, fee);

        return ReturnValue.Ok;
    }

    // Verify the task results signature
    function verifyCommitSig(Task task, bytes data, bytes sig)
        internal
        returns (address)
    {
        // Recreating a data hash to validate the signature
        bytes memory code = GetCode.at(task.dappContract);

        // Build a hash to validate that the I/Os are matching
        bytes32 hash = keccak256(abi.encodePacked(task.callableArgs, data, code));

        // The worker address is not a real Ethereum wallet address but
        // one generated from its signing key
        address workerAddr = hash.recover(sig);

        emit ValidatedSig(sig, hash, workerAddr, true);
        return workerAddr;
    }

    // Execute the encoded function in the specified contract
    function executeCall(address to, uint256 value, bytes data)
        internal
        returns (bool success)
    {
        assembly {
            success := call(gas, to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    /**
    * Commit the computation task results on chain
    *
    * @param taskId The reference task id
    * @param data The encoded callback function call (which includes the computation results)
    * @param sig The data signed by the the worker's enclave
    * @param blockNumber The block number which originated the task
    */
    function commitResults(bytes32 taskId, bytes data, bytes sig, uint256 blockNumber)
        public
        workerRegistered(msg.sender)
        returns (ReturnValue)
    {
        // Task must be solved only once
        require(tasks[taskId].status == TaskStatus.InProgress, "Illegal status, task must be in progress.");
        // TODO: run worker selection algo to validate right worker
        require(block.number > blockNumber, "Block number in the future.");

        address sigAddr = verifyCommitSig(tasks[taskId], data, sig);
        require(sigAddr != address(0), "Cannot verify this signature.");
        require(sigAddr == workers[msg.sender].signer, "Invalid signature.");

        // The contract must hold enough fund to distribute reward
        // TODO: validate that the reward matches the opcodes computed
        uint256 reward = tasks[taskId].reward;
        require(reward > 0, "Reward cannot be zero.");

        // Invoking the callback method of the original contract
        require(executeCall(tasks[taskId].dappContract, 0, data), "Unable to invoke the callback");

        // Keep a trace of the task worker and proof
        tasks[taskId].worker = msg.sender;
        tasks[taskId].sig = sig;
        tasks[taskId].status = TaskStatus.Executed;

        // TODO: send directly to the worker's custodian instead
        // Put the reward in the worker's bank
        // He can withdraw later
        Worker storage worker = workers[msg.sender];
        worker.balance = worker.balance.add(reward);

        emit CommitResults(tasks[taskId].dappContract, sigAddr, sig, reward, true);

        return ReturnValue.Ok;
    }

    // Verify the signature submitted while reparameterizing workers
    function verifyParamsSig(uint256 seed, bytes sig)
        internal
        pure
        returns (address)
    {
        bytes32 hash = keccak256(abi.encodePacked(seed));
        address signer = hash.recover(sig);
        return signer;
    }

    /**
    * Reparameterizing workers with a new seed
    * This should be called for each epoch by the Principal node
    *
    * @param seed The random integer generated by the enclave
    * @param sig The random integer signed by the the principal node's enclave
    */
    function setWorkersParams(uint256 seed, bytes sig)
        public
        workerRegistered(msg.sender)
        returns (ReturnValue)
    {
        require(workers[msg.sender].signer == principal, "Only the Principal can update the seed");

        address sigAddr = verifyParamsSig(seed, sig);
        require(sigAddr == principal, "Invalid signature");

        // Create a new workers parameters item for the specified seed.
        // The workers parameters list is a sort of cache, it never grows beyond its limit.
        // If the list is full, the new item will replace the item assigned to the lowest block number.
        uint ti = 0;
        for (uint pi = 0; pi < workersParams.length; pi++) {
            // Find an empty slot in the array, if full use the lowest block number
            if (workersParams[pi].firstBlockNumber == 0) {
                ti = pi;
                break;
            } else if (workersParams[pi].firstBlockNumber < workersParams[ti].firstBlockNumber) {
                ti = pi;
            }
        }
        workersParams[ti].firstBlockNumber = block.number;
        workersParams[ti].seed = seed;

        // Copy the current worker list
        for (uint wi = 0; wi < workerAddresses.length; wi++) {
            if (workerAddresses[wi] != 0x0) {
                workersParams[ti].workerAddresses.length++;
                workersParams[ti].workerAddresses[wi] = workerAddresses[wi];
            }
        }
        emit WorkersParameterized(seed, workerAddresses, true);
        return ReturnValue.Ok;
    }

    // The workers parameters nearest the specified block number
    function getWorkersParamsIndex(uint256 blockNumber)
        internal
        view
        returns (int8)
    {
        int8 ci = - 1;
        for (uint i = 0; i < workersParams.length; i++) {
            if (workersParams[i].firstBlockNumber <= blockNumber && (ci == - 1 || workersParams[i].firstBlockNumber > workersParams[uint(ci)].firstBlockNumber)) {
                ci = int8(i);
            }
        }
        return ci;
    }

    /**
    * The worker parameters corresponding to the specified block number
    *
    * @param blockNumber The reference block number
    */
    function getWorkersParams(uint256 blockNumber)
        public
        view
        returns (uint256, uint256, address[])
    {
        // The workers parameters for a given block number
        int8 idx = getWorkersParamsIndex(blockNumber);
        require(idx != - 1, "No workers parameters entry for specified block number");

        uint index = uint(idx);
        WorkersParams memory _workerParams = workersParams[index];
        address[] memory addrs = filterWorkers(_workerParams.workerAddresses);

        return (_workerParams.firstBlockNumber, _workerParams.seed, addrs);
    }

    // Filter out bad values from a list of worker addresses
    function filterWorkers(address[] addrs)
        internal
        view
        returns (address[])
    {
        // TODO: I don't know why the list contains empty addresses, investigate
        uint cpt = 0;
        for (uint i = 0; i < addrs.length; i++) {
            if (addrs[i] != 0x0 && workers[addrs[i]].signer != principal) {
                cpt++;
            }
        }
        address[] memory _workers = new address[](cpt);
        uint cur = 0;
        for (uint iw = 0; iw < addrs.length; iw++) {
            if (addrs[iw] != 0x0 && workers[addrs[iw]].signer != principal) {
                _workers[cur] = addrs[iw];
                cur++;
            }
        }
        return _workers;
    }

    /**
    * Apply pseudo-randomness to discover the selected worker for the specified task
    *
    * @param blockNumber The reference block number
    * @param taskId The reference task id
    */
    function selectWorker(uint256 blockNumber, bytes32 taskId)
        public
        view
        returns (address)
    {
        (uint256 b, uint256 seed, address[] memory workerArray) = getWorkersParams(blockNumber);
        address[] memory _workers = filterWorkers(workerArray);

        bytes32 hash = keccak256(abi.encodePacked(seed, taskId));
        uint256 index = uint256(hash) % _workers.length;
        return _workers[index];
    }

    /**
    * The RLP encoded report returned by the IAS server
    *
    * @param custodian The worker's custodian address
    */
    function getReport(address custodian)
        public
        view
        workerRegistered(custodian)
        returns (address, bytes)
    {
        // The RLP encoded report and signer's address for the specified worker
        require(workers[custodian].signer != 0x0, "Worker not registered");
        return (workers[custodian].signer, workers[custodian].report);
    }
}
