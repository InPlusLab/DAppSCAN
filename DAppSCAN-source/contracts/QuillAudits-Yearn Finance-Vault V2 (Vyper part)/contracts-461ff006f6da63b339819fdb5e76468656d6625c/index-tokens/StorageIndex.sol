pragma solidity ^0.5.0;

import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "../shared/utils/DateTimeLibrary.sol"; 
import "../shared/utils/Math.sol"; 


contract StorageIndex is Ownable {
    address public tokenSwapManager;
    address public bridge;

    bool public isPaused;
    bool public isShutdown;

    struct Accounting {
        uint256 bestExecutionPrice;
        uint256 markPrice;
        uint256 notional;
        uint256 tokenValue;
        uint256 effectiveFundingRate;
    }

    struct Order {
        string orderType;
        uint256 tokensGiven;
        uint256 tokensRecieved;
        uint256 mintingPrice;
    }

    uint256 public lastActivityDay;
    uint256 public minRebalanceAmount;
    uint256 public managementFee;
    uint256 public minimumMintingFee;
    uint256 public minimumTrade;

    uint8 public balancePrecision;

    mapping(uint256 => Accounting[]) private accounting;

    uint256[] public mintingFeeBracket;
    mapping(uint256 => uint256) public mintingFee;

    Order[] public allOrders;
    mapping(address => Order[]) public orderByUser;
    mapping(address => uint256) public delayedRedemptionsByUser;

    event AccountingValuesSet(uint256 today);
    event RebalanceValuesSet(uint256 newMinRebalanceAmount);
    event ManagementFeeValuesSet(uint256 newManagementFee);

    function initialize(
        address ownerAddress,
        uint256 _managementFee,
        uint256 _minRebalanceAmount,
        uint8 _balancePrecision,
        uint256 _lastMintingFee,
        uint256 _minimumMintingFee,
        uint256 _minimumTrade
    ) public initializer {
        initialize(ownerAddress);
        managementFee = _managementFee;
        minRebalanceAmount = _minRebalanceAmount;
        mintingFee[~uint256(0)] = _lastMintingFee;
        balancePrecision = _balancePrecision;
        minimumMintingFee = _minimumMintingFee;
        minimumTrade = _minimumTrade;
    }

    function setTokenSwapManager(address _tokenSwapManager) public onlyOwner {
        require(_tokenSwapManager != address(0), "adddress must not be empty");
        tokenSwapManager = _tokenSwapManager;
    }

    function setBridge(address _bridge) public onlyOwner {
        require(_bridge != address(0), "adddress must not be empty");
        bridge = _bridge;
    }

    function setIsPaused(bool _isPaused) public onlyOwner {
        isPaused = _isPaused;
    }

    function shutdown() public onlyOwner {
        isShutdown = true;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwnerOrTokenSwap() {
        require(
            isOwner() || _msgSender() == tokenSwapManager,
            "caller is not the owner or token swap manager"
        );
        _;
    }

    modifier onlyOwnerOrBridge() {
        require(
            isOwner() || _msgSender() == bridge,
            "caller is not the owner or bridge"
        );
        _;
    }

    function setDelayedRedemptionsByUser(
        uint256 amountToRedeem,
        address whitelistedAddress
    ) public onlyOwnerOrTokenSwap {
        delayedRedemptionsByUser[whitelistedAddress] = amountToRedeem;
    }

    /*
     * Saves order in mapping (address => Order[]) orderByUser
     * overwrite == false, append to Order[]
     * overwrite == true, overwrite element at orderIndex
     */

    function setOrderByUser(
        address whitelistedAddress,
        string memory orderType,
        uint256 tokensGiven,
        uint256 tokensRecieved,
        uint256 mintingPrice,
        uint256 orderIndex,
        bool overwrite
    ) public onlyOwnerOrTokenSwap() {
        Order memory newOrder = Order(
            orderType,
            tokensGiven,
            tokensRecieved,
            mintingPrice
        );

        if (!overwrite) {
            orderByUser[whitelistedAddress].push(newOrder);
            setOrder(
                orderType,
                tokensGiven,
                tokensRecieved,
                mintingPrice,
                orderIndex,
                overwrite
            );
        } else {
            orderByUser[whitelistedAddress][orderIndex] = newOrder;
        }
    }

    /*
     * Gets Order[] For User Address
     * Return order at Index in Order[]
     */

    function getOrderByUser(address whitelistedAddress, uint256 orderIndex)
        public
        view
        returns (
            string memory orderType,
            uint256 tokensGiven,
            uint256 tokensRecieved,
            uint256 mintingPrice
        )
    {

            Order storage orderAtIndex
         = orderByUser[whitelistedAddress][orderIndex];
        return (
            orderAtIndex.orderType,
            orderAtIndex.tokensGiven,
            orderAtIndex.tokensRecieved,
            orderAtIndex.mintingPrice
        );
    }

    /*
     * Save order to allOrders array
     * overwrite == false, append to allOrders array
     * overwrite == true, overwrite element at orderIndex
     */
    function setOrder(
        string memory orderType,
        uint256 tokensGiven,
        uint256 tokensRecieved,
        uint256 mintingPrice,
        uint256 orderIndex,
        bool overwrite
    ) public onlyOwnerOrTokenSwap() {
        Order memory newOrder = Order(
            orderType,
            tokensGiven,
            tokensRecieved,
            mintingPrice
        );

        if (!overwrite) {
            allOrders.push(newOrder);
        } else {
            allOrders[orderIndex] = newOrder;
        }
    }

    /*
     * Get Order
     */
    function getOrder(uint256 index)
        public
        view
        returns (
            string memory orderType,
            uint256 tokensGiven,
            uint256 tokensRecieved,
            uint256 mintingPrice
        )
    {
        Order storage orderAtIndex = allOrders[index];
        return (
            orderAtIndex.orderType,
            orderAtIndex.tokensGiven,
            orderAtIndex.tokensRecieved,
            orderAtIndex.mintingPrice
        );
    }

    // @dev Get accounting values for a specific day
    // @param date format as 20200123 for 23th of January 2020
    function getAccounting(uint256 date)
        public
        view
        returns (uint256, uint256, uint256, uint256, uint256)
    {
        Accounting[] storage accountingsForDate = accounting[date];
        uint256 lastIndex = accountingsForDate.length - 1;
        return (
            accountingsForDate[lastIndex].bestExecutionPrice,
            accountingsForDate[lastIndex].markPrice,
            accountingsForDate[lastIndex].notional,
            accountingsForDate[lastIndex].tokenValue,
            accountingsForDate[lastIndex].effectiveFundingRate
        );
    }

    // @dev Set accounting values for the day
    function setAccounting(
        uint256 _bestExecutionPrice,
        uint256 _markPrice,
        uint256 _notional,
        uint256 _tokenValue,
        uint256 _effectiveFundingRate
    ) external onlyOwnerOrTokenSwap() {
        (uint256 year, uint256 month, uint256 day) = DateTimeLibrary
            .timestampToDate(block.timestamp);
        uint256 today = year * 10000 + month * 100 + day;
        accounting[today].push(
            Accounting(
                _bestExecutionPrice,
                _markPrice,
                _notional,
                _tokenValue,
                _effectiveFundingRate
            )
        );
        lastActivityDay = today;
        emit AccountingValuesSet(today);
    }

    // @dev Set accounting values for the day
    function setAccountingForLastActivityDay(
        uint256 _bestExecutionPrice,
        uint256 _markPrice,
        uint256 _notional,
        uint256 _tokenValue,
        uint256 _effectiveFundingRate
    ) external onlyOwnerOrTokenSwap() {
        accounting[lastActivityDay].push(
            Accounting(
                _bestExecutionPrice,
                _markPrice,
                _notional,
                _tokenValue,
                _effectiveFundingRate
            )
        );
        emit AccountingValuesSet(lastActivityDay);
    }

    // @dev Set last rebalance information
    function setMinRebalanceAmount(uint256 _minRebalanceAmount)
        external
        onlyOwner
    {
        minRebalanceAmount = _minRebalanceAmount;

        emit RebalanceValuesSet(minRebalanceAmount);
    }

    // @dev Set last rebalance information
    function setManagementFee(uint256 _managementFee) external onlyOwner {
        managementFee = _managementFee;
        emit ManagementFeeValuesSet(managementFee);
    }

    // @dev Returns execution price
    function getExecutionPrice() public view returns (uint256 price) {
        return
            accounting[lastActivityDay][accounting[lastActivityDay].length - 1]
                .bestExecutionPrice;
    }

    // @dev Returns mark price
    function getMarkPrice() public view returns (uint256 price) {
        return
            accounting[lastActivityDay][accounting[lastActivityDay].length - 1]
                .markPrice;
    }

    // @dev Returns notional amount
    function getNotional() public view returns (uint256 amount) {
        return
            accounting[lastActivityDay][accounting[lastActivityDay].length - 1]
                .notional;
    }

    // @dev Returns token value
    function getTokenValue() public view returns (uint256 tokenValue) {
        return
            accounting[lastActivityDay][accounting[lastActivityDay].length - 1]
                .tokenValue;
    }

    // @dev Returns effective funding rate
    function getFundingRate() public view returns (uint256 fundingRate) {
        return
            accounting[lastActivityDay][accounting[lastActivityDay].length - 1]
                .effectiveFundingRate;
    }

    // @dev Sets last minting fee
    function setLastMintingFee(uint256 _mintingFee) public onlyOwner {
        mintingFee[~uint256(0)] = _mintingFee;
    }

    // @dev Adds minting fee
    function addMintingFeeBracket(uint256 _mintingFeeLimit, uint256 _mintingFee)
        public
        onlyOwner
    {
        require(
            mintingFeeBracket.length == 0 ||
                _mintingFeeLimit >
                mintingFeeBracket[mintingFeeBracket.length - 1],
            "New minting fee bracket needs to be bigger then last one"
        );
        mintingFeeBracket.push(_mintingFeeLimit);
        mintingFee[_mintingFeeLimit] = _mintingFee;
    }

    // @dev Deletes last minting fee
    function deleteLastMintingFeeBracket() public onlyOwner {
        delete mintingFee[mintingFeeBracket[mintingFeeBracket.length - 1]];
        mintingFeeBracket.length--;
    }

    // @dev Changes minting fee
    function changeMintingLimit(
        uint256 _position,
        uint256 _mintingFeeLimit,
        uint256 _mintingFee
    ) public onlyOwner {
        require(
            _mintingFeeLimit > mintingFeeBracket[mintingFeeBracket.length - 1],
            "New minting fee bracket needs to be bigger then last one"
        );
        if (_position != 0) {
            require(
                _mintingFeeLimit > mintingFeeBracket[_position - 1],
                "New minting fee bracket needs to be bigger then last one"
            );
        }
        if (_position < mintingFeeBracket.length - 1) {
            require(
                _mintingFeeLimit < mintingFeeBracket[_position + 1],
                "New minting fee bracket needs to be smaller then next one"
            );
        }
        mintingFeeBracket[_position] = _mintingFeeLimit;
        mintingFee[_mintingFeeLimit] = _mintingFee;
    }

    function getMintingFee(uint256 cash) public view returns (uint256) {
        // Define Start + End Index
        uint256 startIndex = 0;
        if (mintingFeeBracket.length > 0) {
            uint256 endIndex = mintingFeeBracket.length - 1;
            uint256 middleIndex = endIndex / 2;

            if (cash <= mintingFeeBracket[middleIndex]) {
                endIndex = middleIndex;
            } else {
                startIndex = middleIndex + 1;
            }

            for (uint256 i = startIndex; i <= endIndex; i++) {
                if (cash <= mintingFeeBracket[i]) {
                    return mintingFee[mintingFeeBracket[i]];
                }
            }
        }

        return mintingFee[~uint256(0)];
    }

    // @dev Sets last balance precision
    function setLastPrecision(uint8 _balancePrecision) public onlyOwner {
        balancePrecision = _balancePrecision;
    }

    // @dev Sets minimum minting fee
    function setMinimumMintingFee(uint256 _minimumMintingFee) public onlyOwner {
        minimumMintingFee = _minimumMintingFee;
    }

    // @dev Sets minimum trade value
    function setMinimumTrade(uint256 _minimumTrade) public onlyOwner {
        minimumTrade = _minimumTrade;
    }
}
