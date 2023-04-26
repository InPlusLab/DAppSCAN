pragma solidity ^0.4.24;

import './RobotLiability.sol';
import './DutchAuction.sol';
import './Lighthouse.sol';
import './XRT.sol';

import 'ens/contracts/ENS.sol';
import 'ens/contracts/ENSRegistry.sol';
import 'ens/contracts/PublicResolver.sol';

contract LiabilityFactory {
    constructor(
        address _robot_liability_lib,
        address _lighthouse_lib,
        DutchAuction _auction,
        XRT _xrt,
        ENS _ens
    ) public {
        robotLiabilityLib = _robot_liability_lib;
        lighthouseLib = _lighthouse_lib;
        auction = _auction;
        xrt = _xrt;
        ens = _ens;
    }

    /**
     * @dev New liability created 
     */
    event NewLiability(address indexed liability);

    /**
     * @dev New lighthouse created
     */
    event NewLighthouse(address indexed lighthouse, string name);

    /**
     * @dev Robonomics dutch auction contract
     */
    DutchAuction public auction;

    /**
     * @dev Robonomics network protocol token
     */
    XRT public xrt;

    /**
     * @dev Ethereum name system
     */
    ENS public ens;

    /**
     * @dev Total GAS utilized by Robonomics network
     */
    uint256 public totalGasUtilizing = 0;

    /**
     * @dev GAS utilized by liability contracts
     */
    mapping(address => uint256) public gasUtilizing;

    /**
     * @dev The count of utilized gas for switch to next epoch 
     */
    uint256 public constant gasEpoch = 347 * 10**10;

    /**
     * @dev Weighted average gasprice
     */
    uint256 public constant gasPrice = 10 * 10**9;

    /**
     * @dev Used market orders accounting
     */
    mapping(bytes32 => bool) public usedHash;

    /**
     * @dev Lighthouse accounting
     */
    mapping(address => bool) public isLighthouse;

    /**
     * @dev Robot liability shared code smart contract
     */
    address public robotLiabilityLib;

    /**
     * @dev Lightouse shared code smart contract
     */
    address public lighthouseLib;

    /**
     * @dev XRT emission value for utilized gas
     */
    function wnFromGas(uint256 _gas) public view returns (uint256) {
        // Current gas utilization epoch
        uint256 epoch = totalGasUtilizing / gasEpoch;

        // XRT emission with addition coefficient by gas utilzation epoch
        uint256 wn = _gas * gasPrice * 2**epoch / 3**epoch / auction.finalPrice();

        // Check to not permit emission decrease below wn=gas
        return wn < _gas ? _gas : wn;
    }

    /**
     * @dev Only lighthouse guard
     */
    modifier onlyLighthouse {
        require(isLighthouse[msg.sender]);
        _;
    }

    /**
     * @dev Parameter can be used only once
     * @param _hash Single usage hash
     */
    function usedHashGuard(bytes32 _hash) internal {
        require(!usedHash[_hash]);
        usedHash[_hash] = true;
    }

    /**
     * @dev Create robot liability smart contract
     * @param _ask ABI-encoded ASK order message 
     * @param _bid ABI-encoded BID order message 
     */
    function createLiability(
        bytes _ask,
        bytes _bid
    )
        external 
        onlyLighthouse
        returns (RobotLiability liability)
    {
        // Store in memory available gas
        uint256 gasinit = gasleft();

        // Create liability
        liability = new RobotLiability(robotLiabilityLib);
        emit NewLiability(liability);

        // Parse messages
        require(liability.call(abi.encodePacked(bytes4(0x82fbaa25), _ask))); // liability.ask(...)
        usedHashGuard(liability.askHash());

        require(liability.call(abi.encodePacked(bytes4(0x66193359), _bid))); // liability.bid(...)
        usedHashGuard(liability.bidHash());

        // Transfer lighthouse fee to lighthouse worker directly
        require(xrt.transferFrom(liability.promisor(),
                                 tx.origin,
                                 liability.lighthouseFee()));

        // Transfer liability security and hold on contract
        ERC20 token = liability.token();
        require(token.transferFrom(liability.promisee(),
                                   liability,
                                   liability.cost()));

        // Transfer validator fee and hold on contract
        if (address(liability.validator()) != 0 && liability.validatorFee() > 0)
            require(xrt.transferFrom(liability.promisee(),
                                     liability,
                                     liability.validatorFee()));

        // Accounting gas usage of transaction
        uint256 gas = gasinit - gasleft() + 110525; // Including observation error
        totalGasUtilizing       += gas;
        gasUtilizing[liability] += gas;
     }

    /**
     * @dev Create lighthouse smart contract
     * @param _minimalFreeze Minimal freeze value of XRT token
     * @param _timeoutBlocks Max time of lighthouse silence in blocks
     * @param _name Lighthouse subdomain,
     *              example: for 'my-name' will created 'my-name.lighthouse.0.robonomics.eth' domain
     */
    function createLighthouse(
        uint256 _minimalFreeze,
        uint256 _timeoutBlocks,
        string  _name
    )
        external
        returns (address lighthouse)
    {
        // Name reservation check
        bytes32 subnode = keccak256(abi.encodePacked(lighthouseNode, keccak256(_name)));
        require(ens.resolver(subnode) == 0);

        // Create lighthouse
        lighthouse = new Lighthouse(lighthouseLib, _minimalFreeze, _timeoutBlocks);
        emit NewLighthouse(lighthouse, _name);
        isLighthouse[lighthouse] = true;

        bytes32 lighthouseNode
            // lighthouse.0.robonomics.eth
            = 0x1e42a8e8e1e8cf36e83d096dcc74af801d0a194a14b897f9c8dfd403b4eebeda;

        // Register subnode
        ens.setSubnodeOwner(lighthouseNode, keccak256(_name), this);

        // Register lighthouse address
        PublicResolver resolver = PublicResolver(ens.resolver(lighthouseNode));
        ens.setResolver(subnode, resolver);
        resolver.setAddr(subnode, lighthouse);
    }

    /**
     * @dev Is called whan after liability finalization
     * @param _gas Liability finalization gas expenses
     */
    function liabilityFinalized(
        uint256 _gas
    )
        external
        returns (bool)
    {
        require(gasUtilizing[msg.sender] > 0);

        uint256 gas = _gas - gasleft();
        totalGasUtilizing        += gas;
        gasUtilizing[msg.sender] += gas;
        require(xrt.mint(tx.origin, wnFromGas(gasUtilizing[msg.sender])));
        return true;
    }
}
