//SPDX-License-Identifier: MIT
pragma solidity 0.8.2;

import "./IStateUtils.sol";

interface IGetterUtils is IStateUtils {
    function balanceOfAt(
        address userAddress,
        uint256 _block
        )
        external
        view
        returns(uint256);

    function balanceOf(address userAddress)
        external
        view
        returns(uint256);

    function totalSupplyOneBlockAgo()
        external
        view
        returns(uint256);

    function totalSupply()
        external
        view
        returns(uint256);

    function userSharesAt(
        address userAddress,
        uint256 _block
        )
        external
        view
        returns(uint256);

    function userShares(address userAddress)
        external
        view
        returns(uint256);

    function userSharesAtWithBinarySearch(
        address userAddress,
        uint256 _block
        )
        external
        view
        returns(uint256);

    function userStake(address userAddress)
        external
        view
        returns(uint256);

    function userReceivedDelegationAt(
        address userAddress,
        uint256 _block
        )
        external
        view
        returns(uint256);

    function userReceivedDelegation(address userAddress)
        external
        view
        returns(uint256);

    function userDelegateAt(
        address userAddress,
        uint256 _block
        )
        external
        view
        returns(address);

    function userDelegate(address userAddress)
        external
        view
        returns(address);

    function getUserLocked(address userAddress)
        external
        view
        returns(uint256);
}
