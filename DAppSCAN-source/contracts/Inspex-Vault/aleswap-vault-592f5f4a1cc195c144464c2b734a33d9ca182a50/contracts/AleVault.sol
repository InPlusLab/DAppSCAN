//SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "./interfaces/IVaultStrategy.sol";
import "./interfaces/ISwapper.sol";

contract AleVault is ERC20Upgradeable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;
    using SafeMathUpgradeable for uint;
    using AddressUpgradeable for address payable;

    IVaultStrategy public strategy;
    ISwapper public swapper;

    event InCaseTokensGetStuck(address _token);

    function initialize (
        IVaultStrategy _strategy,
        ISwapper _swapper,
        string memory _name,
        string memory _symbol
    ) external initializer {
        __ERC20_init(_name,_symbol);
        __Ownable_init();
        __ReentrancyGuard_init();

        strategy = _strategy;
        swapper = _swapper;
        
        want().safeApprove(address(swapper), type(uint256).max);
    }

    function want() public view returns (IERC20) {
        return IERC20(strategy.want());
    }

    function balance() public view returns (uint) {
        return IVaultStrategy(strategy).balanceOf();
    }

    /**
     * @dev Function for various UIs to display the current value of one of our yield tokens.
     * Returns an uint256 with 18 decimals of how much underlying asset one vault share represents.
     */
    function getPricePerFullShare() external view returns (uint256) {
        return totalSupply() == 0 ? 1e18 : balance().mul(1e18).div(totalSupply());
    }

    receive() external payable {}

    function depositAll() external {
        deposit(want().balanceOf(msg.sender));
    }

    /**
     * @dev The entrypoint of funds into the system. People deposit with this function
     * into the vault. The vault is then in charge of sending funds into the strategy.
     */
    function deposit(uint _amount) public nonReentrant {
        want().safeTransferFrom(msg.sender, address(this), _amount);

        _depositAndMintVaultToken(_amount);
    }

    function depositFromNative(uint256 _minAmount) external payable nonReentrant {
        uint _amount = swapper.swapNativeToLp{value: msg.value}(address(want()), _minAmount, address(this));

        _depositAndMintVaultToken(_amount);  
    }

    function depositFromToken(address _token, uint _tokenAmount, uint256 _minAmount) public nonReentrant {
        require(_token !=  address(want()), "use deposit!");
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _tokenAmount);

        IERC20(_token).safeApprove(address(swapper),_tokenAmount);
        uint _amount = swapper.swapTokenToLP(_token,_tokenAmount, address(want()), _minAmount, address(this));

        _depositAndMintVaultToken(_amount);    
    }

    function depositAllFromToken(address _token,uint256 _minAmount) external {
        depositFromToken(_token, IERC20(_token).balanceOf(msg.sender), _minAmount);
    }    

    function _depositAndMintVaultToken(uint _amount) internal {
        uint256 _poolBefore = balance();        
        
        uint _bal = want().balanceOf(address(this));
        want().safeTransfer(address(strategy), _bal);
        strategy.deposit();

        uint256 shares = 0;
        if (totalSupply() == 0) {
            shares = _amount;
        } else {
            shares = (_amount.mul(totalSupply())).div(_poolBefore);
        }
        _mint(msg.sender, shares);
    }

    function withdrawAll() external {
        withdraw(balanceOf(msg.sender));
    }

    function _withdraw(uint256 _shares) internal returns (uint256)  {
        uint256 _amount = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);
        _amount = strategy.withdraw(_amount); // _amount sub withdraw fee

        return _amount;
    }

    /**
     * @dev Function to exit the system. The vault will withdraw the required tokens
     * from the strategy and pay up the token holder. A proportional number of IOU
     * tokens are burned in the process.
     */
    function withdraw(uint256 _shares) public {
        uint256 _amount = _withdraw(_shares);
        want().safeTransfer(msg.sender, _amount);
    }

    function withdrawToNative(uint256 _shares,uint256 _minAmount) public nonReentrant {
        uint256 _amount = _withdraw(_shares);
        uint256 _nativeAmount = swapper.swapLpToNative(address(want()), _amount, _minAmount, address(this));

        payable(msg.sender).sendValue(_nativeAmount);
    }

    function withdrawToToken(uint256 _shares, address _token, uint256 _minAmount) public {
        require(_token != address(want()), "use withdraw!");
        
        uint256 _amount = _withdraw(_shares);
        uint256 _tokenAmount = swapper.swapLpToToken(address(want()), _amount, _token, _minAmount, address(this));

        IERC20(_token).safeTransfer(msg.sender, _tokenAmount);
    }

    function withdrawAllToNative(uint256 _minAmount) external {
        withdrawToNative(balanceOf(msg.sender), _minAmount);
    }    

    function withdrawAllToToken(address _token, uint256 _minAmount) external {
        withdrawToToken(balanceOf(msg.sender), _token, _minAmount);
    }        

    /**
     * @dev Rescues random funds stuck that the strat can't handle.
     * @param _token address of the token to rescue.
     */
    function inCaseTokensGetStuck(address _token) external onlyOwner {
        require(_token != address(want()), "!token");

        uint256 amount = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransfer(msg.sender, amount);
        emit InCaseTokensGetStuck(_token);
    }
}