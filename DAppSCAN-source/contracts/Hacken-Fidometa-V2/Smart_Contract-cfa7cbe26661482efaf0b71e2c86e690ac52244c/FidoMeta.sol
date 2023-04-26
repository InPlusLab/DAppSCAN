pragma solidity 0.8.11;

// SPDX-License-Identifier: Unlicensed
interface IERC20 {
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
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */


contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

contract Ownable is Context {
    address private _owner;
    address private _previousOwner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    function owner() public view returns (address) {
        return _owner;
    }

    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(
            newOwner != address(0),
            "Ownable: new owner is the zero address"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

contract Fidometa is Context, IERC20, Ownable {

    mapping(address => uint256) private _rOwned;
    mapping(address => uint256) private _tOwned;

    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => bool) public _isExcludedFromCommunity_charge;
    mapping(address => bool) public _isExcludedFromReward;

    address[] private _excluded;

    mapping(address => bool) public _isExcludedFromEcoSysFee;
    mapping(address => bool) public _isExcludedFromSurcharge1;
    mapping(address => bool) public _isExcludedFromSurcharge2;
    mapping(address => bool) public _isExcludedFromSurcharge3;

    uint256 private constant MAX = ~uint256(0);

    string public constant name = "Fido Meta";
    string public constant symbol = "FMC";
    uint8 public constant decimals = 9;
    uint256 private  _tTotal = 15000000000 * 10**uint256(decimals);
    uint256 public _cap;
    uint256 private _rTotal = (MAX - (MAX % _tTotal));
    uint256 public _tCommunityChargeTotal;

    address public _ecoSysWallet;
    address public _surcharge_1_Wallet;
    address public _surcharge_2_Wallet;
    address public _surcharge_3_Wallet;

    uint256 public _community_charge = 3 * 10**uint256(decimals);
    uint256 public _ecoSysFee = 15 * 10**8;
    uint256 public _surcharge1 = 5 * 10**8;
    uint256 public _surcharge2 = 0;
    uint256 public _surcharge3 = 0;

    uint256 private _previousCommunityCharge = _community_charge;
    uint256 private _previousEcoSysFee = _ecoSysFee;
    uint256 private _previousSurcharge1 = _surcharge1;
    uint256 private _previousSurcharge2 = _surcharge2;
    uint256 private _previousSurcharge3 = _surcharge3;

    uint256 public _maxTxAmount = 5000000 * 10**uint256(decimals);

    mapping(address => LockDetails) public locks;

    struct LockDetails {
        uint256 startTime;
        uint256 initialLock;
        uint256 lockedToken;
        uint256 remainedToken;
        uint256 monthCount;
    }

    struct TValues {
        uint256 tTransferAmount;
        uint256 tCommunityCharge;
        uint256 tEcoSysFee;
        uint256 tSurcharge1;
        uint256 tSurcharge2;
        uint256 tSurcharge3;
    }

    struct MValues {
        uint256 rAmount;
        uint256 rTransferAmount;
        uint256 rCommunityCharge;
        uint256 tTransferAmount;
        uint256 tCommunityCharge;
        uint256 tEcoSysFee;
        uint256 tSurcharge1;
        uint256 tSurcharge2;
        uint256 tSurcharge3;
    }

    constructor() {
        _rOwned[_msgSender()] = _rTotal;

        //exclude owner and this contract from fees
        _isExcludedFromCommunity_charge[owner()] = true;
        _isExcludedFromCommunity_charge[address(this)] = true;

        _isExcludedFromEcoSysFee[owner()] = true;
        _isExcludedFromEcoSysFee[address(this)] = true;

        _isExcludedFromSurcharge1[owner()] = true;
        _isExcludedFromSurcharge1[address(this)] = true;

        _isExcludedFromSurcharge2[owner()] = true;
        _isExcludedFromSurcharge2[address(this)] = true;

        _isExcludedFromSurcharge3[owner()] = true;
        _isExcludedFromSurcharge3[address(this)] = true;

        _cap = _tTotal;

        emit Transfer(address(0), _msgSender(), _tTotal);
    }

    /**
     * @dev gives total Supply
     */
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    /**
     * @dev gives balance of an account
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcludedFromReward[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    /**
     * @dev transfer Fund
     */

    function transfer(address recipient, uint256 amount)
        external
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */

    function allowance(address ownerAccount, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[ownerAccount][spender];
    }

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
     */

    function approve(address spender, uint256 amount)
        external
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev increases allowance
     */
    function increaseAllowance(address spender, uint256 addedValue)
        external
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    /**
     * @dev decreases allowance
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        external
        virtual
        returns (bool)
    {
        require(_allowances[_msgSender()][spender] <= subtractedValue, "BEP20: decreased allowance below zero");
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] - subtractedValue
        );
        return true;
    }

    function _approve(
        address _ownerAccount,
        address spender,
        uint256 amount
    ) private {
        require(_ownerAccount != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");
        _allowances[_ownerAccount][spender] = amount;
        emit Approval(_ownerAccount, spender, amount);
    }

    /**
     * @dev Set charges of the FidoMeta Ecosystem that includes, CommunityCharge,EcoSysFee,Surcharge1,Surcharge2,Surcharge3
     * community_charge : charges that deduct from the transaction and distributed to the community
     * ecoSysFee : this fee will be deducted and go to Fidometa ecosystem wallet
     * surcharge1,surcharge2,surcharge3 : these are the placeholder that can be used to provide optional charges for fidometa central bank ecosystem.
     * Can only be called by the current owner.
     */

    function setCharges(
        uint256 community_charge,
        uint256 ecoSysFee,
        uint256 surcharge1,
        uint256 surcharge2,
        uint256 surcharge3
    ) external onlyOwner {

         require(
            community_charge + ecoSysFee + surcharge1 + surcharge2 + surcharge3 <= (100 * 10**uint256(decimals)),
            "Sum of all charges should be less than 100%"
        );

        require(
            community_charge <= (100 * 10**uint256(decimals)),
            "Community Charge % should be less than equal to 100%"
        );
        require(
            ecoSysFee <= (100 * 10**uint256(decimals)),
            "EcoSysFee % should be less than equal to 100%"
        );
        require(
            surcharge1 <= (100 * 10**uint256(decimals)),
            "surcharge1 % should be less than equal to 100%"
        );
        require(
            surcharge2 <= (100 * 10**uint256(decimals)),
            "surcharge2 % should be less than equal to 100%"
        );
        require(
            surcharge3 <= (100 * 10**uint256(decimals)),
            "surcharge3 % should be less than equal to 100%"
        );
        _community_charge = community_charge;
        _ecoSysFee = ecoSysFee;
        _surcharge1 = surcharge1;
        _surcharge2 = surcharge2;
        _surcharge3 = surcharge3;
    }

    /**
     * @dev Set service wallet includes ecoSysWallet,surcharge_1_wallet,surcharge_2_wallet,surcharge_3_wallet
     * ecoSysWallet: where ecoSysFee is to be deposited
     * surcharge_1_wallet, surcharge_2_wallet, surcharge_3_wallet is where the surcahrge1,surcahrge2,surcahrge3 is to be deposited
     * these service wallet should be excluded from all charges including EcoSysFee,Community_charge,surcharge1,surcharge2,surcharge3 and reward
     * Can only be called by the current owner.
     */

    function setServiceWallet(
        address ecoSysWallet,
        address surcharge_1_wallet,
        address surcharge_2_wallet,
        address surcharge_3_wallet
    ) external onlyOwner {
        require(
            ecoSysWallet != address(0),
            "Ecosystem wallet wallet is not valid"
        );

        //add the new service wallet
        _ecoSysWallet = ecoSysWallet;
        _surcharge_1_Wallet = surcharge_1_wallet;
        _surcharge_2_Wallet = surcharge_2_wallet;
        _surcharge_3_Wallet = surcharge_3_wallet;

        //exclude _ecoSysWallet  from charges
        excludeFromCharges(_ecoSysWallet, true, true, true, true, true);
        excludeFromCharges(_surcharge_1_Wallet, true, true, true, true, true);
        excludeFromCharges(_surcharge_2_Wallet, true, true, true, true, true);
        excludeFromCharges(_surcharge_3_Wallet, true, true, true, true, true);

        excludeFromReward(_ecoSysWallet);
        excludeFromReward(_surcharge_1_Wallet);
        excludeFromReward(_surcharge_2_Wallet);
        excludeFromReward(_surcharge_3_Wallet);
    }

    /**
     * @dev tokenFromReflection
     */
    function tokenFromReflection(uint256 rAmount)
        private
        view
        returns (uint256)
    {
        require(
            rAmount <= _rTotal,
            "Amount must be less than total reflections"
        );
        uint256 currentRate = _getRate();
        return rAmount /currentRate;
    }

    /**
     *  @dev  include or exclude an account from charges,
     *  pass true/false
     *  true means excluded and false means included
     */
    function excludeFromCharges(
        address account,
        bool communityCharge,
        bool ecoSysFee,
        bool surcharge1,
        bool surcharge2,
        bool surcharge3
    ) public onlyOwner {
        _isExcludedFromCommunity_charge[account] = communityCharge;
        _isExcludedFromEcoSysFee[account] = ecoSysFee;
        _isExcludedFromSurcharge1[account] = surcharge1;
        _isExcludedFromSurcharge2[account] = surcharge2;
        _isExcludedFromSurcharge3[account] = surcharge3;
    }

    //exclude an address from getting community reward
    function excludeFromReward(address account) public onlyOwner {
        require(!_isExcludedFromReward[account], "Account is already excluded");
        if (_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcludedFromReward[account] = true;
        _excluded.push(account);
    }

    /**
     *  @dev it set the maximum amount of token an address can tranfer at once
     */
    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner {
        _maxTxAmount = (_tTotal * maxTxPercent) /(10**2);
    }

    /**
     * @dev  reflection of fee on each transfer
     */
    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal - rFee;
        _tCommunityChargeTotal = _tCommunityChargeTotal + tFee;
    }

    function _getValues(uint256 tAmount) private view returns (MValues memory) {
        uint256 currentRate = _getRate();
        TValues memory value = _getTValues(tAmount);
        (
            uint256 rAmount,
            uint256 rTransferAmount,
            uint256 rCommunityCharge
        ) = _getRValues(tAmount, value.tCommunityCharge, currentRate);
        uint256 rEcoSysFee = value.tEcoSysFee * currentRate;
        uint256 rSurcharge1 = value.tSurcharge1 * currentRate;
        uint256 rSurcharge2 = value.tSurcharge2 * currentRate;
        uint256 rSurcharge3 = value.tSurcharge3 * currentRate;
        rTransferAmount = rTransferAmount - rEcoSysFee - rSurcharge1 - rSurcharge2 - rSurcharge3;
        MValues memory mValues = MValues({
            rAmount: rAmount,
            rTransferAmount: rTransferAmount,
            rCommunityCharge: rCommunityCharge,
            tTransferAmount: value.tTransferAmount,
            tCommunityCharge: value.tCommunityCharge,
            tEcoSysFee: value.tEcoSysFee,
            tSurcharge1: value.tSurcharge1,
            tSurcharge2: value.tSurcharge2,
            tSurcharge3: value.tSurcharge3
        });
        return (mValues);
    }

    function _getTValues(uint256 tAmount)
        private
        view
        returns (TValues memory)
    {
        uint256 tCommunityCharge = (tAmount * _community_charge) / (10**11);
        uint256 tEcoSysFee = (tAmount * _ecoSysFee) / (10**11);
        uint256 tSurcharge1 = (tAmount *_surcharge1)/(10**11);
        uint256 tSurcharge2 = (tAmount * _surcharge2)/(10**11);
        uint256 tSurcharge3 = (tAmount * _surcharge3)/(10**11);
        uint256 tTransferAmountEco = tAmount- tCommunityCharge - tEcoSysFee;
        uint256 tTransferAmount = tTransferAmountEco - tSurcharge1 - tSurcharge2 - tSurcharge3;
        TValues memory tvalue = TValues({
            tTransferAmount: tTransferAmount,
            tCommunityCharge: tCommunityCharge,
            tEcoSysFee: tEcoSysFee,
            tSurcharge1: tSurcharge1,
            tSurcharge2: tSurcharge2,
            tSurcharge3: tSurcharge3
        });
        return (tvalue);
    }

    function _getRValues(
        uint256 tAmount,
        uint256 tFee,
        uint256 currentRate
    )
        private
        pure
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 rAmount = tAmount * currentRate;
        uint256 rFee = tFee * currentRate;
        uint256 rTransferAmount = rAmount - rFee;
        return (rAmount, rTransferAmount, rFee);
    }

    function _getRate() private view returns (uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply / tSupply;
    }

    function _getCurrentSupply() private view returns (uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;
        uint cacheLength = _excluded.length;
        for (uint256 i = 0; i < cacheLength; i++) {
            if (
                _rOwned[_excluded[i]] > rSupply ||
                _tOwned[_excluded[i]] > tSupply
            ) return (_rTotal, _tTotal);
            rSupply = rSupply - _rOwned[_excluded[i]];
            tSupply = tSupply - _tOwned[_excluded[i]];
        }
        if (rSupply < _rTotal / _tTotal) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }

    /**
     * @dev take charges as per percentage
     */

    function takeCharges(
        uint256 tEcoSys,
        uint256 tSurcharge1,
        uint256 tSurcharge2,
        uint256 tSurcharge3
    ) private {
        uint256 currentRate = _getRate();
        if (tEcoSys > 0) {
            uint256 rEcosys = tEcoSys * currentRate;
            _rOwned[_ecoSysWallet] = _rOwned[_ecoSysWallet] + rEcosys;
            if (_isExcludedFromEcoSysFee[_ecoSysWallet])
                _tOwned[_ecoSysWallet] = _tOwned[_ecoSysWallet] + tEcoSys;
        }
        if (tSurcharge1 > 0) {
            uint256 rSurcharge1 = tSurcharge1 * currentRate;
            _rOwned[_surcharge_1_Wallet] = _rOwned[_surcharge_1_Wallet] + rSurcharge1;
            if (_isExcludedFromSurcharge1[_surcharge_1_Wallet])
                _tOwned[_surcharge_1_Wallet] = _tOwned[_surcharge_1_Wallet] +
                    tSurcharge1;
        }
        if (tSurcharge2 > 0) {
            uint256 rSurcharge2 = tSurcharge2 * currentRate;
            _rOwned[_surcharge_2_Wallet] = _rOwned[_surcharge_2_Wallet] + 
                rSurcharge2
            ;
            if (_isExcludedFromSurcharge1[_surcharge_2_Wallet])
                _tOwned[_surcharge_2_Wallet] = _tOwned[_surcharge_2_Wallet]+
                    tSurcharge2
                ;
        }
        if (tSurcharge3 > 0) {
            uint256 rSurcharge3 = tSurcharge3 * currentRate;
            _rOwned[_surcharge_3_Wallet] = _rOwned[_surcharge_3_Wallet] + 
                rSurcharge3
            ;
            if (_isExcludedFromSurcharge3[_surcharge_3_Wallet])
                _tOwned[_surcharge_3_Wallet] = _tOwned[_surcharge_3_Wallet] +
                    tSurcharge3
                ;
        }
    }

    /**
     * @dev Transfers the tokens from an owner's account to the receiver account,
     * but only if the transaction initiator has sufficient allowance that
     * has been previously approved by the owner to the transaction initiator
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external override returns (bool) {
        _transfer(sender, recipient, amount);
         require(_allowances[sender][_msgSender()] > amount, "BEP20: transfer from the zero address");
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()] - amount
        );
        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) private {
        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(from != to, "Invalid target");
        if (from != owner() && to != owner())
            require(
                amount <= _maxTxAmount,
                "Transfer amount exceeds the maxTxAmount."
            );

        // it checks if an account is serving vesting period,
        //  if yes, it calculates how much token is withdrawable along with released token
        //  if amount crosses the withdrawable return an error
        if (locks[from].lockedToken > 0) {
            uint256 withdrawable = balanceOf(from) - locks[from].remainedToken;
            require(
                amount <= withdrawable,
                "Not enough Unlocked token Available"
            );
        }

        //indicates if fee should be deducted from transfer
        bool takeCommunityCharge = true;
        bool takeEcosysFee = true;
        bool takeSurcharge1 = true;
        bool takeSurcharge2 = true;
        bool takeSurcharge3 = true;

        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromCommunity_charge[from]) {
            takeCommunityCharge = false;
        }
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromEcoSysFee[from]) {
            takeEcosysFee = false;
        }
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromSurcharge1[from]) {
            takeSurcharge1 = false;
        }
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromSurcharge2[from]) {
            takeSurcharge2 = false;
        }
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if (_isExcludedFromSurcharge3[from]) {
            takeSurcharge3 = false;
        }

        _tokenTransfer(
            from,
            to,
            amount,
            takeCommunityCharge,
            takeEcosysFee,
            takeSurcharge1,
            takeSurcharge2,
            takeSurcharge3
        );
    }

    /**
     * @dev transfer token
     */
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amount,
        bool takeCommunityCharge,
        bool takeEcosysFee,
        bool takeSurcharge1,
        bool takeSurcharge2,
        bool takeSurcharge3
    ) private {
        if (!takeCommunityCharge) {
            _previousCommunityCharge = _community_charge;
            _community_charge = 0;
        }

        if (!takeEcosysFee) {
            _previousEcoSysFee = _ecoSysFee;
            _ecoSysFee = 0;
        }

        if (!takeSurcharge1) {
            _previousSurcharge1 = _surcharge1;
            _surcharge1 = 0;
        }

        if (!takeSurcharge2) {
            _previousSurcharge2 = _surcharge2;
            _surcharge2 = 0;
        }

        if (!takeSurcharge3) {
            _previousSurcharge3 = _surcharge3;
            _surcharge3 = 0;
        }

        if (
            _isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]
        ) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (
            !_isExcludedFromReward[sender] && _isExcludedFromReward[recipient]
        ) {
            _transferToExcluded(sender, recipient, amount);
        } else if (
            !_isExcludedFromReward[sender] && !_isExcludedFromReward[recipient]
        ) {
            _transferStandard(sender, recipient, amount);
        } else if (
            _isExcludedFromReward[sender] && _isExcludedFromReward[recipient]
        ) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }

        if (!takeCommunityCharge) _community_charge = _previousCommunityCharge;
        if (!takeEcosysFee) _ecoSysFee = _previousEcoSysFee;
        if (!takeSurcharge1) _surcharge1 = _previousSurcharge1;
        if (!takeSurcharge2) _surcharge2 = _previousSurcharge2;
        if (!takeSurcharge3) _surcharge3 = _previousSurcharge3;
    }

    /**
     * @dev it unlocks token from vesting period ,
     * locked token for initially for initial days than unlock 20% of locked token every month
     */

    function unlock(address target_) external {
        require(target_ != address(0), "Target address can not be zero address");
        uint256 startTime = locks[target_].startTime;
        uint256 lockedToken = locks[target_].lockedToken;
        uint256 remainedToken = locks[target_].remainedToken;
        uint256 monthCount = locks[target_].monthCount;
        uint256 initialLock = locks[target_].initialLock;
        require(remainedToken != 0, "All tokens are unlocked");

        require(
            block.timestamp > startTime + (initialLock * 1 days),
            "UnLocking period is not opened"
        );
        uint256 timePassed = block.timestamp -
            (startTime + (initialLock * 1 days));

        uint256 monthNumber = (uint256(timePassed) + (uint256(30 days) - 1)) /
            uint256(30 days);
        if(monthNumber>5) monthNumber=5;

        uint256 remainedMonth = monthNumber - monthCount;

        if (remainedMonth > 5) remainedMonth = 5;
        require(remainedMonth > 0, "Releasable token till now is released");

        uint256 receivableToken = (lockedToken * (remainedMonth * 20)) / 100;

        locks[target_].monthCount += remainedMonth;   
        remainedToken -= receivableToken;
        locks[target_].remainedToken = remainedToken;

        if (locks[target_].remainedToken == 0) {
            delete locks[target_];
        }
    }

    /** @dev Transfer with lock
     * @param recipient The recipient address.
     * @param tAmountWithoutDecimals Amount that has to be locked (without decimals)
     * @param initialLock duration in days for locking
     */

    function transferWithLock(
        address recipient,
        uint256 tAmountWithoutDecimals,
        uint256 initialLock
    ) external onlyOwner {
        require(recipient != address(0), "Invalid target");
        require(
            locks[recipient].lockedToken == 0,
            "This address is already in vesting period"
        );
       //decimals are added to the amount
       //Be carefull to not to transfer too much tokens
        uint256 tAmount = tAmountWithoutDecimals * 10**uint256(decimals);
        _transfer(_msgSender(), recipient, tAmount);
        locks[recipient] = LockDetails(
            block.timestamp,
            initialLock,
            tAmount,
            tAmount,
            0
        );
    }

    function _transferFromExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        MValues memory mvalues = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender] - tAmount;
        _rOwned[sender] = _rOwned[sender] - mvalues.rAmount;
        _doTransfer(mvalues, sender, recipient);
    }

    function _transferToExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        MValues memory mvalues = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender] - mvalues.rAmount;
        _tOwned[recipient] = _tOwned[recipient] + mvalues.tTransferAmount;
        _doTransfer(mvalues, sender, recipient);
    }

    function _transferStandard(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        MValues memory mvalues = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender] - mvalues.rAmount;
        _doTransfer(mvalues, sender, recipient);
    }

    function _transferBothExcluded(
        address sender,
        address recipient,
        uint256 tAmount
    ) private {
        MValues memory mvalues = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender] - tAmount;
        _rOwned[sender] = _rOwned[sender] - mvalues.rAmount;
        _tOwned[recipient] = _tOwned[recipient] + mvalues.tTransferAmount;
        _doTransfer(mvalues, sender, recipient);
    }

    function _doTransfer(
        MValues memory mvalues,
        address sender,
        address recipient
    ) private {
        _rOwned[recipient] = _rOwned[recipient] + mvalues.rTransferAmount;
        takeCharges(
            mvalues.tEcoSysFee,
            mvalues.tSurcharge1,
            mvalues.tSurcharge2,
            mvalues.tSurcharge3
        );
        _reflectFee(mvalues.rCommunityCharge, mvalues.tCommunityCharge);
        emit Transfer(sender, recipient, mvalues.tTransferAmount);
    }
}
