pragma solidity ^0.5.16;
import "./Utils/SafeBEP20.sol";
import "./Utils/IBEP20.sol";

contract AtlantisStore {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    /// @notice The Admin Address
    address public admin;

    /// @notice The Owner Address
    address public owner;

    /// @notice The Atlantis Address
    IBEP20 public atlantis;

    /// @notice Event emitted when admin changed
    event AdminTransferred(address indexed oldAdmin, address indexed newAdmin);

    /// @notice Event emitted when owner changed
    event OwnerTransferred(address indexed oldOwner, address indexed newOwner);

    constructor(address atlantis_) public {
        admin = msg.sender;
        atlantis = IBEP20(atlantis_);
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin can");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "only owner can");
        _;
    }

    function setNewAdmin(address _admin) public onlyAdmin {
        require(_admin != address(0), "new admin is the zero address");
        address oldAdmin = admin;
        admin = _admin;
        emit AdminTransferred(oldAdmin, _admin);
    }

    function setNewOwner(address _owner) public onlyAdmin {
        require(_owner != address(0), "new owner is the zero address");
        address oldOwner = owner;
        owner = _owner;
        emit OwnerTransferred(oldOwner, _owner);
    }

    // Safe reward token transfer function, just in case if rounding error causes pool to not have enough tokens.
    function safeAtlantisTransfer(address _to, uint256 _amount) public onlyOwner {
        uint256 tokenBalance = atlantis.balanceOf(address(this));
        if (_amount > tokenBalance) {
            atlantis.transfer(_to, tokenBalance);
        } else {
            atlantis.transfer(_to, _amount);
        }
    }

    function atlantisBalance() public view returns (uint256) {
        uint256 atlantisBalance = atlantis.balanceOf(address(this));
        return atlantisBalance;
    }

    function emergencyRewardWithdraw(uint256 _amount) external onlyOwner {
        atlantis.transfer(address(msg.sender), _amount);
    }
}
