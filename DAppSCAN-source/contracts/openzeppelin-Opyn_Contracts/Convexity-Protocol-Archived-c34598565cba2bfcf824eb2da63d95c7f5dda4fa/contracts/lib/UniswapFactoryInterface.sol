pragma solidity 0.5.10;


// Solidity Interface
contract UniswapFactoryInterface {
    // Public Variables
    address public exchangeTemplate;
    uint256 public tokenCount;
    // // Create Exchange
    function createExchange(address token) external returns (address exchange);
    // Get Exchange and Token Info
    function getExchange(address token) external view returns (address exchange);
    function getToken(address exchange) external view returns (address token);
    function getTokenWithId(uint256 tokenId) external view returns (address token);
    // Never use
    function initializeFactory(address template) external;
    // function createExchange(address token) external returns (address exchange) {
    //     return 0x06D014475F84Bb45b9cdeD1Cf3A1b8FE3FbAf128;
    // }
    // // Get Exchange and Token Info
    // function getExchange(address token) external view returns (address exchange){
    //     return 0x06D014475F84Bb45b9cdeD1Cf3A1b8FE3FbAf128;
    // }
    // function getToken(address exchange) external view returns (address token) {
    //     return 0x06D014475F84Bb45b9cdeD1Cf3A1b8FE3FbAf128;
    // }
    // function getTokenWithId(uint256 tokenId) external view returns (address token) {
    //     return 0x06D014475F84Bb45b9cdeD1Cf3A1b8FE3FbAf128;
    // }
}
