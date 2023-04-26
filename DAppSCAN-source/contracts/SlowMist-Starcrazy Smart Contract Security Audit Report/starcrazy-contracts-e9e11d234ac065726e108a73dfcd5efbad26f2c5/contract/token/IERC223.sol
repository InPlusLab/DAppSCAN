pragma solidity <0.6.0 >=0.4.21;

interface IERC223 {
    function transfer(
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bool ok);

    function transferFrom(
        address from,
        address to,
        uint256 amount,
        bytes calldata data
    ) external returns (bool ok);

    event ERC223Transfer(
        address indexed from,
        address indexed to,
        uint256 amount,
        bytes data
    );
}
