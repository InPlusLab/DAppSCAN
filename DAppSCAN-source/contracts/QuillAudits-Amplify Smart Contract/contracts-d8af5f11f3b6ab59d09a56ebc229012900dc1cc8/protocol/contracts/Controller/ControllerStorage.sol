// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../InterestRate/InterestRateModel.sol";
import "../Asset/AssetInterface.sol";
import "../LossProvisionPool/LossProvisionInterface.sol";
import { IERC20 } from "../ERC20/IERC20.sol";

abstract contract ControllerStorage {
    uint256 public amptDepositAmount = 10e18;

    LossProvisionInterface public provisionPool;
    InterestRateModel public interestRateModel;
    IERC20 public amptToken;
    AssetInterface public assetsFactory;

    struct Borrower {
        uint256 debtCeiling;
        uint256 ratingMantissa;
        bool whitelisted;
        bool created;
    }
    mapping(address => Borrower) public borrowers;

    struct Application {
        address lender;
        uint256 depositAmount;
        uint256 mapIndex;
        bool created;
        bool whitelisted;
    }

    struct PoolInfo {
        address owner;
        bool isActive;
    }

    mapping(address => PoolInfo) public pools;
    mapping(address => mapping(address => Application)) internal poolApplicationsByLender;

    mapping(address => Application[]) public poolApplications;


    mapping(address => address[]) internal borrowerPools;
    mapping(address => address[]) internal lenderJoinedPools;
    mapping(address => mapping(address => bool)) internal lenderJoinedPoolsMap;
    mapping(address => mapping(address => bool)) public borrowerWhitelists;
}