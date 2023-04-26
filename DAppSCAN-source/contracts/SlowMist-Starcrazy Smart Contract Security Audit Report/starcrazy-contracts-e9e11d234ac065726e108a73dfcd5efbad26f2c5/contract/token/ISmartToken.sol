pragma solidity <0.6.0 >=0.4.21;

interface ISmartToken {
    function transferOwnership(address newOwner_) external;

    function acceptOwnership() external;

    function disableTransfers(bool disable_) external;

    function issue(address to_, uint256 amount_) external;
}
