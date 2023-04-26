// SPDX-License-Identifier: MIT

pragma solidity 0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {IKODAV3} from "../IKODAV3.sol";

interface ERC998ERC20TopDown {
    event ReceivedERC20(address indexed _from, uint256 indexed _tokenId, address indexed _erc20Contract, uint256 _value);
    event ReceivedERC20ForEdition(address indexed _from, uint256 indexed _editionId, address indexed _erc20Contract, uint256 _value);
    event TransferERC20(uint256 indexed _tokenId, address indexed _to, address indexed _erc20Contract, uint256 _value);

    function balanceOfERC20(uint256 _tokenId, address _erc20Contract) external view returns (uint256);

    function transferERC20(uint256 _tokenId, address _to, address _erc20Contract, uint256 _value) external;

    function getERC20(address _from, uint256 _tokenId, address _erc20Contract, uint256 _value) external;
}

interface ERC998ERC20TopDownEnumerable {
    function totalERC20Contracts(uint256 _tokenId) external view returns (uint256);

    function erc20ContractByIndex(uint256 _tokenId, uint256 _index) external view returns (address);
}

/// @notice ERC998 ERC721 > ERC20 Top Down implementation
abstract contract TopDownERC20Composable is ERC998ERC20TopDown, ERC998ERC20TopDownEnumerable, ReentrancyGuard, Context {
    using EnumerableSet for EnumerableSet.AddressSet;

    // Edition ID -> ERC20 contract -> Balance of ERC20 for every token in Edition
    mapping(uint256 => mapping(address => uint256)) public editionTokenERC20Balances;

    // Edition ID -> ERC20 contract -> Token ID -> Balance Transferred out of token
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) public editionTokenERC20TransferAmounts;

    // Edition ID -> Linked ERC20 contract addresses
    mapping(uint256 => EnumerableSet.AddressSet) ERC20sEmbeddedInEdition;

    // Token ID -> Linked ERC20 contract addresses
    mapping(uint256 => EnumerableSet.AddressSet) ERC20sEmbeddedInNft;

    // Token ID -> ERC20 contract -> balance of ERC20 owned by token
    mapping(uint256 => mapping(address => uint256)) public ERC20Balances;

    /// @notice the ERC20 balance of a NFT token given an ERC20 token address
    function balanceOfERC20(uint256 _tokenId, address _erc20Contract) public override view returns (uint256) {
        IKODAV3 koda = IKODAV3(address(this));
        uint256 editionId = koda.getEditionIdOfToken(_tokenId);

        uint256 editionBalance = editionTokenERC20Balances[editionId][_erc20Contract];
        uint256 tokenEditionBalance = editionBalance / koda.getSizeOfEdition(editionId);
        uint256 spentTokens = editionTokenERC20TransferAmounts[editionId][_erc20Contract][_tokenId];
        tokenEditionBalance = tokenEditionBalance - spentTokens;

        return tokenEditionBalance + ERC20Balances[_tokenId][_erc20Contract];
    }

    /// @notice Transfer out an ERC20 from an NFT
    function transferERC20(uint256 _tokenId, address _to, address _erc20Contract, uint256 _value) external override nonReentrant {
        _prepareERC20LikeTransfer(_tokenId, _to, _erc20Contract, _value);

        IERC20(_erc20Contract).transfer(_to, _value);

        emit TransferERC20(_tokenId, _to, _erc20Contract, _value);
    }

    /// @notice An NFT token owner (or approved) can compose multiple ERC20s in their NFT
    function getERC20s(address _from, uint256[] calldata _tokenIds, address _erc20Contract, uint256 _totalValue) external {
        uint256 totalTokens = _tokenIds.length;
        require(totalTokens > 0 && _totalValue > 0, "Empty values");

        uint256 valuePerToken = _totalValue / totalTokens;
        for (uint i = 0; i < totalTokens; i++) {
            getERC20(_from, _tokenIds[i], _erc20Contract, valuePerToken);
        }
    }

    /// @notice A NFT token owner (or approved address) can compose any ERC20 in their NFT
    function getERC20(address _from, uint256 _tokenId, address _erc20Contract, uint256 _value) public override nonReentrant {
        require(_value > 0, "Value zero");
        require(_from == _msgSender(), "Only owner");

        address spender = _msgSender();
        IERC721 self = IERC721(address(this));

        address owner = self.ownerOf(_tokenId);
        require(
            owner == spender || self.isApprovedForAll(owner, spender) || self.getApproved(_tokenId) == spender,
            "Invalid spender"
        );

        uint256 editionId = IKODAV3(address(this)).getEditionIdOfToken(_tokenId);
        bool editionAlreadyContainsERC20 = ERC20sEmbeddedInEdition[editionId].contains(_erc20Contract);
        bool nftAlreadyContainsERC20 = ERC20sEmbeddedInNft[_tokenId].contains(_erc20Contract);

        // does not already contain _erc20Contract
        if (!editionAlreadyContainsERC20 && !nftAlreadyContainsERC20) {
            ERC20sEmbeddedInNft[_tokenId].add(_erc20Contract);
        }

        ERC20Balances[_tokenId][_erc20Contract] = ERC20Balances[_tokenId][_erc20Contract] + _value;

        IERC20 token = IERC20(_erc20Contract);
        require(token.allowance(_from, address(this)) >= _value, "Exceeds allowance");

        token.transferFrom(_from, address(this), _value);

        emit ReceivedERC20(_from, _tokenId, _erc20Contract, _value);
    }

    function _composeERC20IntoEdition(address _from, uint256 _editionId, address _erc20Contract, uint256 _value) internal nonReentrant {
        require(_value > 0, "Value zero");

        require(!ERC20sEmbeddedInEdition[_editionId].contains(_erc20Contract), "Edition contains ERC20");

        ERC20sEmbeddedInEdition[_editionId].add(_erc20Contract);
        editionTokenERC20Balances[_editionId][_erc20Contract] = editionTokenERC20Balances[_editionId][_erc20Contract] + _value;

        IERC20(_erc20Contract).transferFrom(_from, address(this), _value);

        emit ReceivedERC20ForEdition(_from, _editionId, _erc20Contract, _value);
    }

    function totalERC20Contracts(uint256 _tokenId) override public view returns (uint256) {
        uint256 editionId = IKODAV3(address(this)).getEditionIdOfToken(_tokenId);
        return ERC20sEmbeddedInNft[_tokenId].length() + ERC20sEmbeddedInEdition[editionId].length();
    }

    function erc20ContractByIndex(uint256 _tokenId, uint256 _index) override external view returns (address) {
        uint256 numOfERC20sInNFT = ERC20sEmbeddedInNft[_tokenId].length();
        if (_index >= numOfERC20sInNFT) {
            uint256 editionId =  IKODAV3(address(this)).getEditionIdOfToken(_tokenId);
            return ERC20sEmbeddedInEdition[editionId].at(_index - numOfERC20sInNFT);
        }

        return ERC20sEmbeddedInNft[_tokenId].at(_index);
    }

    /// --- Internal ----

    function _prepareERC20LikeTransfer(uint256 _tokenId, address _to, address _erc20Contract, uint256 _value) private {
        // To avoid stack too deep, do input checks within this scope
        {
            require(_value > 0, "Value zero");
            require(_to != address(0), "Zero address");

            IERC721 self = IERC721(address(this));

            address owner = self.ownerOf(_tokenId);
            require(
                owner == _msgSender() || self.isApprovedForAll(owner, _msgSender()) || self.getApproved(_tokenId) == _msgSender(),
                "Not owner"
            );
        }

        // Check that the NFT contains the ERC20
        bool nftContainsERC20 = ERC20sEmbeddedInNft[_tokenId].contains(_erc20Contract);

        IKODAV3 koda = IKODAV3(address(this));
        uint256 editionId = koda.getEditionIdOfToken(_tokenId);
        bool editionContainsERC20 = ERC20sEmbeddedInEdition[editionId].contains(_erc20Contract);
        require(nftContainsERC20 || editionContainsERC20, "No such ERC20");

        // Check there is enough balance to transfer out
        require(balanceOfERC20(_tokenId, _erc20Contract) >= _value, "Exceeds balance");

        uint256 editionSize = koda.getSizeOfEdition(editionId);
        uint256 tokenInitialBalance = editionTokenERC20Balances[editionId][_erc20Contract] / editionSize;
        uint256 spentTokens = editionTokenERC20TransferAmounts[editionId][_erc20Contract][_tokenId];
        uint256 editionTokenBalance = tokenInitialBalance - spentTokens;

        // Check whether the value can be fully transferred from the edition balance, token balance or both balances
        if (editionTokenBalance >= _value) {
            editionTokenERC20TransferAmounts[editionId][_erc20Contract][_tokenId] = spentTokens + _value;
        } else if (ERC20Balances[_tokenId][_erc20Contract] >= _value) {
            ERC20Balances[_tokenId][_erc20Contract] = ERC20Balances[_tokenId][_erc20Contract] - _value;
        } else {
            // take from both balances
            editionTokenERC20TransferAmounts[editionId][_erc20Contract][_tokenId] = spentTokens + editionTokenBalance;
            uint256 amountOfTokensToSpendFromTokenBalance = _value - editionTokenBalance;
            ERC20Balances[_tokenId][_erc20Contract] = ERC20Balances[_tokenId][_erc20Contract] - amountOfTokensToSpendFromTokenBalance;
        }

        // The ERC20 is no longer composed within the token if the balance falls to zero
        if (nftContainsERC20 && ERC20Balances[_tokenId][_erc20Contract] == 0) {
            ERC20sEmbeddedInNft[_tokenId].remove(_erc20Contract);
        }

        // If all tokens in an edition have spent their ERC20 balance, then we can remove the link
        if (editionContainsERC20) {
            uint256 allTokensInEditionERC20Balance;
            for (uint i = 0; i < editionSize; i++) {
                uint256 tokenBal = tokenInitialBalance - editionTokenERC20TransferAmounts[editionId][_erc20Contract][editionId + i];
                allTokensInEditionERC20Balance = allTokensInEditionERC20Balance + tokenBal;
            }

            if (allTokensInEditionERC20Balance == 0) {
                ERC20sEmbeddedInEdition[editionId].remove(_erc20Contract);
            }
        }
    }
}
