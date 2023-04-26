pragma solidity 0.7.5;

interface IERC20Metadata {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}
