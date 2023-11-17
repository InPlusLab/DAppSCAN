pragma solidity ^0.6.10;
import "@openzeppelin/contracts/GSN/Context.sol";

contract Ownable is Context {

    address payable public owner;
    address public dev;

    event TransferredOwnership(address _previous, address _next, uint256 _time);

    modifier onlyOwner() {
        require(_msgSender() == owner, "Owner only");
        _;
    }

    modifier onlyDev() {
        require(_msgSender() == dev, "Dev only");
        _;
    }

    constructor(address _dev) public {
        owner = _msgSender();
        dev = _dev;
    }

    function transferOwnership(address payable _owner) public onlyOwner() {
        address previousOwner = owner;
        owner = _owner;
        emit TransferredOwnership(previousOwner, owner, now);
    }

    function transferDev(address _dev) public onlyDev() {
        dev = _dev;
    }

}