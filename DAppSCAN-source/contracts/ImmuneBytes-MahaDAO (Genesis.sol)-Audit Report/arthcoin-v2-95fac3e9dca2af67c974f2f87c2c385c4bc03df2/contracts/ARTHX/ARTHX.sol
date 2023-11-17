// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IARTHX} from './IARTHX.sol';
import {IARTH} from '../Arth/IARTH.sol';
import {IERC20} from '../ERC20/IERC20.sol';
import {Context} from '../utils/Context.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {AnyswapV4Token} from '../ERC20/AnyswapV4Token.sol';
import {IARTHController} from '../Arth/IARTHController.sol';
import {AccessControl} from '../access/AccessControl.sol';
import {IARTHXTaxController} from "./IARTHXTaxController.sol";

/**
 * @title  ARTHShares.
 * @author MahaDAO.
 *
 * Original code written by:
 * - Travis Moore, Jason Huan, Same Kazemian, Sam Sun.
 */
contract ARTHShares is AnyswapV4Token, IARTHX {
    using SafeMath for uint256;

    /**
     * State variables.
     */

    /// @dev Controller for arth params.
    IARTH private _ARTH;
    IARTHController private _arthController;
    IARTHXTaxController private _taxController;

    string public name;
    string public symbol;
    uint8 public constant override decimals = 18;
    uint256 public constant genesisSupply = 1e4 ether; // 10k is printed upon genesis.

    address public arthAddress;
    address public ownerAddress;
    address public oracleAddress;
    address public timelockAddress; // Governance timelock address.

    /**
     * Events.
     */

    event ARTHXBurned(address indexed from, address indexed to, uint256 amount);

    event ARTHXMinted(address indexed from, address indexed to, uint256 amount);

    /**
     * Modifier.
     */

    modifier onlyPools() {
        require(
            _ARTH.pools(msg.sender) == true,
            'Only arth pools can mint new ARTH'
        );
        _;
    }

     modifier onlyTaxController() {
        require(
            _msgSender() == address(_taxController),
            "ARTHX: FORBIDDEN"
        );
        _;
    }

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == ownerAddress || msg.sender == timelockAddress,
            'You are not an owner or the governance timelock'
        );
        _;
    }

    /**
     * Constructor.
     */

    constructor(
        string memory _name,
        string memory _symbol,
        address _oracleAddress,
        address _ownerAddress,
        address _timelockAddress
    ) AnyswapV4Token(_name) {
        name = _name;
        symbol = _symbol;

        ownerAddress = _ownerAddress;
        oracleAddress = _oracleAddress;
        timelockAddress = _timelockAddress;

        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _mint(ownerAddress, genesisSupply);
    }

    /**
     * External.
     */

    function setOracle(address newOracle)
        external
        override
        onlyByOwnerOrGovernance
    {
        oracleAddress = newOracle;
    }

    function setTaxController(IARTHXTaxController controller)
        external
        override
        onlyByOwnerOrGovernance
    {
        _taxController = controller;
    }

    function setArthController(address _controller)
        external
        override
        onlyByOwnerOrGovernance
    {
        _arthController = IARTHController(_controller);
    }

    function setTimelock(address newTimelock)
        external
        override
        onlyByOwnerOrGovernance
    {
        timelockAddress = newTimelock;
    }

    function setARTHAddress(address arthContractAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        _ARTH = IARTH(arthContractAddress);
    }

    function setOwner(address _ownerAddress)
        external
        override
        onlyByOwnerOrGovernance
    {
        ownerAddress = _ownerAddress;
    }

    function mint(address to, uint256 amount) public onlyPools {
        _mint(to, amount);
    }

    // This function is what other arth pools will call to mint new ARTHX (similar to the ARTH mint)
    function poolMint(address account, uint256 amount)
        external
        override
        onlyPools
    {
        super._mint(account, amount);

        emit ARTHXMinted(address(this), account, amount);
    }

    // This function is what other arth pools will call to burn ARTHX
    function poolBurnFrom(address account, uint256 amount)
        external
        override
        onlyPools
    {
        super._burnFrom(account, amount);
        emit ARTHXBurned(account, address(this), amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual override notPaused onlyNonBlacklisted(sender) {
        // Check if tax mode is on, and if its is on tax the tx and transfer the
        // remaining amount to `recipient`.
        if (address(_taxController) != address(0))
            amount = _taxController.chargeTax(_msgSender(), amount);

        super._transfer(sender, recipient, amount);
    }

    function taxTransfer(
        address spender,
        address receiver,
        uint256 amount
    ) external override notPaused onlyTaxController {
        super._transfer(spender, receiver, amount);
    }
}
