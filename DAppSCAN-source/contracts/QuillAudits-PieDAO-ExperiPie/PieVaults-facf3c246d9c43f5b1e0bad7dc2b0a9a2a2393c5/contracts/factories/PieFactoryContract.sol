// SPDX-License-Identifier: MIT
pragma solidity ^0.7.1;
pragma experimental ABIEncoderV2;

import "diamond-2/contracts/Diamond.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "../interfaces/IExperiPie.sol";

contract PieFactoryContract is Ownable {
    using SafeERC20 for IERC20;

    address[] public pies;
    mapping(address => bool) public isPie;
    address public defaultController;

    IDiamondCut.FacetCut[] public defaultCut;

    event PieCreated(
        address indexed pieAddress,
        address indexed deployer,
        uint256 indexed index
    );

    event DefaultControllerSet(address indexed controller);
    event FacetAdded(IDiamondCut.FacetCut);
    event FacetRemoved(IDiamondCut.FacetCut);

    constructor() {
        defaultController = msg.sender;
    }

    function setDefaultController(address _controller) external onlyOwner {
        defaultController = _controller;
        emit DefaultControllerSet(_controller);
    }

    function removeFacet(uint256 _index) external onlyOwner {
        emit FacetRemoved(defaultCut[_index]);
        defaultCut[_index] = defaultCut[defaultCut.length - 1];
        defaultCut.pop();
    }

    function addFacet(IDiamondCut.FacetCut memory _facet) external onlyOwner {
        defaultCut.push(_facet);
        emit FacetAdded(_facet);
    }

    function bakePie(
        address[] memory _tokens,
        uint256[] memory _amounts,
        uint256 _initialSupply,
        string memory _symbol,
        string memory _name
    ) external {
        Diamond d = new Diamond(defaultCut, address(this));

        pies.push(address(d));
        isPie[address(d)] = true;

        // emit DiamondCreated(address(d));
        require(_tokens.length != 0, "CANNOT_CREATE_ZERO_TOKEN_LENGTH_PIE");
        require(_tokens.length == _amounts.length, "ARRAY_LENGTH_MISMATCH");

        IExperiPie pie = IExperiPie(address(d));

        // Init erc20 facet
        pie.initialize(_initialSupply, _name, _symbol);

        // Transfer and add tokens
        // SWC-128-DoS With Block Gas Limit: L73 - L77
        for (uint256 i = 0; i < _tokens.length; i++) {
            IERC20 token = IERC20(_tokens[i]);
            token.safeTransferFrom(msg.sender, address(pie), _amounts[i]);
            pie.addToken(_tokens[i]);
        }

        // Unlock pool
        pie.setLock(1);

        // Uncap pool
        pie.setCap(uint256(-1));

        // Send minted pie to msg.sender
        pie.transfer(msg.sender, _initialSupply);
        pie.transferOwnership(defaultController);

        emit PieCreated(address(d), msg.sender, pies.length - 1);
    }

    function getDefaultCut()
        external
        view
        returns (IDiamondCut.FacetCut[] memory)
    {
        return defaultCut;
    }

    function getDefaultCutCount() external view returns (uint256) {
        return defaultCut.length;
    }
}
