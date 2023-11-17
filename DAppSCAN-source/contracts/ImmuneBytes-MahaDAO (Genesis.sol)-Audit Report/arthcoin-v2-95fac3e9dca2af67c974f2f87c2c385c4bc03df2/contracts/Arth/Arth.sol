// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {IARTH} from './IARTH.sol';
import {IERC20} from '../ERC20/IERC20.sol';
import {ERC20Custom} from '../ERC20/ERC20Custom.sol';
import {SafeMath} from '../utils/math/SafeMath.sol';
import {IIncentiveController} from './IIncentive.sol';
import {AnyswapV4Token} from '../ERC20/AnyswapV4Token.sol';

/**
 * @title  ARTHStablecoin.
 * @author MahaDAO.
 */
contract ARTHStablecoin is AnyswapV4Token, IARTH {
    using SafeMath for uint256;

    IIncentiveController public incentiveController;

    address public governance;

    uint8 public constant override decimals = 18;
    string public constant symbol = 'ARTH';
    string public constant name = 'ARTH Valuecoin';

    /// @dev Number of fractions that make up 1 ARTH.
    uint256 private _fractionsPerAmount = 1;

    uint256 private _MAX_UINT256 = type(uint256).max;

    /// @dev ARTH v1 already in circulation.
    uint256 private _INITIAL_AMOUNT_SUPPLY = 21107858507999546111302861;

    uint256 private _TOTAL_FRACTIONS =
        _MAX_UINT256 - (_MAX_UINT256 % _INITIAL_AMOUNT_SUPPLY);

    uint256 private constant _REBASING_PRECISION = 1e6;

    /// @notice This is to help with establishing the Uniswap pools, as they need liquidity.
    uint256 public constant override genesisSupply = 22_000_000 ether; // 22M ARTH (testnet) & 5k (Mainnet).

    address public troveManagerAddress;
    address public stabilityPoolAddress;
    address public borrowerOperationsAddress;

    mapping(address => bool) public override pools;

    event Rebase(uint256 supply);
    event PoolBurned(address indexed from, address indexed to, uint256 amount);
    event PoolMinted(address indexed from, address indexed to, uint256 amount);
    event TroveManagerAddressChanged(address _troveManagerAddress);
    event StabilityPoolAddressChanged(address _newStabilityPoolAddress);
    event BorrowerOperationsAddressChanged(
        address _newBorrowerOperationsAddress
    );

    modifier onlyPools() {
        require(pools[msg.sender] == true, 'ARTH: not pool');
        _;
    }

    modifier onlyByOwnerOrGovernance() {
        require(
            msg.sender == owner() || msg.sender == governance,
            'ARTH: not owner or governance'
        );
        _;
    }

    modifier requireValidRecipient(address _recipient) {
        require(
            _recipient != address(0) && _recipient != address(this),
            'ARTH: Cannot transfer tokens directly to the ARTH token contract or the zero address'
        );
        require(
            _recipient != stabilityPoolAddress &&
                _recipient != troveManagerAddress &&
                _recipient != borrowerOperationsAddress,
            'ARTH: not owner or governance'
        );
        _;
    }

    modifier requireCallerIsBorrowerOperations() {
        require(
            msg.sender == borrowerOperationsAddress,
            'ARTH: Caller is not BorrowerOperations'
        );
        _;
    }

    modifier requireCallerIsBOorTroveMorSP() {
        require(
            msg.sender == borrowerOperationsAddress ||
                msg.sender == troveManagerAddress ||
                msg.sender == stabilityPoolAddress,
            'ARTH: Caller is not BorrowerOperations'
        );
        _;
    }

    modifier requireCallerIsStabilityPool() {
        require(
            msg.sender == stabilityPoolAddress,
            'ARTH: Caller is not the StabilityPool'
        );
        _;
    }

    modifier requireCallerIsTroveMorSP() {
        require(
            msg.sender == troveManagerAddress ||
                msg.sender == stabilityPoolAddress,
            'ARTH: Caller is neither TroveManager nor StabilityPool'
        );
        _;
    }

    constructor() AnyswapV4Token(name) {
        _mint(msg.sender, genesisSupply);
    }

    function setTroveManagerAddress(address _troveManagerAddress)
        external
        onlyOwner
    {
        troveManagerAddress = _troveManagerAddress;
        emit TroveManagerAddressChanged(_troveManagerAddress);
    }

    function setStabilityPoolAddress(address _stabilityPoolAddress)
        external
        onlyOwner
    {
        stabilityPoolAddress = _stabilityPoolAddress;
        emit StabilityPoolAddressChanged(_stabilityPoolAddress);
    }

    function setBorrowerOperationsAddress(address _borrowerOperationsAddress)
        external
        onlyOwner
    {
        borrowerOperationsAddress = _borrowerOperationsAddress;
        emit BorrowerOperationsAddressChanged(_borrowerOperationsAddress);
    }

    function sendToPool(
        address _sender,
        address _poolAddress,
        uint256 _amount
    ) external override requireCallerIsStabilityPool {
        _transfer(_sender, _poolAddress, _amount);
    }

    function returnFromPool(
        address _poolAddress,
        address _receiver,
        uint256 _amount
    ) external override requireCallerIsTroveMorSP {
        _transfer(_poolAddress, _receiver, _amount);
    }

    function rebase(int256 supplyDelta)
        external
        onlyByOwnerOrGovernance
        returns (uint256)
    {
        if (supplyDelta == 0) {
            emit Rebase(totalSupply());
            return totalSupply();
        }

        if (supplyDelta < 0) {
            _totalSupply = _totalSupply.sub(uint256(supplyDelta * -1));
        } else {
            _totalSupply = _totalSupply.add(uint256(supplyDelta));
        }

        /*
        if (_totalSupply > MAX_SUPPLY) {
            _totalSupply = MAX_SUPPLY;
        }
        */

         _fractionsPerAmount = _TOTAL_FRACTIONS.mul(_REBASING_PRECISION).div(
            totalSupply()
        );

        /*
            From this point forward, _fractionsPerAmount is taken as the source of truth.
        We recalculate a new _totalSupply to be in agreement with the _fractionsPerAmount
        conversion rate.
            This means our applied supplyDelta can deviate from the requested supplyDelta,
        but this deviation is guaranteed to be < (_totalSupply^2)/(_TOTAL_FRACTIONS - _totalSupply).
            In the case of _totalSupply <= MAX_UINT128 (our current supply cap), this
        deviation is guaranteed to be < 1, so we can omit this step. If the supply cap is
        ever increased, it must be re-included _totalSupply = _TOTAL_FRACTIONS.div(_fractionsPerAmount).
        */

        emit Rebase(totalSupply());
        return totalSupply();
    }

    function balanceOf(address account)
        public
        view
        override(IERC20, ERC20Custom)
        returns (uint256)
    {
        return _convertFractionToAmount(_balances[account]);
    }

    function _mint(address account, uint256 amount)
        internal
        override
        onlyNonBlacklisted(account)
    {
        require(account != address(0), 'ERC20: mint to the zero address');

        uint256 fractionAmount = _convertAmountToFraction(amount);
        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(fractionAmount);

        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount)
        internal
        override
        onlyNonBlacklisted(account)
    {
        require(account != address(0), 'ERC20: burn from the zero address');

        uint256 fractionAmount = _convertAmountToFraction(amount);
        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(
            fractionAmount,
            'ERC20: burn amount exceeds balance'
        );

        _totalSupply = _totalSupply.sub(amount);

        emit Transfer(account, address(0), amount);
    }

    /// @notice Used by pools when user redeems.
    function poolBurnFrom(address who, uint256 amount)
        external
        override
        onlyPools
    {
        super._burnFrom(who, amount);
        emit PoolBurned(who, msg.sender, amount);
    }

    /// @notice This function is what other arth pools will call to mint new ARTH
    function poolMint(address who, uint256 amount) external override onlyPools {
        _mint(who, amount);
        emit PoolMinted(msg.sender, who, amount);
    }

    /// @dev    Collateral Must be ERC20.
    /// @notice Adds collateral addresses supported.
    function addPool(address pool) external override onlyByOwnerOrGovernance {
        require(pools[pool] == false, 'pool exists');
        pools[pool] = true;
    }

    /// @notice Removes a pool.
    function removePool(address pool)
        external
        override
        onlyByOwnerOrGovernance
    {
        require(pools[pool] == true, "pool doesn't exist");
        delete pools[pool];
    }

    function setGovernance(address _governance) external override onlyOwner {
        governance = _governance;
    }

    function setIncentiveController(IIncentiveController _incentiveController)
        external
        override
        onlyByOwnerOrGovernance
    {
        incentiveController = _incentiveController;
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal override {
        uint256 fractionAmount = _convertAmountToFraction(amount);

        super._transfer(sender, recipient, fractionAmount);

        if (address(incentiveController) != address(0)) {
            incentiveController.incentivize(
                sender,
                recipient,
                msg.sender,
                amount
            );
        }
    }

    function _convertFractionToAmount(uint256 fraction)
        internal
        view
        returns (uint256)
    {
        return fraction.mul(_REBASING_PRECISION).div(_fractionsPerAmount);
    }

    function _convertAmountToFraction(uint256 amount)
        internal
        view
        returns (uint256)
    {
        return amount.mul(_fractionsPerAmount).div(_REBASING_PRECISION);
    }
}
