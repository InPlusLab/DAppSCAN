import './DSMath.sol';

pragma solidity ^0.5.10;

interface CTokenInterface {
    function redeem(uint redeemTokens) external returns (uint);
    function redeemUnderlying(uint redeemAmount) external returns (uint);
    function borrow(uint borrowAmount) external returns (uint);
    function liquidateBorrow(address borrower, uint repayAmount, address cTokenCollateral) external returns (uint);
    function liquidateBorrow(address borrower, address cTokenCollateral) external payable;
    function exchangeRateCurrent() external returns (uint);
    function getCash() external view returns (uint);
    function totalBorrowsCurrent() external returns (uint);
    function borrowRatePerBlock() external view returns (uint);
    function supplyRatePerBlock() external view returns (uint);
    function totalReserves() external view returns (uint);
    function reserveFactorMantissa() external view returns (uint);

    function totalSupply() external view returns (uint256);
    function balanceOf(address owner) external view returns (uint256 balance);
    function allowance(address, address) external view returns (uint);
    function approve(address, uint) external;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface CERC20Interface {
    function mint(uint mintAmount) external returns (uint); // For ERC20
    function repayBorrow(uint repayAmount) external returns (uint); // For ERC20
    function repayBorrowBehalf(address borrower, uint repayAmount) external returns (uint); // For ERC20
    function borrowBalanceCurrent(address account) external returns (uint);
}

interface ERC20Interface {
    function allowance(address, address) external view returns (uint);
    function balanceOf(address) external view returns (uint);
    function approve(address, uint) external;
    function transfer(address, uint) external returns (bool);
    function transferFrom(address, address, uint) external returns (bool);
}

interface TrollerInterface {
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function exitMarket(address cTokenAddress) external returns (uint);
    function getAssetsIn(address account) external view returns (address[] memory);
    function getAccountLiquidity(address account) external view returns (uint, uint, uint);
}


contract Helpers is DSMath {

    address public comptroller;

    /**
     * @dev get Compound Comptroller Address
     */
    function getComptrollerAddress() public view returns (address) {
        // troller = 0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B; // Mainnet
        // troller = 0x2EAa9D77AE4D8f9cdD9FAAcd44016E746485bddb; // Rinkeby
        // troller = 0x3CA5a0E85aD80305c2d2c4982B2f2756f1e747a5; // Kovan
        return comptroller;
    }

    function enterMarket(address cErc20) internal {
        TrollerInterface troller = TrollerInterface(getComptrollerAddress());
        address[] memory markets = troller.getAssetsIn(address(this));
        bool isEntered = false;
        for (uint i = 0; i < markets.length; i++) {
            if (markets[i] == cErc20) {
                isEntered = true;
            }
        }
        if (!isEntered) {
            address[] memory toEnter = new address[](1);
            toEnter[0] = cErc20;
            troller.enterMarkets(toEnter);
        }
    }

    /**
     * @dev setting allowance to compound for the "user proxy" if required
     */
    function setApproval(address erc20, uint srcAmt, address to) internal {
        ERC20Interface erc20Contract = ERC20Interface(erc20);
        uint tokenAllowance = erc20Contract.allowance(address(this), to);
        if (srcAmt > tokenAllowance) {
            erc20Contract.approve(to, 2**255);
        }
    }

}


contract ALCompound is Helpers {
    /**
     * @dev Deposit ETH/ERC20 and mint Compound Tokens
     */
    function mintCToken(address erc20, address cErc20, uint tokenAmt) internal {
        enterMarket(cErc20);
        ERC20Interface token = ERC20Interface(erc20);
        uint toDeposit = token.balanceOf(address(this));
        if (toDeposit > tokenAmt) {
            toDeposit = tokenAmt;
        }
        CERC20Interface cToken = CERC20Interface(cErc20);
        setApproval(erc20, toDeposit, cErc20);
        assert(cToken.mint(toDeposit) == 0);
    }

    /**
     * @dev Redeem ETH/ERC20 and mint Compound Tokens
     * @param tokenAmt Amount of token To Redeem
     */
    function redeemUnderlying(address cErc20, uint tokenAmt) internal {
        CTokenInterface cToken = CTokenInterface(cErc20);
        setApproval(cErc20, 10**50, cErc20);
        uint toBurn = cToken.balanceOf(address(this));
        uint tokenToReturn = wmul(toBurn, cToken.exchangeRateCurrent());
        if (tokenToReturn > tokenAmt) {
            tokenToReturn = tokenAmt;
        }
        require(cToken.redeemUnderlying(tokenToReturn) == 0, "something went wrong");
    }

    /**
     * @dev Redeem ETH/ERC20 and burn Compound Tokens
     * @param cTokenAmt Amount of CToken To burn
     */
    function redeemCToken(address cErc20, uint cTokenAmt) internal {
        CTokenInterface cToken = CTokenInterface(cErc20);
        uint toBurn = cToken.balanceOf(address(this));
        if (toBurn > cTokenAmt) {
            toBurn = cTokenAmt;
        }
        setApproval(cErc20, toBurn, cErc20);
        require(cToken.redeem(toBurn) == 0, "something went wrong");
    }
}
