// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

interface ISIGHBoostersSale {

    event BoosterAddedForSale(string _type,uint boosterid);
    event SalePriceUpdated(string _type,uint _price);
    event PaymentTokenUpdated(address token);
    event FundsTransferred(uint amount);
    event TokensTransferred(address token,address to,uint amount);
    event SaleTimeUpdated(uint initiateTimestamp);
    event BoosterSold(address _to, string _BoosterType,uint _boosterId, uint salePrice );
    event BoostersBought(address caller,address receiver,string _BoosterType,uint boostersBought,uint amountToBePaid);
    event BoosterAdded(address operator,address from,uint tokenId);

    // #################################
    // ######## ADMIN FUNCTIONS ########
    // #################################

    // Add a list of Boosters for sale at a particular price
//    function addBoostersForSale(string calldata _BoosterType, uint[] memory boosterIds) external;

    // Update the sale price for a particular type of Boosters
    function updateSalePrice(string calldata _BoosterType, uint256 _price ) external;

    // Update the token accepted as payment
    function updateAcceptedToken(address token) external;

    // Transfer part of the the token collected for payments to the 'to' address
    function transferBalance(address to, uint amount) external;

    // Updates time when the Booster sale will go live
    function updateSaleTime(uint timestamp) external;

    function transferTokens(address token, address to, uint amount) external ;
    // ##########################################
    // ######## FUNCTION TO BY BOOSTERS  ########
    // ##########################################

    // Buy the 'boostersToBuy' no. of Boosters for the '_BoosterType' type of boosters
    function buyBoosters(address receiver, string memory _BoosterType, uint boostersToBuy) external;

    // #########################################
    // ######## EXTERNAL VIEW FUNCTIONS ########
    // #########################################

    // Get the current available no. of boosters, its price and total sold for the provided Booster category
    function getBoosterSaleDetails(string memory _Boostertype) external view returns (uint256 available,uint256 price, uint256 sold);

    // Get the symbol and address of the token accepted for payments
    function getTokenAccepted() external view returns(string memory symbol, address tokenAddress);

    // Get current balance of the token accepted for payments.
    function getCurrentFundsBalance() external view returns (uint256);

    function getTokenBalance(address token) external view returns (uint256) ;

}
