pragma solidity 0.4.25;


contract OracleContractMock {

    event PriceUpdated(uint256 ethUsdPrice);

    uint256 public ethUsdPrice; //price in cents

    address owner;

    constructor() public {
        owner = msg.sender;
        ethUsdPrice = 10000000; //100$
    }

    function setPrice(uint256 _newPrice) public {
        require(msg.sender == owner);
        ethUsdPrice = _newPrice;
        emit PriceUpdated(ethUsdPrice);
    }
}
