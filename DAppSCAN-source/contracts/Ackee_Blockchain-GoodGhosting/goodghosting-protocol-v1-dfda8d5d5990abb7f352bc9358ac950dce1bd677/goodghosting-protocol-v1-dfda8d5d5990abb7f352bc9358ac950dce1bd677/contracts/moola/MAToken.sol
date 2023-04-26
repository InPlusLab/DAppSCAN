pragma solidity 0.6.11;

interface MAToken {
    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    function redeem(uint256 _amount) external;

}
