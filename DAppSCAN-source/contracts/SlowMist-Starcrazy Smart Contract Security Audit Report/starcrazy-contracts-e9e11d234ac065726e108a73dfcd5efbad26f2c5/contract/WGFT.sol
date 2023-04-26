pragma solidity ^0.5.0;

import "./math/SafeMath.sol";
import "./token/IERC20.sol";
import "./token/IERC223.sol";
import "./token/ISmartToken.sol";
import "./token/DSToken.sol";
import "./token/IApproveAndCallFallBack.sol";
import "./token/ITokenController.sol";
import "./token/IERC223Receiving.sol";

contract WGFT is
    DSToken("WGFT", "Wrapped Game Fantasy Token"),
    IERC223,
    ISmartToken
{
    using SafeMath for uint256;
    address private _newOwner;
    bool public _transfersEnabled = true; // true if transfer/transferFrom are enabled, false if not

    uint256 private _cap;

    address private _controller;

    // The Wrapped TOKEN
    IERC20 public wrappedToken;

    // allows execution only when transfers aren't disabled
    modifier transfersAllowed() {
        assert(_transfersEnabled);
        _;
    }

    constructor(IERC20 _wrappedToken) public {
        wrappedToken = _wrappedToken;
        _controller = msg.sender;
        uint256 perCoin = 1e18;
        _cap = perCoin.mul(3000 * 10000);
    }

    //////////
    // IOwned Methods
    //////////

    /**
        @dev allows transferring the contract ownership
        the new owner still needs to accept the transfer
        can only be called by the contract owner
        @param newOwner_    new contract owner
    */
    function transferOwnership(address newOwner_) public auth {
        require(newOwner_ != _owner, "WGFT-already-an-owner");
        _newOwner = newOwner_;
    }

    /**
        @dev used by a new owner to accept an ownership transfer
    */
    function acceptOwnership() public {
        require(msg.sender == _newOwner, "WGFT-not-new-owner");
        _owner = _newOwner;
        _newOwner = address(0);
    }

    //////////
    // SmartToken Methods
    //////////
    /**
        @dev disables/enables transfers
        can only be called by the contract owner
        @param disable_    true to disable transfers, false to enable them
    */
    function disableTransfers(bool disable_) public auth {
        _transfersEnabled = !disable_;
    }

    function issue(address to_, uint256 amount_) public auth stoppable {
        mint(to_, amount_);
    }

    //////////
    // Cap Methods
    //////////
    function cap() public view returns (uint256) {
        return _cap;
    }

    //////////
    // Cap Methods
    //////////
    function changeCap(uint256 newCap_) public auth {
        require(newCap_ >= totalSupply());

        _cap = newCap_;
    }

    //////////
    // Controller Methods
    //////////
    /// @notice Changes the _controller of the contract
    /// @param newController_ The new _controller of the contract
    function changeController(address newController_) public auth {
        _controller = newController_;
    }

    /// @notice Send `amount_` tokens to `to_` from `from_` on the condition it
    ///  is approved by `from_`
    /// @param from_ The address holding the tokens being transferred
    /// @param to_ The address of the recipient
    /// @param amount_ The amount of tokens to be transferred
    /// @return True if the transfer was successful
    function transferFrom(
        address from_,
        address to_,
        uint256 amount_
    ) public transfersAllowed returns (bool success) {
        // Alerts the token _controller of the transfer
        if (isContract(_controller)) {
            if (!ITokenController(_controller).onTransfer(from_, to_, amount_))
                revert();
        }

        success = super.transferFrom(from_, to_, amount_);
    }

    /*
     * ERC 223
     * Added support for the ERC 223 "tokenFallback" method in a "transfer" function with a payload.
     */
    function transferFrom(
        address from_,
        address to_,
        uint256 amount_,
        bytes memory data_
    ) public transfersAllowed returns (bool success) {
        // Alerts the token _controller of the transfer
        if (isContract(_controller)) {
            if (!ITokenController(_controller).onTransfer(from_, to_, amount_))
                revert();
        }

        require(
            super.transferFrom(from_, to_, amount_),
            "WGFT-insufficient-balance"
        );

        if (isContract(to_)) {
            IERC223Receiving receiver = IERC223Receiving(to_);
            receiver.tokenFallback(from_, amount_, data_);
        }

        emit ERC223Transfer(from_, to_, amount_, data_);

        return true;
    }

    /*
     * ERC 223
     * Added support for the ERC 223 "tokenFallback" method in a "transfer" function with a payload.
     * https://github.com/ethereum/EIPs/issues/223
     * function transfer(address to_, uint256 value_, bytes memory data_) public returns (bool success);
     */
    /// @notice Send `value_` tokens to `to_` from `msg.sender` and trigger
    /// tokenFallback if sender is a contract.
    /// @dev Function that is called when a user or another contract wants to transfer funds.
    /// @param to_ Address of token receiver.
    /// @param amount_ Number of tokens to transfer.
    /// @param data_ Data to be sent to tokenFallback
    /// @return Returns success of function call.
    function transfer(
        address to_,
        uint256 amount_,
        bytes memory data_
    ) public returns (bool success) {
        return transferFrom(msg.sender, to_, amount_, data_);
    }

    /// @notice `msg.sender` approves `spender_` to spend `amount_` tokens on
    ///  its behalf. This is a modified version of the ERC20 approve function
    ///  to be a little bit safer
    /// @param spender_ The address of the account able to transfer the tokens
    /// @param amount_ The amount of tokens to be approved for transfer
    /// @return True if the approval was successful
    function approve(address spender_, uint256 amount_)
        public
        returns (bool success)
    {
        // Alerts the token _controller of the approve function call
        if (isContract(_controller)) {
            if (
                !ITokenController(_controller).onApprove(
                    msg.sender,
                    spender_,
                    amount_
                )
            ) revert();
        }

        return super.approve(spender_, amount_);
    }

    function mint(address guy_, uint256 wad_) public auth stoppable {
        require(totalSupply().add(wad_) <= _cap, "WGFT-insufficient-cap");

        super.mint(guy_, wad_);

        emit Transfer(address(0), guy_, wad_);
    }

    function burn(address guy_, uint256 wad_) public auth stoppable {
        super.burn(guy_, wad_);

        emit Transfer(guy_, address(0), wad_);
    }

    /// @notice `msg.sender` approves `spender_` to send `amount_` tokens on
    ///  its behalf, and then a function is triggered in the contract that is
    ///  being approved, `spender_`. This allows users to use their tokens to
    ///  interact with contracts in one function call instead of two
    /// @param spender_ The address of the contract able to transfer the tokens
    /// @param amount_ The amount of tokens to be approved for transfer
    /// @return True if the function call was successful
    function approveAndCall(
        address spender_,
        uint256 amount_,
        bytes memory extraData_
    ) public returns (bool success) {
        if (!approve(spender_, amount_)) revert();

        IApproveAndCallFallBack(spender_).receiveApproval(
            msg.sender,
            amount_,
            address(this),
            extraData_
        );

        return true;
    }

    /// @dev Internal function to determine if an address is a contract
    /// @param addr_ The address being queried
    /// @return True if `addr_` is a contract
    function isContract(address addr_) internal view returns (bool) {
        uint256 size;
        if (addr_ == address(0)) return false;
        assembly {
            size := extcodesize(addr_)
        }
        return size > 0;
    }

    /// @notice The fallback function: If the contract's _controller has not been
    ///  set to 0, then the `proxyPayment` method is called which relays the
    ///  ether and creates tokens as described in the token _controller contract
    function() external payable {
        if (isContract(_controller)) {
            if (
                !ITokenController(_controller).proxyPayment.value(msg.value)(
                    msg.sender,
                    msg.sig,
                    msg.data
                )
            ) revert();
        } else {
            revert();
        }
    }

    //////////
    // Safety Methods
    //////////

    /// @notice This method can be used by the owner to extract mistakenly
    ///  sent tokens to this contract.
    /// @param token_ The address of the token contract that you want to recover
    ///  set to 0 in case you want to extract ether.
    function claimTokens(address token_) public auth {
        if (token_ == address(0)) {
            address(msg.sender).transfer(address(this).balance);
            return;
        }

        IERC20 token = IERC20(token_);
        uint256 balance = token.balanceOf(address(this));
        token.transfer(address(msg.sender), balance);

        emit ClaimedTokens(token_, address(msg.sender), balance);
    }

    function withdrawTokens(
        IERC20 token_,
        address to_,
        uint256 amount_
    ) public auth {
        assert(token_.transfer(to_, amount_));
    }

    ////////////////
    // Events
    ////////////////

    event ClaimedTokens(
        address indexed token_,
        address indexed controller_,
        uint256 amount_
    );

    event ReceiveApproval(
        address _sender,
        uint256 _value,
        address _tokenContract,
        bytes _extraData,
        uint256 action
    );

    function receiveApproval(
        address _sender,
        uint256 _value,
        address _tokenContract,
        bytes memory _extraData
    ) public {
        require(_value > 0, "approval zero");
        uint256 action;
        assembly {
            action := mload(add(_extraData, 0x20))
        }
        emit ReceiveApproval(
            _sender,
            _value,
            _tokenContract,
            _extraData,
            action
        );
        require(action == 5, "unknow action");
        if (action == 5) {
            // swapFrom
            require(
                _tokenContract == address(wrappedToken),
                "approval and want deposit, but used token isn't GFT"
            );
            uint256 amount;
            assembly {
                amount := mload(add(_extraData, 0x40))
            }
            _swapFrom(_sender, amount);
        }
    }

    function _swapBurn(address guy, uint256 wad) private stoppable {
        if (guy != msg.sender && _allowances[guy][msg.sender] != uint256(-1)) {
            require(
                _allowances[guy][msg.sender] >= wad,
                "ds-token-insufficient-approval"
            );
            _allowances[guy][msg.sender] = _allowances[guy][msg.sender].sub(
                wad
            );
        }

        require(_balances[guy] >= wad, "ds-token-insufficient-balance");
        _balances[guy] = _balances[guy].sub(wad);
        _totalSupply = _totalSupply.sub(wad);
        emit Burn(guy, wad);
        emit Transfer(guy, address(0), wad);
    }

    function _swapMint(address guy, uint256 wad) private stoppable {
        require(totalSupply().add(wad) <= _cap, "WGFT-insufficient-cap");

        _balances[guy] = _balances[guy].add(wad);
        _totalSupply = _totalSupply.add(wad);
        emit Mint(guy, wad);
        emit Transfer(address(0), guy, wad);
    }

    function swapTo(uint256 _amount) external stoppable {
        _swapTo(msg.sender, _amount);
    }

    function _swapTo(address _from, uint256 _amount) internal stoppable {
        _swapBurn(_from, _amount);
        wrappedToken.transferFrom(address(this), msg.sender, _amount);
    }

    function swapFrom(uint256 _amount) external stoppable {
        _swapFrom(msg.sender, _amount);
    }

    function _swapFrom(address _from, uint256 _amount) internal stoppable {
        wrappedToken.transferFrom(msg.sender, address(this), _amount);
        _swapMint(_from, _amount);
    }
}
