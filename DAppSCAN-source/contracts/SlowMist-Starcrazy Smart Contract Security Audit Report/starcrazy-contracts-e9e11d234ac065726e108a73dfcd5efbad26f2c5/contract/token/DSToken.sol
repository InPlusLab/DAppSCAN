pragma solidity ^0.5.0;

import "../math/SafeMath.sol";
import "../ownership/DSAuth.sol";

contract DSToken is DSAuth {
    using SafeMath for uint256;
    bool public _stopped;
    uint256 internal _totalSupply;
    mapping(address => uint256) internal _balances;
    mapping(address => mapping(address => uint256)) internal _allowances;
    string private _name;
    string private _symbol;

    constructor(string memory symbol_, string memory name_) public {
        _symbol = symbol_;
        _name = name_;
    }

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Mint(address indexed guy, uint256 wad);
    event Burn(address indexed guy, uint256 wad);
    event Stop();
    event Start();

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view returns (uint256) {
        require(
            account != address(0),
            "ERC721: balance query for the zero address"
        );
        return _balances[account];
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender)
        public
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    modifier stoppable {
        require(!_stopped, "ds-stop-is-stopped");
        _;
    }

    function approve(address guy) external returns (bool) {
        return approve(guy, uint256(-1));
    }

    function approve(address guy, uint256 wad) public stoppable returns (bool) {
        require(guy != address(0), "ERC20: approve to the zero address");

        _allowances[msg.sender][guy] = wad;

        emit Approval(msg.sender, guy, wad);

        return true;
    }

    function transfer(address dst, uint256 wad) external returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(
        address src,
        address dst,
        uint256 wad
    ) public stoppable returns (bool) {
        if (src != msg.sender && _allowances[src][msg.sender] != uint256(-1)) {
            require(
                _allowances[src][msg.sender] >= wad,
                "ds-token-insufficient-approval"
            );
            _allowances[src][msg.sender] = _allowances[src][msg.sender].sub(
                wad
            );
        }

        require(_balances[src] >= wad, "ds-token-insufficient-balance");
        _balances[src] = _balances[src].sub(wad);
        _balances[dst] = _balances[dst].add(wad);

        emit Transfer(src, dst, wad);

        return true;
    }

    function push(address dst, uint256 wad) external {
        transferFrom(msg.sender, dst, wad);
    }

    function pull(address src, uint256 wad) external {
        transferFrom(src, msg.sender, wad);
    }

    function move(
        address src,
        address dst,
        uint256 wad
    ) external {
        transferFrom(src, dst, wad);
    }

    function mint(uint256 wad) external {
        mint(msg.sender, wad);
    }

    function burn(uint256 wad) external {
        burn(msg.sender, wad);
    }

    function mint(address guy, uint256 wad) public auth stoppable {
        _balances[guy] = _balances[guy].add(wad);
        _totalSupply = _totalSupply.add(wad);
        emit Mint(guy, wad);
    }

    function burn(address guy, uint256 wad) public auth stoppable {
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
    }

    function destroy(address from_, uint256 amount_) public auth stoppable {
        // do not require allowance

        require(_balances[from_] >= amount_, "ds-token-insufficient-balance");
        _balances[from_] = _balances[from_].sub(amount_);
        _totalSupply = _totalSupply.sub(amount_);
        emit Burn(from_, amount_);
        emit Transfer(from_, address(0), amount_);
    }

    function dsStop() public auth {
        _stopped = true;
        emit Stop();
    }

    function start() public auth {
        _stopped = false;
        emit Start();
    }
}
