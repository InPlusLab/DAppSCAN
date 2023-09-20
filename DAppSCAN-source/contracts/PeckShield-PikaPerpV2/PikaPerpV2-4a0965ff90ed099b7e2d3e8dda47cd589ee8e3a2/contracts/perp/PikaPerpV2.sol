// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/math/SignedSafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../oracle/IOracle.sol";
import '../lib/UniERC20.sol';
import './IPikaPerp.sol';
import "../staking/IVaultReward.sol";

contract PikaPerpV2 is ReentrancyGuard {
    using SafeMath for uint256;
    using SignedSafeMath for int256;
    using SafeERC20 for IERC20;
    using UniERC20 for IERC20;
    // All amounts are stored with 8 decimals

    // Structs

    struct Vault {
        // 32 bytes
        uint96 cap; // Maximum capacity. 12 bytes
        uint96 balance; // 12 bytes
        uint64 staked; // Total staked by users. 8 bytes
        uint64 shares; // Total ownership shares. 8 bytes
        // 32 bytes
        uint32 stakingPeriod; // Time required to lock stake (seconds). 4 bytes
    }

    struct Stake {
        // 32 bytes
        address owner; // 20 bytes
        uint64 amount; // 8 bytes
        uint64 shares; // 8 bytes
        uint32 timestamp; // 4 bytes
    }

    struct Product {
        // 32 bytes
        address feed; // Chainlink feed. 20 bytes
        uint72 maxLeverage; // 9 bytes
        uint16 fee; // In bps. 0.5% = 50. 2 bytes
        bool isActive; // 1 byte
        // 32 bytes
        uint64 openInterestLong; // 6 bytes
        uint64 openInterestShort; // 6 bytes
        uint16 interest; // For 360 days, in bps. 10% = 1000. 2 bytes
        uint16 liquidationThreshold; // In bps. 8000 = 80%. 2 bytes
        uint16 liquidationBounty; // In bps. 500 = 5%. 2 bytes
        uint16 minPriceChange; // 1.5%, the minimum oracle price up change for trader to close trade with profit
        uint16 weight; // share of the max exposure
        uint64 reserve; // Virtual reserve in USDC. Used to calculate slippage
    }

    struct Position {
        // 32 bytes
        uint64 productId; // 8 bytes
        uint64 leverage; // 8 bytes
        uint64 price; // 8 bytes
        uint64 oraclePrice; // 8 bytes
        uint64 margin; // 8 bytes
        // 32 bytes
        address owner; // 20 bytes
        uint80 timestamp; // 10 bytes
        bool isLong; // 1 byte
    }

    // Variables

    address public owner; // Contract owner
    address public liquidator;
    address public token;
    uint256 public tokenDecimal;
    uint256 public tokenBase;
    address public oracle;
    uint256 public minMargin;
    uint256 public nextStakeId; // Incremental
    uint256 public protocolRewardRatio = 2000;  // 20%
    uint256 public pikaRewardRatio = 3000;  // 30%
    uint256 public maxShift = 0.003e8; // max shift (shift is used adjust the price to balance the longs and shorts)
    uint256 public minProfitTime = 12 hours; // the time window where minProfit is effective
    uint256 public maxPositionMargin; // for guarded launch
    uint256 public totalWeight; // total exposure weights of all product
    uint256 public exposureMultiplier = 10000; // exposure multiplier
    uint256 public utilizationMultiplier = 10000; // exposure multiplier
    uint256 public pendingProtocolReward; // protocol reward collected
    uint256 public pendingPikaReward; // pika reward collected
    uint256 public pendingVaultReward; // vault reward collected
    address public protocolRewardDistributor;
    address public pikaRewardDistributor;
    address public vaultRewardDistributor;
    address public vaultTokenReward;
    uint256 public totalOpenInterest;
    uint256 public constant BASE_DECIMALS = 8;
    uint256 public constant BASE = 10**BASE_DECIMALS;
    bool canUserStake = false;
    bool allowPublicLiquidator = false;
    Vault private vault;

    mapping(uint256 => Product) private products;
    mapping(address => Stake) private stakes;
    mapping(uint256 => Position) private positions;

    // Events

    event Staked(
        address indexed user,
        uint256 amount,
        uint256 shares
    );
    event Redeemed(
        address indexed user,
        uint256 amount,
        uint256 shares,
        uint256 shareBalance,
        bool isFullRedeem
    );
    event NewPosition(
        uint256 indexed positionId,
        address indexed user,
        uint256 indexed productId,
        bool isLong,
        uint256 price,
        uint256 oraclePrice,
        uint256 margin,
        uint256 leverage,
        uint256 fee
    );

    event AddMargin(
        uint256 indexed positionId,
        address indexed user,
        uint256 margin,
        uint256 newMargin,
        uint256 newLeverage
    );
    event ClosePosition(
        uint256 indexed positionId,
        address indexed user,
        uint256 indexed productId,
        uint256 price,
        uint256 entryPrice,
        uint256 margin,
        uint256 leverage,
        uint256 fee,
        int256 pnl,
        bool wasLiquidated
    );
    event PositionLiquidated(
        uint256 indexed positionId,
        address indexed liquidator,
        uint256 liquidatorReward,
        uint256 remainingReward
    );
    event ProtocolRewardDistributed(
        address to,
        uint256 amount
    );
    event PikaRewardDistributed(
        address to,
        uint256 amount
    );
    event VaultRewardDistributed(
        address to,
        uint256 amount
    );
    event VaultUpdated(
        Vault vault
    );
    event ProductAdded(
        uint256 productId,
        Product product
    );
    event ProductUpdated(
        uint256 productId,
        Product product
    );
    event ProtocolRewardRatioUpdated(
        uint256 protocolRewardRatio
    );
    event PikaRewardRatioUpdated(
        uint256 pikaRewardRatio
    );
    event OracleUpdated(
        address newOracle
    );
    event OwnerUpdated(
        address newOwner
    );

    // Constructor

    constructor(address _token, uint256 _tokenDecimal, address _oracle, uint256 _minMargin) {
        owner = msg.sender;
        liquidator = msg.sender;
        token = _token;
        tokenDecimal = _tokenDecimal;
        tokenBase = 10**_tokenDecimal;
        oracle = _oracle;
        minMargin = _minMargin;
        vault = Vault({
        cap: 0,
        balance: 0,
        staked: 0,
        shares: 0,
        stakingPeriod: uint32(24 * 3600)
        });
    }

    // Methods

    // Stakes amount of usdc in the vault
    function stake(uint256 amount) external payable nonReentrant {
        require(canUserStake || msg.sender == owner, "!stake");
        address user = msg.sender;
        IVaultReward(vaultRewardDistributor).updateReward(user);
        IVaultReward(vaultTokenReward).updateReward(user);
        IERC20(token).uniTransferFromSenderToThis(amount.mul(tokenBase).div(BASE));
        require(amount >= minMargin, "!margin");
        require(uint256(vault.staked) + amount <= uint256(vault.cap), "!cap");
        uint256 shares = vault.staked > 0 ? amount.mul(uint256(vault.shares)).div(uint256(vault.balance)) : amount;
        vault.balance += uint96(amount);
        vault.staked += uint64(amount);
        vault.shares += uint64(shares);

        if (stakes[user].amount == 0) {
            stakes[user] = Stake({
            owner: user,
            amount: uint64(amount),
            shares: uint64(shares),
            timestamp: uint32(block.timestamp)
            });
        } else {
            stakes[user].amount += uint64(amount);
            stakes[user].shares += uint64(shares);
            stakes[user].timestamp = uint32(block.timestamp);
        }

        emit Staked(
            user,
            amount,
            shares
        );

    }

    // Redeems amount from Stake with id = stakeId
    function redeem(
        uint256 shares
    ) external {

        require(shares <= uint256(vault.shares), "!staked");

        address user = msg.sender;
        IVaultReward(vaultRewardDistributor).updateReward(user);
        IVaultReward(vaultTokenReward).updateReward(user);
        Stake storage _stake = stakes[user];
        bool isFullRedeem = shares >= uint256(_stake.shares);
        if (isFullRedeem) {
            shares = uint256(_stake.shares);
        }

        if (user != owner) {
            uint256 timeDiff = block.timestamp.sub(uint256(_stake.timestamp));
            require(timeDiff > uint256(vault.stakingPeriod), "!period");
        }

        uint256 shareBalance = shares.mul(uint256(vault.balance)).div(uint256(vault.shares));

        uint256 amount = shares.mul(_stake.amount).div(uint256(_stake.shares));

        _stake.amount -= uint64(amount);
        _stake.shares -= uint64(shares);
        vault.staked -= uint64(amount);
        vault.shares -= uint64(shares);
        vault.balance -= uint96(shareBalance);

        require(totalOpenInterest <= uint256(vault.balance).mul(utilizationMultiplier).div(10**4), "!utilized");

        if (isFullRedeem) {
            delete stakes[user];
        }
        IERC20(token).uniTransfer(user, shareBalance.mul(tokenBase).div(BASE));

        emit Redeemed(
            user,
            amount,
            shares,
            shareBalance,
            isFullRedeem
        );
    }

    // Opens position with margin = msg.value
    function openPosition(
        uint256 productId,
        uint256 margin,
        bool isLong,
        uint256 leverage
    ) external payable nonReentrant returns(uint256 positionId) {
        // Check params
        require(margin >= minMargin, "!margin");
        require(leverage >= 1 * BASE, "!leverage");

        // Check product
        Product storage product = products[productId];
        require(product.isActive, "!product-active");
        require(leverage <= uint256(product.maxLeverage), "!max-leverage");

        // Transfer margin plus fee
        uint256 tradeFee = _getTradeFee(margin, leverage, uint256(product.fee));
        IERC20(token).uniTransferFromSenderToThis((margin.add(tradeFee)).mul(tokenBase).div(BASE));
        pendingProtocolReward = pendingProtocolReward.add(tradeFee.mul(protocolRewardRatio).div(10**4));
        pendingPikaReward = pendingPikaReward.add(tradeFee.mul(pikaRewardRatio).div(10**4));
        pendingVaultReward = pendingVaultReward.add(tradeFee.mul(10**4 - protocolRewardRatio - pikaRewardRatio).div(10**4));

        // Check exposure
        uint256 amount = margin.mul(leverage).div(BASE);
        uint256 price = _calculatePrice(product.feed, isLong, product.openInterestLong,
            product.openInterestShort, uint256(vault.balance).mul(uint256(product.weight)).div(uint256(totalWeight)),
            uint256(product.reserve), amount);

        _updateOpenInterest(productId, amount, isLong, true);

        positionId = getPositionId(msg.sender, productId, isLong);
        Position storage position = positions[positionId];
        if (position.margin > 0) {
            price = (uint256(position.margin).mul(position.leverage).mul(uint256(position.price)).add(margin.mul(leverage).mul(price))).div(
                uint256(position.margin).mul(position.leverage).add(margin.mul(leverage)));
            leverage = (uint256(position.margin).mul(uint256(position.leverage)).add(margin.mul(leverage))).div(uint256(position.margin).add(margin));
            margin = uint256(position.margin).add(margin);
        }
        require(margin < maxPositionMargin, "!max margin");

        positions[positionId] = Position({
        owner: msg.sender,
        productId: uint64(productId),
        margin: uint64(margin),
        leverage: uint64(leverage),
        price: uint64(price),
        oraclePrice: uint64(IOracle(oracle).getPrice(product.feed)),
        timestamp: uint80(block.timestamp),
        isLong: isLong
        });
        emit NewPosition(
            positionId,
            msg.sender,
            productId,
            isLong,
            price,
            IOracle(oracle).getPrice(product.feed),
            margin,
            leverage,
            tradeFee
        );
    }

    // Add margin to Position with positionId
    function addMargin(uint256 positionId, uint256 margin) external payable nonReentrant {

        IERC20(token).uniTransferFromSenderToThis(margin.mul(tokenBase).div(BASE));

        // Check params
        require(margin >= minMargin, "!margin");

        // Check position
        Position storage position = positions[positionId];
        require(msg.sender == position.owner, "!owner");

        // New position params
        uint256 newMargin = uint256(position.margin).add(margin);
        uint256 newLeverage = uint256(position.leverage).mul(uint256(position.margin)).div(newMargin);
        require(newLeverage >= 1 * BASE, "!low-leverage");

        position.margin = uint64(newMargin);
        position.leverage = uint64(newLeverage);

        emit AddMargin(
            positionId,
            position.owner,
            margin,
            newMargin,
            newLeverage
        );

    }

    // Closes margin from Position with productId and direction
    function closePosition(
        uint256 productId,
        uint256 margin,
        bool isLong
    ) external {
        return closePositionWithId(getPositionId(msg.sender, productId, isLong), margin);
    }

    // Closes position from Position with id = positionId
    //SWC-107-Reentrancy: L402-359
    function closePositionWithId(
        uint256 positionId,
        uint256 margin
    ) public {
        // Check params
        require(margin >= minMargin, "!margin");

        // Check position
        Position storage position = positions[positionId];
        require(msg.sender == position.owner, "!owner");

        // Check product
        Product storage product = products[uint256(position.productId)];

        bool isFullClose;
        if (margin >= uint256(position.margin)) {
            margin = uint256(position.margin);
            isFullClose = true;
        }
        uint256 maxExposure = uint256(vault.balance).mul(uint256(product.weight)).mul(exposureMultiplier).div(uint256(totalWeight)).div(10**4);
        uint256 price = _calculatePrice(product.feed, !position.isLong, product.openInterestLong, product.openInterestShort,
            maxExposure, uint256(product.reserve), margin * position.leverage / 10**8);

        bool isLiquidatable;
        int256 pnl = _getPnl(position, margin, price);
        if (pnl < 0 && uint256(-1 * pnl) >= margin.mul(uint256(product.liquidationThreshold)).div(10**4)) {
            margin = uint256(position.margin);
            pnl = -1 * int256(uint256(position.margin));
            isLiquidatable = true;
        } else {
            // front running protection: if oracle price up change is smaller than threshold and minProfitTime has not passed, the pnl is be set to 0
            if (pnl > 0 && !_canTakeProfit(position, IOracle(oracle).getPrice(product.feed), product.minPriceChange)) {
                pnl = 0;
            }
        }

        uint256 totalFee = _updateVaultAndGetFee(pnl, position, margin, uint256(product.fee), uint256(product.interest));
        _updateOpenInterest(uint256(position.productId), margin.mul(uint256(position.leverage)).div(BASE), position.isLong, false);

        emit ClosePosition(
            positionId,
            position.owner,
            uint256(position.productId),
            price,
            uint256(position.price),
            margin,
            uint256(position.leverage),
            totalFee,
            pnl,
            isLiquidatable
        );

        if (isFullClose) {
            delete positions[positionId];
        } else {
            position.margin -= uint64(margin);
        }
    }

    function _updateVaultAndGetFee(
        int256 pnl,
        Position memory position,
        uint256 margin,
        uint256 fee,
        uint256 interest
    ) internal returns(uint256) {

        (int256 pnlAfterFee, uint256 totalFee) = _getPnlWithFee(pnl, position, margin, fee, interest);
        // Update vault
        if (pnlAfterFee < 0) {
            uint256 _pnlAfterFee = uint256(-1 * pnlAfterFee);
            if (_pnlAfterFee < margin) {
                IERC20(token).uniTransfer(position.owner, (margin.sub(_pnlAfterFee)).mul(tokenBase).div(BASE));
                vault.balance += uint96(_pnlAfterFee);
            } else {
                vault.balance += uint96(margin);
                return totalFee;
            }

        } else {
            uint256 _pnlAfterFee = uint256(pnlAfterFee);
            // Check vault
            require(uint256(vault.balance) >= _pnlAfterFee, "!vault-insufficient");
            vault.balance -= uint96(_pnlAfterFee);

            IERC20(token).uniTransfer(position.owner, (margin.add(_pnlAfterFee)).mul(tokenBase).div(BASE));
        }

        pendingProtocolReward = pendingProtocolReward.add(totalFee.mul(protocolRewardRatio).div(10**4));
        pendingPikaReward = pendingPikaReward.add(totalFee.mul(pikaRewardRatio).div(10**4));
        pendingVaultReward = pendingVaultReward.add(totalFee.mul(10**4 - protocolRewardRatio - pikaRewardRatio).div(10**4));
        vault.balance -= uint96(totalFee);

        return totalFee;
    }

    function releaseMargin(uint256 positionId) external onlyOwner {

        Position storage position = positions[positionId];
        require(position.margin > 0, "!position");

        uint256 margin = position.margin;
        address positionOwner = position.owner;

        uint256 amount = margin.mul(uint256(position.leverage)).div(10**8);

        _updateOpenInterest(uint256(position.productId), amount, position.isLong, false);

        emit ClosePosition(
            positionId,
            positionOwner,
            position.productId,
            position.price,
            position.price,
            margin,
            position.leverage,
            0,
            0,
            false
        );

        delete positions[positionId];

        IERC20(token).uniTransfer(positionOwner, margin.mul(tokenBase).div(BASE));
    }


    // Liquidate positionIds
    function liquidatePositions(uint256[] calldata positionIds) external {
        require(msg.sender == liquidator || allowPublicLiquidator, "!liquidator");

        uint256 totalLiquidatorReward;
        for (uint256 i = 0; i < positionIds.length; i++) {
            uint256 positionId = positionIds[i];
            uint256 liquidatorReward = liquidatePosition(positionId);
            totalLiquidatorReward = totalLiquidatorReward.add(liquidatorReward);
        }
        if (totalLiquidatorReward > 0) {
            IERC20(token).uniTransfer(msg.sender, totalLiquidatorReward.mul(tokenBase).div(BASE));
        }
    }


    function liquidatePosition(
        uint256 positionId
    ) internal returns(uint256 liquidatorReward) {
        Position storage position = positions[positionId];
        if (position.productId == 0) {
            return 0;
        }
        Product storage product = products[uint256(position.productId)];
        uint256 price = IOracle(oracle).getPrice(product.feed); // use oracle price for liquidation

        uint256 remainingReward;
        if (_checkLiquidation(position, price, uint256(product.liquidationThreshold))) {
            int256 pnl = _getPnl(position, position.margin, price);
            if (pnl < 0 && uint256(position.margin) > uint256(-1*pnl)) {
                uint256 _pnl = uint256(-1*pnl);
                liquidatorReward = (uint256(position.margin).sub(_pnl)).mul(uint256(product.liquidationBounty)).div(10**4);
                remainingReward = (uint256(position.margin).sub(_pnl).sub(liquidatorReward));
                pendingProtocolReward = pendingProtocolReward.add(remainingReward.mul(protocolRewardRatio).div(10**4));
                pendingPikaReward = pendingPikaReward.add(remainingReward.mul(pikaRewardRatio).div(10**4));
                pendingVaultReward = pendingVaultReward.add(remainingReward.mul(10**4 - protocolRewardRatio - pikaRewardRatio).div(10**4));
                vault.balance += uint96(_pnl);
            } else {
                vault.balance += uint96(position.margin);
            }

            uint256 amount = uint256(position.margin).mul(uint256(position.leverage)).div(BASE);

            _updateOpenInterest(uint256(position.productId), amount, position.isLong, false);

            emit ClosePosition(
                positionId,
                position.owner,
                uint256(position.productId),
                price,
                uint256(position.price),
                uint256(position.margin),
                uint256(position.leverage),
                0,
                int256(uint256(position.margin)),
                true
            );

            delete positions[positionId];

            emit PositionLiquidated(
                positionId,
                msg.sender,
                liquidatorReward,
                remainingReward
            );
        }
        return liquidatorReward;
    }

    function _updateOpenInterest(uint256 productId, uint256 amount, bool isLong, bool isIncrease) internal {
        Product storage product = products[productId];
        if (isIncrease) {
            totalOpenInterest = totalOpenInterest.add(amount);
            require(totalOpenInterest <= uint256(vault.balance).mul(utilizationMultiplier).div(10**4), "!maxOpenInterest");
            uint256 maxExposure = uint256(vault.balance).mul(uint256(product.weight)).mul(exposureMultiplier).div(uint256(totalWeight)).div(10**4);
            if (isLong) {
                product.openInterestLong += uint64(amount);
                require(uint256(product.openInterestLong) <= uint256(maxExposure).add(uint256(product.openInterestShort)), "!exposure-long");
            } else {
                product.openInterestShort += uint64(amount);
                require(uint256(product.openInterestShort) <= uint256(maxExposure).add(uint256(product.openInterestLong)), "!exposure-short");
            }
        } else {
            totalOpenInterest = totalOpenInterest.sub(amount);
            if (isLong) {
                if (uint256(product.openInterestLong) >= amount) {
                    product.openInterestLong -= uint64(amount);
                } else {
                    product.openInterestLong = 0;
                }
            } else {
                if (uint256(product.openInterestShort) >= amount) {
                    product.openInterestShort -= uint64(amount);
                } else {
                    product.openInterestShort = 0;
                }
            }
        }
    }

    function distributeProtocolReward() external returns(uint256) {
        require(msg.sender == protocolRewardDistributor, "!distributor");
        uint256 _pendingProtocolReward = pendingProtocolReward;
        if (pendingProtocolReward > 0) {
            pendingProtocolReward = 0;
            IERC20(token).uniTransfer(protocolRewardDistributor, _pendingProtocolReward.mul(tokenBase).div(BASE));
            emit ProtocolRewardDistributed(protocolRewardDistributor, _pendingProtocolReward.mul(tokenBase).div(BASE));
        }
        return _pendingProtocolReward.mul(tokenBase).div(BASE);
    }

    function distributePikaReward() external returns(uint256) {
        require(msg.sender == pikaRewardDistributor, "!distributor");
        uint256 _pendingPikaReward = pendingPikaReward;
        if (pendingPikaReward > 0) {
            pendingPikaReward = 0;
            IERC20(token).uniTransfer(pikaRewardDistributor, _pendingPikaReward.mul(tokenBase).div(BASE));
            emit PikaRewardDistributed(pikaRewardDistributor, _pendingPikaReward.mul(tokenBase).div(BASE));
        }
        return _pendingPikaReward.mul(tokenBase).div(BASE);
    }

    function distributeVaultReward() external returns(uint256) {
        require(msg.sender == vaultRewardDistributor, "!distributor");
        uint256 _pendingVaultReward = pendingVaultReward;
        if (pendingVaultReward > 0) {
            pendingVaultReward = 0;
            IERC20(token).uniTransfer(vaultRewardDistributor, _pendingVaultReward.mul(tokenBase).div(BASE));
            emit VaultRewardDistributed(vaultRewardDistributor, _pendingVaultReward.mul(tokenBase).div(BASE));
        }
        return _pendingVaultReward.mul(tokenBase).div(BASE);
    }

    // Getters

    function getPendingPikaReward() external view returns(uint256) {
        return pendingPikaReward.mul(tokenBase).div(BASE);
    }

    function getPendingProtocolReward() external view returns(uint256) {
        return pendingProtocolReward.mul(tokenBase).div(BASE);
    }

    function getPendingVaultReward() external view returns(uint256) {
        return pendingVaultReward.mul(tokenBase).div(BASE);
    }

    function getVault() external view returns(Vault memory) {
        return vault;
    }

    function getProduct(uint256 productId) external view returns(Product memory) {
        return products[productId];
    }

    function getPositionId(
        address account,
        uint256 productId,
        bool isLong
    ) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(account, productId, isLong)));
    }

    function getPosition(
        address account,
        uint256 productId,
        bool isLong
    ) external view returns(Position memory position) {
        position = positions[getPositionId(account, productId, isLong)];
    }

    function getPositions(uint256[] calldata positionIds) external view returns(Position[] memory _positions) {
        uint256 length = positionIds.length;
        _positions = new Position[](length);
        for (uint256 i=0; i < length; i++) {
            _positions[i] = positions[positionIds[i]];
        }
    }

    function getTotalShare() external view returns(uint256) {
        return uint256(vault.shares);
    }

    function getShare(address stakeOwner) external view returns(uint256) {
        return uint256(stakes[stakeOwner].shares);
    }

    function getStakes(address[] calldata stakeOwners) external view returns(Stake[] memory _stakes) {
        uint256 length = stakeOwners.length;
        _stakes = new Stake[](length);
        for (uint256 i = 0; i < length; i++) {
            _stakes[i] = stakes[stakeOwners[i]];
        }
    }

    function canLiquidate(
        uint256 positionId
    ) external view returns(bool) {
        Position memory position = positions[positionId];
        Product storage product = products[uint256(position.productId)];
        uint256 price = IOracle(oracle).getPrice(product.feed);
        return _checkLiquidation(position, price, product.liquidationThreshold);
    }

    // Internal methods

    function _canTakeProfit(
        Position memory position,
        uint256 oraclePrice,
        uint256 minPriceChange
    ) internal view returns(bool) {
        if (block.timestamp > uint256(position.timestamp).add(minProfitTime)) {
            return true;
        } else if (position.isLong && oraclePrice > uint256(position.oraclePrice).mul(uint256(1e4).add(minPriceChange)).div(1e4)) {
            return true;
        } else if (!position.isLong && oraclePrice < uint256(position.oraclePrice).mul(uint256(1e4).sub(minPriceChange)).div(1e4)) {
            return true;
        }
        return false;
    }

    function _calculatePrice(
        address feed,
        bool isLong,
        uint256 openInterestLong,
        uint256 openInterestShort,
        uint256 maxExposure,
        uint256 reserve,
        uint256 amount
    ) internal view returns(uint256) {
        uint256 oraclePrice = IOracle(oracle).getPrice(feed);
        int256 shift = (int256(openInterestLong) - int256(openInterestShort)) * int256(maxShift) / int256(maxExposure);
        if (isLong) {
            uint256 slippage = (reserve.mul(reserve).div(reserve.sub(amount)).sub(reserve)).mul(10**8).div(amount);
            slippage = shift >= 0 ? slippage.add(uint256(shift)) : slippage.sub(uint256(-1 * shift).div(2));
            return oraclePrice.mul(slippage).div(10**8);
        } else {
            uint256 slippage = (reserve.sub(reserve.mul(reserve).div(reserve.add(amount)))).mul(10**8).div(amount);
            slippage = shift >= 0 ? slippage.add(uint256(shift).div(2)) : slippage.sub(uint256(-1 * shift));
            return oraclePrice.mul(slippage).div(10**8);
        }
    }

    function _getInterest(
        Position memory position,
        uint256 margin,
        uint256 interest
    ) internal view returns(uint256) {
        return margin.mul(uint256(position.leverage)).mul(interest)
        .mul(block.timestamp.sub(uint256(position.timestamp))).div(uint256(10**12).mul(365 days));
    }

    function _getPnl(
        Position memory position,
        uint256 margin,
        uint256 price
    ) internal view returns(int256 _pnl) {
        bool pnlIsNegative;
        uint256 pnl;
        if (position.isLong) {
            if (price >= uint256(position.price)) {
                pnl = margin.mul(uint256(position.leverage)).mul(price.sub(uint256(position.price))).div(uint256(position.price)).div(10**8);
            } else {
                pnl = margin.mul(uint256(position.leverage)).mul(uint256(position.price).sub(price)).div(uint256(position.price)).div(10**8);
                pnlIsNegative = true;
            }
        } else {
            if (price > uint256(position.price)) {
                pnl = margin.mul(uint256(position.leverage)).mul(price - uint256(position.price)).div(uint256(position.price)).div(10**8);
                pnlIsNegative = true;
            } else {
                pnl = margin.mul(uint256(position.leverage)).mul(uint256(position.price).sub(price)).div(uint256(position.price)).div(10**8);
            }
        }

        if (pnlIsNegative) {
            _pnl = -1 * int256(pnl);
        } else {
            _pnl = int256(pnl);
        }

        return _pnl;
    }

    function _getPnlWithFee(
        int256 pnl,
        Position memory position,
        uint256 margin,
        uint256 fee,
        uint256 interest
    ) internal view returns(int256 pnlAfterFee, uint256 totalFee) {
        // Subtract trade fee from P/L
        uint256 tradeFee = _getTradeFee(margin, uint256(position.leverage), fee);
        pnlAfterFee = pnl.sub(int256(tradeFee));

        // Subtract interest from P/L
        uint256 interestFee = _getInterest(position, margin, interest);
        pnlAfterFee = pnlAfterFee.sub(int256(interestFee));
        totalFee = tradeFee.add(interestFee);
    }

    function _getTradeFee(
        uint256 margin,
        uint256 leverage,
        uint256 fee
    ) internal pure returns(uint256) {
        return margin.mul(leverage).div(10**8).mul(fee).div(10**4);
    }

    function _checkLiquidation(
        Position memory position,
        uint256 price,
        uint256 liquidationThreshold
    ) internal pure returns (bool) {

        uint256 liquidationPrice;

        if (position.isLong) {
            liquidationPrice = position.price - position.price * liquidationThreshold * 10**4 / uint256(position.leverage);
        } else {
            liquidationPrice = position.price + position.price * liquidationThreshold * 10**4 / uint256(position.leverage);
        }

        if (position.isLong && price <= liquidationPrice || !position.isLong && price >= liquidationPrice) {
            return true;
        } else {
            return false;
        }
    }

    // Owner methods

    function updateVault(Vault memory _vault) external onlyOwner {
        require(_vault.cap > 0, "!cap");
        require(_vault.stakingPeriod > 0, "!stakingPeriod");

        vault.cap = _vault.cap;
        vault.stakingPeriod = _vault.stakingPeriod;

        emit VaultUpdated(vault);

    }

    function addProduct(uint256 productId, Product memory _product) external onlyOwner {

        Product memory product = products[productId];
        require(product.maxLeverage == 0, "!product-exists");

        require(_product.maxLeverage > 0, "!max-leverage");
        require(_product.feed != address(0), "!feed");
        require(_product.liquidationThreshold > 0, "!liquidationThreshold");

        products[productId] = Product({
        feed: _product.feed,
        maxLeverage: _product.maxLeverage,
        fee: _product.fee,
        isActive: true,
        openInterestLong: 0,
        openInterestShort: 0,
        interest: _product.interest,
        liquidationThreshold: _product.liquidationThreshold,
        liquidationBounty: _product.liquidationBounty,
        minPriceChange: _product.minPriceChange,
        weight: _product.weight,
        reserve: _product.reserve
        });
        totalWeight += _product.weight;

        emit ProductAdded(productId, products[productId]);

    }

    function updateProduct(uint256 productId, Product memory _product) external onlyOwner {

        Product storage product = products[productId];
        require(product.maxLeverage > 0, "!product-exists");

        require(_product.maxLeverage >= 1 * 10**8, "!max-leverage");
        require(_product.feed != address(0), "!feed");
        require(_product.liquidationThreshold > 0, "!liquidationThreshold");

        product.feed = _product.feed;
        product.maxLeverage = _product.maxLeverage;
        product.fee = _product.fee;
        product.isActive = _product.isActive;
        product.interest = _product.interest;
        product.liquidationThreshold = _product.liquidationThreshold;
        product.liquidationBounty = _product.liquidationBounty;
        totalWeight = totalWeight - product.weight + _product.weight;
        product.weight = _product.weight;

        emit ProductUpdated(productId, product);

    }

    function setDistributors(
        address _protocolRewardDistributor,
        address _pikaRewardDistributor,
        address _vaultRewardDistributor,
        address _vaultTokenReward
    ) external onlyOwner {
        protocolRewardDistributor = _protocolRewardDistributor;
        pikaRewardDistributor = _pikaRewardDistributor;
        vaultRewardDistributor = _vaultRewardDistributor;
        vaultTokenReward = _vaultTokenReward;
    }

    function setProtocolRewardRatio(uint256 _protocolRewardRatio) external onlyOwner {
        require(_protocolRewardRatio <= 10000, "!too-much");
        protocolRewardRatio = _protocolRewardRatio;
        emit ProtocolRewardRatioUpdated(protocolRewardRatio);
    }

    function setPikaRewardRatio(uint256 _pikaRewardRatio) external onlyOwner {
        require(_pikaRewardRatio <= 10000, "!too-much");
        pikaRewardRatio = _pikaRewardRatio;
        emit PikaRewardRatioUpdated(pikaRewardRatio);
    }

    function setMinMargin(uint256 _minMargin) external onlyOwner {
        minMargin = _minMargin;
    }

    function setMaxPositionMargin(uint256 _maxPositionMargin) external onlyOwner {
        maxPositionMargin = _maxPositionMargin;
    }

    function setCanUserStake(bool _canUserStake) external onlyOwner {
        canUserStake = _canUserStake;
    }

    function setAllowPublicLiquidator(bool _allowPublicLiquidator) external onlyOwner {
        allowPublicLiquidator = _allowPublicLiquidator;
    }

    function setExposureMultiplier(uint256 _exposureMultiplier) external onlyOwner {
        exposureMultiplier = _exposureMultiplier;
    }

    function setOracle(address _oracle) external onlyOwner {
        oracle = _oracle;
        emit OracleUpdated(_oracle);
    }

    function setLiquidator(address _liquidator) external onlyOwner {
        liquidator = _liquidator;
    }

    function setOwner(address _owner) external onlyOwner {
        owner = _owner;
        emit OwnerUpdated(_owner);
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

}
