// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma abicoder v2;

import '@openzeppelin/contracts/token/ERC721/ERC721Holder.sol';
import '@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol';
import './helpers/ERC20Helper.sol';
import './utils/Storage.sol';
import '../interfaces/IPositionManager.sol';
import '../interfaces/DataTypes.sol';
import '../interfaces/IUniswapAddressHolder.sol';
import '../interfaces/IAaveAddressHolder.sol';
import '../interfaces/IDiamondCut.sol';
import '../interfaces/IRegistry.sol';
import '../interfaces/ILendingPool.sol';

/**
 * @title   Position Manager
 * @notice  A vault that provides liquidity on Uniswap V3.
 * @notice  User can Deposit here its Uni-v3 position
 * @notice  If user does so, he is sure that idle liquidity will always be employed in protocols
 * @notice  User will pay fee to external keepers
 * @notice  vault works for multiple positions
 */

contract PositionManager is IPositionManager, ERC721Holder {
    uint256[] private uniswapNFTs;
    mapping(uint256 => mapping(address => ModuleInfo)) public activatedModules;

    ///@notice emitted when a position is withdrawn
    ///@param to address of the user
    ///@param tokenId ID of the withdrawn NFT
    event PositionWithdrawn(address to, uint256 tokenId);

    ///@notice emitted when a ERC20 is withdrawn
    ///@param tokenAddress address of the ERC20
    ///@param to address of the user
    ///@param amount of the ERC20
    event ERC20Withdrawn(address tokenAddress, address to, uint256 amount);

    ///@notice emitted when a module is activated/deactivated
    ///@param module address of module
    ///@param tokenId position on which change is made
    ///@param isActive true if module is activated, false if deactivated
    event ModuleStateChanged(address module, uint256 tokenId, bool isActive);

    ///@notice modifier to check if the msg.sender is the owner
    modifier onlyOwner() {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();

        require(msg.sender == Storage.owner, 'PositionManager::onlyOwner: Only owner can call this function');
        _;
    }

    ///@notice modifier to check if the msg.sender is whitelisted
    modifier onlyWhitelisted() {
        require(
            _calledFromRecipe(msg.sender) || _calledFromActiveModule(msg.sender) || msg.sender == address(this),
            'PositionManager::fallback: Only whitelisted addresses can call this function'
        );
        _;
    }

    ///@notice modifier to check if the msg.sender is the PositionManagerFactory
    modifier onlyFactory(address _registry) {
        require(
            IRegistry(_registry).positionManagerFactoryAddress() == msg.sender,
            'PositionManager::init: Only PositionManagerFactory can init this contract'
        );
        _;
    }

    ///@notice modifier to check if the position is owned by the positionManager
    modifier onlyOwnedPosition(uint256 tokenId) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        require(
            INonfungiblePositionManager(Storage.uniswapAddressHolder.nonfungiblePositionManagerAddress()).ownerOf(
                tokenId
            ) == address(this),
            'PositionManager::onlyOwnedPosition: positionManager is not owner of the token'
        );
        _;
    }

    constructor(
        address _owner,
        address _diamondCutFacet,
        address _registry
    ) payable onlyFactory(_registry) {
        PositionManagerStorage.setContractOwner(_owner);

        // Add the diamondCut external function from the diamondCutFacet
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = IDiamondCut.diamondCut.selector;
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: _diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
        PositionManagerStorage.diamondCut(cut, address(0), '');
    }

    function init(
        address _owner,
        address _uniswapAddressHolder,
        address _registry,
        address _aaveAddressHolder
    ) public onlyFactory(_registry) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        Storage.owner = _owner;
        Storage.uniswapAddressHolder = IUniswapAddressHolder(_uniswapAddressHolder);
        Storage.registry = IRegistry(_registry);
        Storage.aaveAddressHolder = IAaveAddressHolder(_aaveAddressHolder);
    }

    ///@notice middleware to manage the deposit of the position
    ///@param tokenId ID of the position
    function middlewareDeposit(uint256 tokenId) public override onlyOwnedPosition(tokenId) {
        _setDefaultDataOfPosition(tokenId);
        pushPositionId(tokenId);
    }

    ///@notice remove awareness of tokenId UniswapV3 NFT
    ///@param tokenId ID of the NFT to remove
    function removePositionId(uint256 tokenId) public override onlyWhitelisted {
        for (uint256 i = 0; i < uniswapNFTs.length; i++) {
            if (uniswapNFTs[i] == tokenId) {
                if (uniswapNFTs.length > 1) {
                    uniswapNFTs[i] = uniswapNFTs[uniswapNFTs.length - 1];
                    uniswapNFTs.pop();
                } else {
                    delete uniswapNFTs;
                }
                return;
            }
        }
    }

    ///@notice add tokenId in the uniswapNFTs array
    ///@param tokenId ID of the added NFT
    function pushPositionId(uint256 tokenId) public override onlyOwnedPosition(tokenId) {
        uniswapNFTs.push(tokenId);
    }

    ///@notice return the IDs of the uniswap positions
    ///@return array of IDs
    function getAllUniPositions() external view override returns (uint256[] memory) {
        uint256[] memory uniswapNFTsMemory = uniswapNFTs;
        return uniswapNFTsMemory;
    }

    ///@notice set default data for every module
    ///@param tokenId ID of the position
    function _setDefaultDataOfPosition(uint256 tokenId) internal {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();

        bytes32[] memory moduleKeys = Storage.registry.getModuleKeys();

        for (uint32 i = 0; i < moduleKeys.length; i++) {
            (address moduleAddress, , bytes32 defaultData, bool activatedByDefault) = Storage.registry.getModuleInfo(
                moduleKeys[i]
            );

            activatedModules[tokenId][moduleAddress].isActive = activatedByDefault;
            activatedModules[tokenId][moduleAddress].data = defaultData;
        }
    }

    ///@notice toggle module state, activated (true) or not (false)
    ///@param tokenId ID of the NFT
    ///@param moduleAddress address of the module
    ///@param activated state of the module
    function toggleModule(
        uint256 tokenId,
        address moduleAddress,
        bool activated
    ) external override onlyOwner onlyOwnedPosition(tokenId) {
        activatedModules[tokenId][moduleAddress].isActive = activated;
        emit ModuleStateChanged(moduleAddress, tokenId, activated);
    }

    ///@notice sets the data of a module strategy for tokenId position
    ///@param tokenId ID of the position
    ///@param moduleAddress address of the module
    ///@param data data for the module
    function setModuleData(
        uint256 tokenId,
        address moduleAddress,
        bytes32 data
    ) external override onlyOwner onlyOwnedPosition(tokenId) {
        uint256 moduleData = uint256(data);
        require(moduleData > 0, 'PositionManager::setModuleData: moduleData must be greater than 0%');
        activatedModules[tokenId][moduleAddress].data = data;
    }

    ///@notice get info for a module strategy for tokenId position
    ///@param _tokenId ID of the position
    ///@param _moduleAddress address of the module
    ///@return isActive is module activated
    ///@return data of the module
    function getModuleInfo(uint256 _tokenId, address _moduleAddress)
        external
        view
        override
        returns (bool isActive, bytes32 data)
    {
        return (activatedModules[_tokenId][_moduleAddress].isActive, activatedModules[_tokenId][_moduleAddress].data);
    }

    ///@notice stores old position data when liquidity is moved to aave
    ///@param token address of the token
    ///@param id ID of the position
    ///@param tokenId of the position
    function pushTokenIdToAave(
        address token,
        uint256 id,
        uint256 tokenId
    ) public override onlyWhitelisted {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        require(
            Storage.aaveUserReserves[token].positionShares[id] > 0,
            'PositionManager::pushOldPositionData: positionShares does not exist'
        );

        Storage.aaveUserReserves[token].tokenIds[id] = tokenId;
    }

    ///@notice returns the old position data of an aave position
    ///@param token address of the token
    ///@param id ID of aave position
    ///@return tokenId of the position
    function getTokenIdFromAavePosition(address token, uint256 id)
        public
        view
        override
        onlyWhitelisted
        returns (uint256)
    {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        require(
            Storage.aaveUserReserves[token].positionShares[id] > 0,
            'PositionManager::getOldPositionData: positionShares does not exist'
        );

        return Storage.aaveUserReserves[token].tokenIds[id];
    }

    ///@notice return the address of this position manager owner
    ///@return address of the owner
    function getOwner() external view override returns (address) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        return Storage.owner;
    }

    ///@notice return the all tokens of tokenAddress in the positionManager
    ///@param tokenAddress address of the token to be withdrawn
    function withdrawERC20(address tokenAddress) external override onlyOwner {
        ERC20Helper._approveToken(tokenAddress, address(this), 2**256 - 1);
        uint256 amount = ERC20Helper._withdrawTokens(tokenAddress, msg.sender, 2**256 - 1);
        emit ERC20Withdrawn(tokenAddress, msg.sender, amount);
    }

    ///@notice function to check if an address corresponds to an active module (or this contract)
    ///@param _address input address
    ///@return isCalledFromActiveModule boolean
    function _calledFromActiveModule(address _address) internal view returns (bool isCalledFromActiveModule) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        bytes32[] memory keys = Storage.registry.getModuleKeys();
        for (uint256 i = 0; i < keys.length; i++) {
            (address moduleAddress, bool isActive, , ) = Storage.registry.getModuleInfo(keys[i]);
            if (moduleAddress == _address && isActive == true) {
                isCalledFromActiveModule = true;
                break;
            }
        }
    }

    function _calledFromRecipe(address _address) internal view returns (bool isCalledFromRecipe) {
        StorageStruct storage Storage = PositionManagerStorage.getStorage();
        bytes32[] memory recipeKeys = PositionManagerStorage.getRecipesKeys();

        for (uint256 i = 0; i < recipeKeys.length; i++) {
            (address moduleAddress, , , ) = Storage.registry.getModuleInfo(recipeKeys[i]);
            if (moduleAddress == _address) {
                isCalledFromRecipe = true;
                break;
            }
        }
    }

    fallback() external payable onlyWhitelisted {
        StorageStruct storage Storage;
        bytes32 position = PositionManagerStorage.key;
        ///@dev get diamond storage position
        assembly {
            Storage.slot := position
        }
        address facet = Storage.selectorToFacetAndPosition[msg.sig].facetAddress;
        require(facet != address(0), 'PositionManager::Fallback: Function does not exist');
        ///@dev Execute external function from facet using delegatecall and return any value.

        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {
        revert();
        //we need to decide what to do when the contract receives ether
        //for now we just revert
    }
}
