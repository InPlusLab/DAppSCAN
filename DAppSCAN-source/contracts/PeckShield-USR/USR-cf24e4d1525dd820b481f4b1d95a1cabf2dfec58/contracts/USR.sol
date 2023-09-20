pragma solidity 0.5.12;

import './library/ERC20SafeTransfer';
import './library/IERC20';
import './library/LibNote';
import './library/Pausable';
import './library/SafeMath';

contract InterestModel {
    function getInterestRate() external view returns (uint);
}

/// USR.sol -- USDx Savings Rate

/*
   "Savings USDx" is obtained when USDx is deposited into
   this contract. Each "Savings USDx" accrues USDx interest
   at the "USDx Savings Rate".

         --- `save` your `USDx` in the `USR.sol` ---

   - `mint`: start saving some USDx
   - `burn`: remove some USR
   - `draw`: get back some USDx
   - `drip`: perform rate collection
   - `getTotalBalance`: user current total balance with benefits
*/

contract USR is LibNote, Pausable, ERC20SafeTransfer {
    using SafeMath for uint;
    // --- Data ---
    bool private initialized;     // flag of initialize data

    uint public exchangeRate;     // the rate accumulator
    uint public lastTriggerTime;  // time of last drip
    uint public originationFee;   // trade fee

    address public interestModel;
    address public usdx;

    uint public maxDebtAmount;    // max debt amount, scaled by 1e18.

    uint constant ONE = 10 ** 27;
    uint constant BASE = 10 ** 18;

    // --- ERC20 Data ---
    string  public name;
    string  public symbol;
    uint8   public decimals;
    uint256 public totalSupply;

    mapping (address => uint)                      public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;

    // --- Event ---
    event Approval(address indexed src, address indexed guy, uint wad);
    event Transfer(address indexed src, address indexed dst, uint wad);

    event SetMaxDebtAmount(address indexed owner, uint indexed newTokenMaxAmount, uint indexed oldTokenMaxAmount);
    event NewInterestModel(address InterestRate, address oldInterestRate);
    event NewOriginationFee(uint oldOriginationFeeMantissa, uint newOriginationFeeMantissa);

    /**
     * The constructor is used here to ensure that the implementation
     * contract is initialized. An uncontrolled implementation
     * contract might lead to misleading state
     * for users who accidentally interact with it.
     */
    constructor(string memory _name, string memory _symbol, uint8 _decimals, address _interestModel, address _usdx, uint _originationFee, uint _maxDebtAmount) public {
        initialize(_name, _symbol, _decimals, _interestModel, _usdx, _originationFee, _maxDebtAmount);
    }

    // --- Init ---
    function initialize(string memory _name, string memory _symbol, uint8 _decimals, address _interestModel, address _usdx, uint _originationFee, uint _maxDebtAmount) public {
        require(!initialized, "initialize: already initialized.");
        require(_originationFee < BASE / 10, "initialize: fee should be less than ten percent.");
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        interestModel = _interestModel;
        usdx = _usdx;
        owner = msg.sender;
        exchangeRate = ONE;
        lastTriggerTime = now;
        originationFee = _originationFee;
        maxDebtAmount = _maxDebtAmount;
        initialized = true;

        emit NewInterestModel(_interestModel, address(0));
        emit NewOriginationFee(0, _originationFee);
        emit SetMaxDebtAmount(msg.sender, _maxDebtAmount, 0);
    }

    // --- Administration ---
    /**
     * @dev Owner function to set a new interest model contract address.
     * @param _newInterestModel new interest model contract address.
     * @return bool true=success, otherwise a failure.
     */
    function updateInterestModel(address _newInterestModel) external note onlyOwner returns (bool) {
        require(_newInterestModel != interestModel, "updateInterestModel: same interest model address.");
        address _oldInterestModel = interestModel;
        interestModel = _newInterestModel;
        emit NewInterestModel(_newInterestModel, _oldInterestModel);

        return true;
    }

    /**
     * @dev Owner function to set a new origination fee.
     * @param _newOriginationFee rational trading fee ratio, scaled by 1e18.
     * @return bool true=success, otherwise a failure.
     */
    function updateOriginationFee(uint _newOriginationFee) external onlyOwner returns (bool) {
        require(_newOriginationFee < BASE / 10, "updateOriginationFee: fee should be less than ten percent.");
        uint _oldOriginationFee = originationFee;
        require(_oldOriginationFee != _newOriginationFee, "updateOriginationFee: The old and new values cannot be the same.");
        originationFee = _newOriginationFee;
        emit NewOriginationFee(_oldOriginationFee, _newOriginationFee);

        return true;
    }

    /**
     * @dev Owner function to set max debt amount.
     * @param _newMaxDebtAmount rational debt threshold, scaled by 1e18.
     */
    function setMaxDebtAmount(uint _newMaxDebtAmount) external onlyOwner {
        uint _oldTokenMaxAmount = maxDebtAmount;
        require(_oldTokenMaxAmount != _newMaxDebtAmount, "setMaxDebtAmount: The old and new values cannot be the same.");
        maxDebtAmount = _newMaxDebtAmount;
        emit SetMaxDebtAmount(owner, _newMaxDebtAmount, _oldTokenMaxAmount);
    }

    /**
     * @dev Manager function to transfer token out to earn extra savings
            but only when the contract is not paused.
     * @param _token reserve asset, generally spaking it should be USDx.
     * @param _recipient account to receive asset.
     * @param _amount transfer amount.
     * @return bool true=success, otherwise a failure.
     */
    function transferOut(address _token, address _recipient, uint _amount) external onlyManager whenNotPaused returns (bool) {
        require(doTransferOut(_token, _recipient, _amount));
        return true;
    }

    // --- Math ---
    function rpow(uint x, uint n, uint base) internal pure returns (uint z) {
        assembly {
            switch x case 0 {switch n case 0 {z := base} default {z := 0}}
            default {
                switch mod(n, 2) case 0 { z := base } default { z := x }
                let half := div(base, 2)  // for rounding.
                for { n := div(n, 2) } n { n := div(n,2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0,0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0,0) }
                    x := div(xxRound, base)
                    if mod(n,2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0,0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }

    function rmul(uint x, uint y) internal pure returns (uint z) {
        z = x.mul(y) / ONE;
    }
    function rdiv(uint x, uint y) internal pure returns (uint z) {
        z = x.mul(ONE) / y;
    }
    function rdivup(uint x, uint y) internal pure returns (uint z) {
        z = x.mul(ONE).add(y.sub(1)) / y;
    }

    function mulScale(uint x, uint y) internal pure returns (uint z) {
        z = x.mul(y) / BASE;
    }

    function divScale(uint x, uint y) internal pure returns (uint z) {
        z = x.mul(BASE).add(y.sub(1)) / y;
    }

    /**
     * @dev Savings Rate Accumulation.
     * @return the most recent exchange rate, scaled by 1e27.
     */
    function drip() public note returns (uint _tmp) {
        require(now >= lastTriggerTime, "drip: invalid now.");
        uint _usr = InterestModel(interestModel).getInterestRate();
        _tmp = rmul(rpow(_usr, now - lastTriggerTime, ONE), exchangeRate);
        exchangeRate = _tmp;
        lastTriggerTime = now;
    }

    /**
     * @dev Deposit USDx to earn savings, but only when the contract is not paused.
     * @param _dst account who will get benefits.
     * @param _pie amount to buy, scaled by 1e18.
     */
    function join(address _dst, uint _pie) private note whenNotPaused {
        require(now == lastTriggerTime, "join: last trigger time not updated.");
        require(doTransferFrom(usdx, msg.sender, address(this), _pie));
        uint _wad = rdiv(_pie, exchangeRate);
        balanceOf[_dst] = balanceOf[_dst].add(_wad);
        totalSupply = totalSupply.add(_wad);
        require(rmul(totalSupply, exchangeRate) <= maxDebtAmount, "join: not enough to join.");
        emit Transfer(address(0), _dst, _wad);
    }

    /**
     * @dev Withdraw to get USDx according to input USR amount, but only when the contract is not paused.
     * @param _src account who will receive benefits.
     * @param _wad amount to burn USR, scaled by 1e18.
     */
    function exit(address _src, uint _wad) private note whenNotPaused {
        require(now == lastTriggerTime, "exit: lastTriggerTime not updated.");
        require(balanceOf[_src] >= _wad, "exit: insufficient balance");
        if (_src != msg.sender && allowance[_src][msg.sender] != uint(-1)) {
            require(allowance[_src][msg.sender] >= _wad, "exit: insufficient allowance");
            allowance[_src][msg.sender] = allowance[_src][msg.sender].sub(_wad);
        }
        balanceOf[_src] = balanceOf[_src].sub(_wad);
        totalSupply = totalSupply.sub(_wad);
        uint earningWithoutFee = rmul(_wad, exchangeRate);

        require(doTransferOut(usdx, msg.sender, mulScale(earningWithoutFee, BASE.sub(originationFee))));
        emit Transfer(_src, address(0), _wad);
    }

    /**
     * @dev Withdraw to get specified USDx, but only when the contract is not paused.
     * @param _src account who will receive benefits.
     * @param _pie amount to withdraw USDx, scaled by 1e18.
     */
    function draw(address _src, uint _pie) private note whenNotPaused {
        require(now == lastTriggerTime, "draw: last trigger time not updated.");
        uint _wad = rdivup(divScale(_pie, BASE.sub(originationFee)), exchangeRate);
        require(balanceOf[_src] >= _wad, "draw: insufficient balance");
        if (_src != msg.sender && allowance[_src][msg.sender] != uint(-1)) {
            require(allowance[_src][msg.sender] >= _wad, "draw: insufficient allowance");
            allowance[_src][msg.sender] = allowance[_src][msg.sender].sub(_wad);
        }
        balanceOf[_src] = balanceOf[_src].sub(_wad);
        totalSupply = totalSupply.sub(_wad);

        require(doTransferOut(usdx, msg.sender, _pie));
        emit Transfer(_src, address(0), _wad);
    }

    // --- Token ---
    function transfer(address _dst, uint _wad) external returns (bool) {
        return transferFrom(msg.sender, _dst, _wad);
    }

    // like transferFrom but Token-denominated
    function move(address _src, address _dst, uint _pie) external returns (bool) {
        uint _exchangeRate = (now > lastTriggerTime) ? drip() : exchangeRate;
        // rounding up ensures _dst gets at least _pie Token
        return transferFrom(_src, _dst, rdivup(_pie, _exchangeRate));
    }

    function transferFrom(address _src, address _dst, uint _wad) public returns (bool)
    {
        require(balanceOf[_src] >= _wad, "transferFrom: insufficient balance");
        if (_src != msg.sender && allowance[_src][msg.sender] != uint(-1)) {
            require(allowance[_src][msg.sender] >= _wad, "transferFrom: insufficient allowance");
            allowance[_src][msg.sender] = allowance[_src][msg.sender].sub(_wad);
        }
        balanceOf[_src] = balanceOf[_src].sub(_wad);
        balanceOf[_dst] = balanceOf[_dst].add(_wad);
        emit Transfer(_src, _dst, _wad);
        return true;
    }

    function approve(address _spender, uint _wad) external returns (bool) {
        allowance[msg.sender][_spender] = _wad;
        emit Approval(msg.sender, _spender, _wad);
        return true;
    }

    /**
     * @dev Get current contract debet.
     * @return int > 0 indicates no debts,
     *         otherwise in debt, and it indicates lossing amount, scaled by 1e18.
     */
    //  SWC-129-Typographical Error: L295
    function equity() external view returns (int) {
        uint _totalAmount = rmul(totalSupply, getExchangeRate());
        uint _banance = IERC20(usdx).balanceOf(address(this));
        if (_totalAmount > _banance)
            return -1 * int(_totalAmount.sub(_banance));

        return int(_banance.sub(_totalAmount));
    }

    /**
     * @dev Available quantity to buy.
     * @return uint > 0 indicates remaining share can be bought, scaled by 1e18,
     *         otherwise no share.
     */
    function share() external view returns (uint) {
        uint _totalAmount = rmul(totalSupply, getExchangeRate());
        uint _tokenMaxAmount = maxDebtAmount;
        return _tokenMaxAmount > _totalAmount ? _tokenMaxAmount.sub(_totalAmount) : 0;
    }

    /**
     * @dev Total amount with earning savings.
     * @param _account account to query current total balance.
     * @return total balance with any accumulated interest.
     */
    function getTotalBalance(address _account) external view returns (uint _wad) {
        uint _exchangeRate = getExchangeRate();
        _wad = mulScale(rmul(balanceOf[_account], _exchangeRate), BASE.sub(originationFee));
    }

    /**
     * @dev the most recent exchange rate, scaled by 1e27.
     */
    function getExchangeRate() public view returns (uint) {
        return getFixedExchangeRate(now.sub(lastTriggerTime));
    }

    function getFixedExchangeRate(uint interval) public view returns (uint) {
        uint _scale = ONE;
        return rpow(InterestModel(interestModel).getInterestRate(), interval, _scale).mul(exchangeRate) / _scale;
    }

    // _pie is denominated in Token
    function mint(address _dst, uint _pie) external {
        if (now > lastTriggerTime)
            drip();

        join(_dst, _pie);
    }

    // _wad is denominated in (1/exchangeRate) * Token
    function burn(address _src, uint _wad) external {
        if (now > lastTriggerTime)
            drip();
        exit(_src, _wad);
    }

    // _pie is denominated in Token
    function withdraw(address _src, uint _pie) external {
        if (now > lastTriggerTime)
            drip();
        // rounding up ensures usr gets at least _pie Token
        draw(_src, _pie);
    }
}
