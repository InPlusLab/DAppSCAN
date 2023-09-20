/**

All Coins Yield Capital: $ACYC

- The Meme Coin Index
- You aim for one moon shot, we grab them all.

Tokenomics:

- Buy side taxes:
    - 10% of each buy goes to reflections.
- Sell side taxes:
    - 5% of each sell to our proprietary trading algorithm; and
    - 5% to the liquidity pool.
- You do the marketing

Distribution of profits from farming:

- 50% reflected back to token holders.
- 35% reflected back to farming pool.
- 15% to team and advisors.

Website:
https://acy.capital

Telegram:
https://t.me/ACYCapital

Twitter:
https://twitter.com/ACYCapital

Medium:
https://acycapital.medium.com

*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

// Contract implementation
contract AllCoinsYieldCapital is Context, IERC20, Ownable {
    using SafeMath for uint256;
    using Address for address;

    // standard variables
    string private _name = "AllCoinsYieldCapital";
    string private _symbol = "ACYC";
    uint8 private _decimals = 18;

    // baseline token construction
    uint256 private constant MAX = ~uint256(0);
    uint256 private _totalTokenSupply = 1 * 10**12 * 10**_decimals;
    uint256 private _totalReflections = (MAX - (MAX % _totalTokenSupply));
    uint256 private _totalTaxesReflectedToHodlers;
    uint256 private _totalTaxesSentToTreasury;
    mapping(address => uint256) private _reflectionsOwned;
    mapping(address => mapping(address => uint256)) private _allowances;

    // taxes and fees
    address payable public _treasuryAddress;
    uint256 private _currentTaxForReflections = 10; // modified depending on context of tx
    uint256 private _currentTaxForTreasury = 10; // modified depending on context of tx
    uint256 public _fixedTaxForReflections = 10; // unchanged save by owner transaction
    uint256 public _fixedTaxForTreasury = 10; // unchanged save by owner transaction

    // tax exempt addresses
    mapping(address => bool) private _isExcludedFromTaxes;

    // uniswap matters -- n.b. we are married to this particular uniswap v2 pair
    // contract will not survive as is and will require migration if a new pool
    // is stood up on sushiswap, uniswapv3, etc.
    address private uniDefault = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    IUniswapV2Router02 public immutable uniswapV2Router;
    bool private _inSwap = false;
    address public immutable uniswapV2Pair;

    // minimum tokens to initiate a swap
    uint256 private _minimumTokensToSwap = 10 * 10**3 * 10**_decimals;

    modifier lockTheSwap() {
        _inSwap = true;
        _;
        _inSwap = false;
    }

    constructor(address payable treasuryAddress, address router) {
        require(
            (treasuryAddress != address(0)),
            "Give me the treasury address"
        );
        _treasuryAddress = treasuryAddress;
        _reflectionsOwned[_msgSender()] = _totalReflections;

        // connect to uniswap router
        if (router == address(0)) {
            router = uniDefault;
        }
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(router);

        // setup uniswap pair
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
        uniswapV2Router = _uniswapV2Router;

        // Exclude owner, treasury, and this contract from fee
        _isExcludedFromTaxes[owner()] = true;
        _isExcludedFromTaxes[address(this)] = true;
        _isExcludedFromTaxes[_treasuryAddress] = true;

        emit Transfer(address(0), _msgSender(), _totalTokenSupply);
    }

    // recieve ETH from uniswapV2Router when swaping
    receive() external payable {
        return;
    }

    // We expose this function to modify the address where the treasuryTax goes
    function setTreasuryAddress(address payable treasuryAddress) external {
        require(_msgSender() == _treasuryAddress, "You cannot call this");
        require(
            (treasuryAddress != address(0)),
            "Give me the treasury address"
        );
        address _previousTreasuryAddress = _treasuryAddress;
        _treasuryAddress = treasuryAddress;
        _isExcludedFromTaxes[treasuryAddress] = true;
        _isExcludedFromTaxes[_previousTreasuryAddress] = false;
    }

    // We allow the owner to set addresses that are unaffected by taxes
    function excludeFromTaxes(address account, bool excluded)
        external
        onlyOwner
    {
        _isExcludedFromTaxes[account] = excluded;
    }

    // We expose these functions to be able to modify the fees and tx amounts
    function setReflectionsTax(uint256 tax) external onlyOwner {
        // SWC-135-Code With No Effects: L153
        require(tax >= 0 && tax <= 10, "ERC20: tax out of band");
        _currentTaxForReflections = tax;
        _fixedTaxForReflections = tax;
    }

    function setTreasuryTax(uint256 tax) external onlyOwner {
        // SWC-135-Code With No Effects: L160
        require(tax >= 0 && tax <= 10, "ERC20: tax out of band");
        _currentTaxForTreasury = tax;
        _fixedTaxForTreasury = tax;
    }

    // We expose these functions to be able to manual swap and send
    function manualSend() external onlyOwner {
        uint256 _contractETHBalance = address(this).balance;
        _sendETHToTreasury(_contractETHBalance);
    }

    function manualSwap() external onlyOwner {
        uint256 _contractBalance = balanceOf(address(this));
        _swapTokensForEth(_contractBalance);
    }

    // public functions to do things
    // SWC-126-Insufficient Gas Griefing: L176
    function transfer(address recipient, uint256 amount)
        public
        override
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount)
        public
        override
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    // used by smart contracts rather than users
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(
            sender,
            _msgSender(),
            _allowances[sender][_msgSender()].sub(
                amount,
                "ERC20: transfer amount exceeds allowance"
            )
        );
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        virtual
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "ERC20: decreased allowance below zero"
            )
        );
        return true;
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        uint256 currentRate = _getRate();
        return _totalReflections.div(currentRate);
    }

    function isExcludedFromTaxes(address account) public view returns (bool) {
        return _isExcludedFromTaxes[account];
    }

    function totalTaxesSentToReflections() public view returns (uint256) {
        return tokensFromReflection(_totalTaxesReflectedToHodlers);
    }

    function totalTaxesSentToTreasury() public view returns (uint256) {
        return tokensFromReflection(_totalTaxesSentToTreasury);
    }

    function getETHBalance() public view returns (uint256 balance) {
        return address(this).balance;
    }

    function allowance(address owner, address spender)
        public
        view
        override
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    function balanceOf(address account) public view override returns (uint256) {
        return tokensFromReflection(_reflectionsOwned[account]);
    }

    function reflectionFromToken(
        uint256 amountOfTokens,
        bool deductTaxForReflections
    ) public view returns (uint256) {
        require(
            amountOfTokens <= _totalTokenSupply,
            "Amount must be less than supply"
        );
        if (!deductTaxForReflections) {
            (uint256 reflectionsToDebit, , , ) = _getValues(amountOfTokens);
            return reflectionsToDebit;
        } else {
            (, uint256 reflectionsToCredit, , ) = _getValues(amountOfTokens);
            return reflectionsToCredit;
        }
    }

    function tokensFromReflection(uint256 amountOfReflections)
        public
        view
        returns (uint256)
    {
        require(
            amountOfReflections <= _totalReflections,
            "ERC20: Amount too large"
        );
        uint256 currentRate = _getRate();
        return amountOfReflections.div(currentRate);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) private {
        require(owner != address(0), "ERC20: approve from 0 address");
        require(spender != address(0), "ERC20: approve to 0 address");
        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    // transfer function that sets up the context so that the
    // _tokenTransfer function can do the accounting work
    // to perform the transfer function
    // SWC-107-Reentrancy: L331
    function _transfer(
        address sender,
        address recipient,
        uint256 amountOfTokens
    ) private {
        require(sender != address(0), "ERC20: transfer from 0 address");
        require(recipient != address(0), "ERC20: transfer to 0 address");
        require(amountOfTokens > 0, "ERC20: Transfer more than zero");

        // if either side of transfer account belongs to _isExcludedFromTaxes
        // account then remove the fee
        bool takeFee = true;
        if (_isExcludedFromTaxes[sender] || _isExcludedFromTaxes[recipient]) {
            takeFee = false;
        }

        // check if we're buy side or sell side in a swap; if buy side apply
        // buy side taxes; if sell side then apply those taxes; duh
        bool buySide = false;
        if (sender == address(uniswapV2Pair)) {
            buySide = true;
        }

        // based on context set the correct fee structure
        if (!takeFee) {
            _setNoFees();
        } else if (buySide) {
            _setBuySideFees();
        } else {
            _setSellSideFees();
        }

        // conduct the transfer
        _tokenTransfer(sender, recipient, amountOfTokens);

        // reset the fees for the next go around
        _restoreAllFees();
    }

    // primary transfer function that does all the work
    function _tokenTransfer(
        address sender,
        address recipient,
        uint256 amountOfTokens
    ) private {
        // when treasury transfers to the contract we automatically
        // remove these reflections from pool such that all token hodlers
        // benefit prorata and the treasury's reflections are removed.
        //
        // this allows for gas effective distribution of farming profits
        // to be returned cleanly to all token hodlers.
        //
        // we do not emit a Transfer event here because it is not strictly
        // speaking a transfer due to the lack of a recipient
        if (sender == _treasuryAddress && recipient == address(this)) {
            _manualReflect(amountOfTokens);
            return;
        }

        // the below allows for a consolidated handling of the necessary
        // math to support the possible transfer+tax combinations
        (
            uint256 reflectionsToDebit, // sender
            uint256 reflectionsToCredit, // recipient
            uint256 reflectionsToRemove, // to all the hodlers
            uint256 reflectionsForTreasury // to treasury
        ) = _getValues(amountOfTokens);

        // take taxes -- this is not a tax free zone ser
        _takeTreasuryTax(reflectionsForTreasury);
        _takeReflectionTax(reflectionsToRemove);

        // we potentially do any "inline" swapping after the taxes are taken
        // so that we know if there's balance to take.
        uint256 contractTokenBalance = balanceOf(address(this));
        bool overMinTokenBalance = contractTokenBalance >= _minimumTokensToSwap;
        if (!_inSwap && overMinTokenBalance && reflectionsForTreasury != 0) {
            _swapTokensForEth(contractTokenBalance);
        }
        uint256 contractETHBalance = address(this).balance;
        if (contractETHBalance > 0) {
            _sendETHToTreasury(address(this).balance);
        }

        // debit the correct reflections from the sender's account and credit
        // the correct number of reflections to the recipient's (accounting for
        // taxes)
        _reflectionsOwned[sender] = _reflectionsOwned[sender].sub(
            reflectionsToDebit
        );
        _reflectionsOwned[recipient] = _reflectionsOwned[recipient].add(
            reflectionsToCredit
        );

        // let the world know
        emit Transfer(sender, recipient, reflectionsToCredit.div(_getRate()));
    }

    // allows for treasury to cleanly distribute earnings back to
    // tokenhodlers pro rata
    function _manualReflect(uint256 amountOfTokens) private {
        uint256 currentRate = _getRate();
        uint256 amountOfReflections = amountOfTokens.mul(currentRate);

        // we remove the reflections from the treasury address and then
        // burn them by removing them from the reflections pool thus
        // reducing the denominator and "distributing" the reflections
        // to all hodlers pro rata
        _reflectionsOwned[_treasuryAddress] = _reflectionsOwned[
            _treasuryAddress
        ].sub(amountOfReflections);
        _totalReflections = _totalReflections.sub(amountOfReflections);
    }

    // reflections are added to the balance of this contract and are
    // subsequently swapped out with the uniswap pair within the same
    // transaction; the resulting eth is transfered to the treasury.
    //
    // the below function is simple accounting which will not survive
    // to the end of the transaction as long as the totaly amount of
    // reflections taken by the tax are more than the _minimumTokensToSwap
    //
    // in the case where they are not more than _minimumTokensToSwap
    // the tokens will not be swapped due to gas concerns and will simply
    // accrue within the contract until the contract's acyc balance is
    // more than _minimumTokensToSwap at which time the automatic swap
    // will occur sending eth to the treasury.
    function _takeTreasuryTax(uint256 reflectionsForTreasury) private {
        _reflectionsOwned[address(this)] = _reflectionsOwned[address(this)].add(
            reflectionsForTreasury
        );
        _totalTaxesSentToTreasury = _totalTaxesSentToTreasury.add(
            reflectionsForTreasury
        );
    }

    // reflections are "reflected" back to hodlers via a mechanism which
    // seeks to simply remove the amount of the tax from the total reflection
    // pool. since the token balance is a simple product of the amount of
    // reflections a hodler has in their account to the ratio of all the
    // reflections to the total token supply, removing reflections is a
    // gas efficient way of applying a benefit to all hodlers pro rata as
    // it lowers the denominator in the ratio thus increasing the result
    // of the product. in other words, by removing reflections the
    // numbers folks care about go up.
    function _takeReflectionTax(uint256 reflectionsToRemove) private {
        _totalReflections = _totalReflections.sub(reflectionsToRemove);
        _totalTaxesReflectedToHodlers = _totalTaxesReflectedToHodlers.add(
            reflectionsToRemove
        );
    }

    // baking this in so deeply will mean if the uni v2 pool ever dries up
    // then the contract will effectively stop functioning and it will need
    // to be migrated
    function _swapTokensForEth(uint256 tokenAmount) private lockTheSwap {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(_treasuryAddress),
            block.timestamp
        );
    }

    function _sendETHToTreasury(uint256 amount) private {
        _treasuryAddress.transfer(amount);
    }

    // on buy side we collect tax and apply that to reflections; there is
    // no tax taken for the treasury on the buy side
    function _setBuySideFees() private {
        _currentTaxForReflections = _fixedTaxForReflections;
        _currentTaxForTreasury = 0;
    }

    // on sell side we collect tax and apply that to the treasury account;
    // there is no sell side tax taken for reflections
    function _setSellSideFees() private {
        _currentTaxForReflections = 0;
        _currentTaxForTreasury = _fixedTaxForTreasury;
    }

    // if a tax exempt address is transfering we turn off all the taxes
    function _setNoFees() private {
        _currentTaxForReflections = 0;
        _currentTaxForTreasury = 0;
    }

    // once a transfer occurs we reset the taxes. this is strictly speaking
    // not necessary due to the construction of the transfer function which
    // will opinionated-ly always set the tax structure before performing
    // the math (in the functions below). however, for reasons of super-
    // stition it remains
    function _restoreAllFees() private {
        _currentTaxForReflections = _fixedTaxForReflections;
        _currentTaxForTreasury = _fixedTaxForTreasury;
    }

    // this function is the primary math function which calculates the
    // proper accounting to support a transfer based on the context of
    // that transfer (buy side; sell side; tax free).
    function _getValues(uint256 amountOfTokens)
        private
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        // given tokens split those out into what goes where (reflections,
        // treasury, and recipient)
        (
            uint256 tokensToTransfer,
            uint256 tokensForReflections,
            uint256 tokensForTreasury
        ) = _getTokenValues(amountOfTokens);

        // given the proper split of tokens, turn those into reflections
        // based on the current ratio of _tokenTokenSupply:_totalReflections
        uint256 currentRate = _getRate();
        uint256 reflectionsTotal = amountOfTokens.mul(currentRate);
        uint256 reflectionsToTransfer = tokensToTransfer.mul(currentRate);
        uint256 reflectionsToRemove = tokensForReflections.mul(currentRate);
        uint256 reflectionsForTreasury = tokensForTreasury.mul(currentRate);

        return (
            reflectionsTotal,
            reflectionsToTransfer,
            reflectionsToRemove,
            reflectionsForTreasury
        );
    }

    // the golden and necssary function that allows us to calculate the
    // ratio of total token supply to total reflections on which the
    // entire token accounting infrastructure resides
    function _getRate() private view returns (uint256) {
        return _totalReflections.div(_totalTokenSupply);
    }

    // the below function calculates where tokens needs to go based on the
    // inputted amount of tokens. n.b., this function does not work in
    // reflections, those typically happen later in the processing when the
    // token distribution calculated by this function is turned to reflections
    // based on the golden ratio of total token supply to total reflections.
    function _getTokenValues(uint256 amountOfTokens)
        private
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 tokensForReflections = amountOfTokens
            .mul(_currentTaxForReflections)
            .div(100);
        uint256 tokensForTreasury = amountOfTokens
            .mul(_currentTaxForTreasury)
            .div(100);
        uint256 tokensToTransfer = amountOfTokens.sub(tokensForReflections).sub(
            tokensForTreasury
        );
        return (tokensToTransfer, tokensForReflections, tokensForTreasury);
    }
}
