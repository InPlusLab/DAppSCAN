// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./TokenVesting.sol";

contract VestingController is Ownable {
    using SafeERC20 for IERC20;

    uint256 constant countMintDay = 2; // count day afer create contract when can mint locked token

    event Vesting(address VestingContract, address Beneficiary);

    modifier vestTime() {
        require(_timestampCreated + (1 days) * countMintDay >= block.timestamp, "mint time was finished");
        _;
    }

    IERC20 blid;

    /**
     * @return The start timestamp day when create contract
     */
    function timestampCreated() public view returns (uint256) {
        return _timestampCreated;
    }

    uint256 _timestampCreated;

    /**
     * @notice Constuctor save time create and owner this contract
     */
    constructor() {
        _timestampCreated = block.timestamp;
        transferOwnership(msg.sender);
    }

    /**
     * @notice Set token for vesting
     */
    function addBLID(address token) external vestTime onlyOwner {
        blid = IERC20(token);
    }

    /**
     * @notice Deploy TokenVesting with this parameters, and transfer amount blid to TokenVesting
     */
    function vest(
        address account,
        uint256 amount,
        uint256 startTimestamp,
        uint256 duration,
        uint256 durationCount
    ) external vestTime onlyOwner {
        require(blid.balanceOf(address(this)) > amount, "VestingController: vest amount exceeds balance");
        TokenVesting vesting = new TokenVesting(
            address(blid),
            account,
            startTimestamp,
            duration,
            durationCount
        );
        blid.safeTransfer(address(vesting), amount);
        emit Vesting(address(vesting), account);
    }
}
