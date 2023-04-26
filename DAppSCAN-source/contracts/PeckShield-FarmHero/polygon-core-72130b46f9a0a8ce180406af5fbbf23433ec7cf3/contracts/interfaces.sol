pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

// For interacting with our own strategy
interface IStrategy {
    // Total want tokens managed by stratfegy
    function wantLockedTotal() external view returns (uint256);

    // Sum of all shares of users to wantLockedTotal
    function sharesTotal() external view returns (uint256);

    // Main want token compounding function
    function earn() external;

    // Transfer want tokens autoFarm -> strategy
    function deposit(address _userAddress, uint256 _wantAmt)
        external
        returns (uint256);

    function deposit(address _userAddress, uint256[] memory _tokenIds)
        external
        returns (uint256);

    // Transfer want tokens strategy -> autoFarm
    function withdraw(address _userAddress, uint256 _wantAmt)
        external
        returns (uint256);

    function withdraw(address _userAddress, uint256[] memory _tokenIds)
        external
        returns (uint256);

    function inCaseTokensGetStuck(
        address _token,
        uint256 _amount,
        address _to
    ) external;
    function entranceFeeFactor() external returns (uint256);
}

interface IRewardDistribution {
    function earn(address _strat) external;
    function requestRewardDistribution() external;
}


interface IPlayerBook {
    function dev() external returns (address);
    function NameXPlayer(bytes32) external returns (address);
    function getPlayer(string memory _name) external returns (address);
}

interface IFeeDistribution {
    function mint(address user, uint256 amount) external;
}