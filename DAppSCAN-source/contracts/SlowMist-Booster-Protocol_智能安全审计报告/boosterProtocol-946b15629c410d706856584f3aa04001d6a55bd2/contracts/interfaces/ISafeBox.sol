// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISafeBox {

    function bank() external view returns(address);

    function token() external view returns(address);

    function getSource() external view returns (string memory);

    function supplyRatePerBlock() external view returns (uint256);
    function borrowRatePerBlock() external view returns (uint256);

    function getBorrowInfo(uint256 _bid) external view 
            returns (address owner, uint256 amount, address strategy, uint256 pid);
    function getBorrowId(address _strategy, uint256 _pid, address _account) external view returns (uint256 borrowId);
    function getBorrowId(address _strategy, uint256 _pid, address _account, bool _add) external returns (uint256 borrowId);
    function getDepositTotal() external view returns (uint256);
    function getBorrowTotal() external view returns (uint256);
    function getBorrowAmount(address _account) external view returns (uint256 value); 
    function getBaseTokenPerLPToken() external view returns (uint256);

    function deposit(uint256 _value) external;
    function withdraw(uint256 _value) external;
    
    function emergencyWithdraw() external;
    function emergencyRepay(uint256 _bid, uint256 _value) external;

    function borrowInfoLength() external view returns (uint256);

    function borrow(uint256 _bid, uint256 _value, address _to) external;
    function repay(uint256 _bid, uint256 _value) external;
    function claim(uint256 _tTokenAmount) external;

    function update() external;
    function mintDonate(uint256 _value) external;

    function pendingSupplyAmount(address _account) external view returns (uint256 value);   
    function pendingBorrowAmount(uint256 _bid) external view returns (uint256 value);
    function pendingBorrowRewards(uint256 _bid) external view returns (uint256 value);
}