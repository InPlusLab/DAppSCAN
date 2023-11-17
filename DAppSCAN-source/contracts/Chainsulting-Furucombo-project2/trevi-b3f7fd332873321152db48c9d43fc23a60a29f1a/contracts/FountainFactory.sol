// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./Fountain.sol";
import "./interfaces/IArchangel.sol";
import "./interfaces/IFountainFactory.sol";
import "./utils/ErrorMsg.sol";

/// @title The factory of Fountain
contract FountainFactory is ErrorMsg {
    IArchangel public immutable archangel;
    /// @dev Token and Fountain should be 1-1 and only
    mapping(IERC20 => Fountain) private _fountains;
    mapping(Fountain => IERC20) private _stakings;

    event Created(address to);

    constructor() public {
        archangel = IArchangel(msg.sender);
    }

    // Getters
    /// @notice Return contract name for error message.
    function getContractName() public pure override returns (string memory) {
        return "FountainFactory";
    }

    /// @notice Check if fountain is valid.
    /// @param fountain The fountain to be verified.
    /// @return Is valid or not.
    function isValid(Fountain fountain) external view returns (bool) {
        return (address(_stakings[fountain]) != address(0));
    }

    /// @notice Get the fountain of given token.
    /// @param token The token address.
    /// @return The fountain.
    function fountainOf(IERC20 token) external view returns (Fountain) {
        return _fountains[token];
    }

    /// @notice Create Fountain for token.
    /// @param token The token address to be created.
    /// @return The created fountain.
    function create(ERC20 token) external returns (Fountain) {
        _requireMsg(
            address(_fountains[token]) == address(0),
            "create",
            "fountain existed"
        );
        string memory name = _concat("Fountain ", token.name());
        string memory symbol = _concat("FTN-", token.symbol());
        Fountain fountain =
            new Fountain(token, name, symbol, archangel.defaultFlashLoanFee());
        _fountains[token] = fountain;
        _stakings[fountain] = token;

        emit Created(address(fountain));
    }

    function _concat(string memory a, string memory b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(a, b));
    }
}
