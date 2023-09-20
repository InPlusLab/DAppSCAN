// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "../utils/OwnablePausable.sol";
import "./IDepositaryBalanceView.sol";

contract AgregateDepositaryBalanceView is IDepositaryBalanceView, OwnablePausable {
    using SafeMath for uint256;

    /// @notice The number of depositaries in agregate.
    uint256 public maxSize;

    /// @notice Decimals balance.
    uint256 public override decimals;

    /// @notice Depositaries in agregate.
    IDepositaryBalanceView[] public depositaries;

    /// @dev Depositaries index.
    mapping(address => uint256) internal depositariesIndex;

    /// @notice An event thats emitted when an new depositary added to agregate.
    event DepositaryAdded(address depositary);

    /// @notice An event thats emitted when an depositary removed from agregate.
    event DepositaryRemoved(address depositary);

    /**
     * @param _decimals Decimals balance.
     * @param _maxSize Max number depositaries in agregate.
     */
    constructor(uint256 _decimals, uint256 _maxSize) public {
        decimals = _decimals;
        maxSize = _maxSize;
    }

    /**
     * @return Depositaries count of agregate.
     */
    function size() public view returns (uint256) {
        return depositaries.length;
    }

    /**
     * @notice Add depositary address to agregate.
     * @param depositary Added depositary address.
     */
    //  SWC-135-Code With No Effects: L50 - L71
    function addDepositary(address depositary) external onlyOwner {
        require(depositariesIndex[depositary] == 0, "AgregateDepositaryBalanceView::addDepositary: depositary already added");
        require(size() < maxSize, "AgregateDepositaryBalanceView::addDepositary: too many depositaries");

        depositaries.push(IDepositaryBalanceView(depositary));
        depositariesIndex[depositary] = size().sub(1);
        emit DepositaryAdded(depositary);
    }

    /**
     * @notice Removed depositary address from agregate.
     * @param depositary Removed depositary address.
     */
    function removeDepositary(address depositary) external onlyOwner {
        uint256 depositaryIndex = depositariesIndex[depositary];
        require(depositaryIndex != 0, "AgregateDepositaryBalanceView::removeDepositary: depositary already removed");

        delete depositariesIndex[depositary];
        depositaries[depositaryIndex] = depositaries[size().sub(1)];
        delete depositaries[size().sub(1)];
        emit DepositaryRemoved(depositary);
    }

    /**
     * @return Allowed depositaries list.
     */
    function allowedDepositaries() external view returns (address[] memory) {
        address[] memory result = new address[](size());

        for (uint256 i = 0; i < size(); i++) {
            result[i] = address(depositaries[i]);
        }

        return result;
    }

    function balance() external view override returns (uint256) {
        uint256 result;

        for (uint256 i = 0; i < size(); i++) {
            uint256 depositaryBalance = depositaries[i].balance();
            uint256 depositaryDecimals = depositaries[i].decimals();
            uint256 decimalsPower = decimals.sub(depositaryDecimals);
            result = result.add(depositaryBalance.mul(10**decimalsPower));
        }

        return result;
    }
}
