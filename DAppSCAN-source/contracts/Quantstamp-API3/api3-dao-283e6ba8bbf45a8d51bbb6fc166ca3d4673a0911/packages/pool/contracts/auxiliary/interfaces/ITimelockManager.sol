//SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


interface ITimelockManager {
    event Api3PoolUpdated(address api3PoolAddress);

    event RevertedTimelock(
        address indexed recipient,
        address destination,
        uint256 amount
        );

    event PermittedTimelockToBeReverted(address recipient);

    event TransferredAndLocked(
        address source,
        address indexed recipient,
        uint256 amount,
        uint256 releaseStart,
        uint256 releaseEnd
        );

    event Withdrawn(
        address indexed recipient,
        uint256 amount
        );

    event WithdrawnToPool(
        address indexed recipient,
        address api3PoolAddress,
        address beneficiary
        );

    function updateApi3Pool(address api3PoolAddress)
        external;

    function revertTimelock(
        address recipient,
        address destination
        )
        external;

    function permitTimelockToBeReverted()
        external;

    function transferAndLock(
        address source,
        address recipient,
        uint256 amount,
        uint256 releaseStart,
        uint256 releaseEnd
        )
        external;

    function transferAndLockMultiple(
        address source,
        address[] calldata recipients,
        uint256[] calldata amounts,
        uint256[] calldata releaseStarts,
        uint256[] calldata releaseEnds
        )
        external;

    function withdraw()
        external;

    function withdrawToPool(
        address api3PoolAddress,
        address beneficiary
        )
        external;

    function getWithdrawable(address recipient)
        external
        view
        returns(uint256 withdrawable);

    function getTimelock(address recipient)
        external
        view
        returns (
            uint256 totalAmount,
            uint256 remainingAmount,
            uint256 releaseStart,
            uint256 releaseEnd
            );

    function getRemainingAmount(address recipient)
        external
        view
        returns (uint256 remainingAmount);

    function getIfTimelockIsRevertible(address recipient)
        external
        view
        returns (bool revertStatus);
}
