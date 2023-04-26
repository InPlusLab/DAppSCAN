//SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "../libraries/NFTLib.sol";
import "../libraries/Random.sol";
import "../interfaces/IPandoBox.sol";
import "../interfaces/IDroidBot.sol";
import "../interfaces/IPandoPot.sol";
import "../interfaces/IDataStorage.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/ISwapRouter02.sol";

contract NFTRouter is Ownable{
    using SafeERC20 for IERC20;

    mapping (uint256 => uint256) private pandoBoxCreated;

    uint256 constant PRECISION = 10000000000;
    IDroidBot public droidBot;
    IPandoBox public pandoBox;
    IPandoPot public pandoPot;
    IDataStorage public dataStorage;
    IERC20 public PAN;
    IERC20 public PSR;
    IOracle public PANOracle;
    IOracle public PSROracle;
    ISwapRouter02 public swapRouter;

    uint256 public startTime;
    uint256 public pandoBoxPerDay;
    uint256 public createPandoBoxFee;
    uint256 public upgradeBaseFee;
    uint256 public PSRRatio = 80;
    uint256 public slippage = 8000000000;
    address[] public PANToPSR;

    /*----------------------------INITIALIZE----------------------------*/
    constructor (
        address _pandoBox,
        address _droidBot,
        address _PAN,
        address _PSR,
        address _pandoPot,
        address _dataStorage,
        address _PANOracle,
        address _PSROracle,
        address _swapRouter,
        uint256 _startTime
    ) {
        pandoBox = IPandoBox(_pandoBox);
        droidBot = IDroidBot(_droidBot);
        PAN = IERC20(_PAN);
        PSR = IERC20(_PSR);
        pandoPot = IPandoPot(_pandoPot);
        dataStorage = IDataStorage(_dataStorage);
        startTime = _startTime;
        PANOracle = IOracle(_PANOracle);
        PSROracle = IOracle(_PSROracle);
        swapRouter = ISwapRouter02(_swapRouter);
    }

    /*----------------------------INTERNAL FUNCTIONS----------------------------*/
    function getPandoBoxLv() internal view returns(uint256) {
        uint256[] memory _creatingProbability = IDataStorage(dataStorage).getPandoBoxCreatingProbability();
        uint256 _randSeed = Random.computerSeed(0) % PRECISION + 1;
        uint256 _cur = 0;
        for (uint256 i = 0; i < _creatingProbability.length; i++) {
            _cur += _creatingProbability[i];
            if (_cur >= _randSeed) {
                return i;
            }
        }
        return 0;
    }

    function getNewBotLv(uint256 _boxLv) internal view returns(uint256, uint256) {
        uint256[] memory _creatingProbability = IDataStorage(dataStorage).getDroidBotCreatingProbability(_boxLv);
        uint256 _randSeed = Random.computerSeed(0) % PRECISION + 1;
        uint256 _cur = 0;
        for (uint256 i = 0; i < _creatingProbability.length; i++) {
            _cur += _creatingProbability[i];
            if (_cur >= _randSeed) {
                uint256 _power = IDataStorage(dataStorage).getDroidBotPower(i);
                return (i, _power);
            }
        }
        return (0, 0);
    }

    function getUpgradeBotLv(uint256 _bot0Lv, uint256 _bot1Lv) internal view returns (uint256, uint256){
        uint256[] memory _evolvingProbability = IDataStorage(dataStorage).getDroidBotUpgradingProbability(_bot0Lv, _bot1Lv);
        uint256 _randSeed = Random.computerSeed(0) % PRECISION + 1;
        uint256 _cur = 0;
        for (uint256 i = 0; i < _evolvingProbability.length; i++) {
            _cur += _evolvingProbability[i];
            if (_cur >= _randSeed) {
                uint256 _power = IDataStorage(dataStorage).getDroidBotPower(i);
                return (i, _power);
            }
        }
        return (0, 0);
    }

    /*----------------------------EXTERNAL FUNCTIONS----------------------------*/
    function createPandoBox(uint256 _option) external {
        require(block.timestamp >= startTime, 'Router: not started');
        uint256 _ndays = (block.timestamp - startTime) / 1 days;
        if (pandoBoxCreated[_ndays] < pandoBoxPerDay) {
            if (createPandoBoxFee > 0) {
                if (_option == 0) { // only PAN
                    PAN.safeTransferFrom(msg.sender, address(this), createPandoBoxFee);
                    uint256 _amountSwap = createPandoBoxFee * (100 - PSRRatio) / 100;
                    uint256 _minAmount = _amountSwap * slippage / PRECISION;
                    IERC20(PAN).safeApprove(address(swapRouter), _amountSwap);
                    swapRouter.swapExactTokensForTokens(_amountSwap, _minAmount, PANToPSR, address(this), block.timestamp + 300);
                    ERC20Burnable(address(PAN)).burn(PAN.balanceOf(address(this)));
                    ERC20Burnable(address(PSR)).burn(PSR.balanceOf(address(this)));
                } else {
                    uint256 _price_PAN = PANOracle.consult();
                    uint256 _price_PSR = PSROracle.consult();

                    uint256 _amount_PSR = createPandoBoxFee * (100 - PSRRatio) / 100 * _price_PAN / _price_PSR;
                    ERC20Burnable(address(PAN)).burnFrom(msg.sender, createPandoBoxFee * PSRRatio / 100);
                    ERC20Burnable(address(PSR)).burnFrom(msg.sender, _amount_PSR);
                }
            }
            pandoBoxCreated[_ndays]++;
            uint256 _lv = getPandoBoxLv();
            uint256 _boxId = pandoBox.create(msg.sender, _lv);
            emit BoxCreated(msg.sender, _lv, _option, _boxId);
        }
    }

    function createDroidBot(uint256 _pandoBoxId) external {
        if (pandoBox.ownerOf(_pandoBoxId) == msg.sender) {
            pandoBox.burn(_pandoBoxId);
            NFTLib.Info memory _info = pandoBox.info(_pandoBoxId);
            (uint256 _lv, uint256 _power) = getNewBotLv(_info.level);
            uint256 _newBotId = droidBot.create(msg.sender, _lv, _power);

            (uint256 _megaNum, uint256 _minorNum) = dataStorage.getJDroidBotCreating(_info.level);
            pandoPot.enter(msg.sender, _megaNum, _minorNum, PANOracle.consult());
            emit BotCreated(msg.sender, _pandoBoxId, _newBotId);
        }
    }

    function upgradeDroidBot(uint256 _droidBot0Id, uint256 _droidBot1Id) external{
        require(droidBot.ownerOf(_droidBot0Id) == msg.sender && droidBot.ownerOf(_droidBot1Id) == msg.sender, 'NFTRouter : not owner of bot');
        uint256 _l0 = droidBot.level(_droidBot0Id);
        uint256 _l1 = droidBot.level(_droidBot1Id);
        uint256 _id0 = _droidBot0Id;
        uint256 _id1 = _droidBot1Id;
        if (_l0 < _l1) {
            _id0 = _droidBot1Id;
            _id1 = _droidBot0Id;
        }
        NFTLib.Info memory _info0 = droidBot.info(_id0);
        NFTLib.Info memory _info1 = droidBot.info(_id1);

        uint256 _upgradeFee = upgradeBaseFee * (15 ** _info1.level) / (10 ** _info1.level);

        if (_upgradeFee > 0) {
            ERC20Burnable(address(PSR)).burnFrom(msg.sender, _upgradeFee);
        }

        (uint256 _lv, uint256 _power) = getUpgradeBotLv(_info0.level, _info1.level);
        droidBot.burn(_id1);
        if (_lv > _info0.level) {
            droidBot.upgrade(_id0, _lv, _power);
        } else {
            _power = _info0.power;
        }
        (uint256 _megaNum, uint256 _minorNum) = dataStorage.getJDroidBotUpgrading(_info1.level);
        pandoPot.enter(msg.sender, _megaNum, _minorNum, PSROracle.consult());
        emit BotUpgraded(msg.sender, _id0, _id1);
    }


    function pandoBoxRemain() external view returns (uint256) {
        uint256 _ndays = (block.timestamp - startTime) / 1 days;
        return pandoBoxPerDay - pandoBoxCreated[_ndays];
    }

    /*----------------------------RESTRICT FUNCTIONS----------------------------*/
    function setPandoBoxPerDay(uint256 _value) external onlyOwner {
        pandoBoxPerDay = _value;
    }

    function setCreatePandoBoxFee(uint256 _newFee) external onlyOwner {
        createPandoBoxFee = _newFee;
    }

    function setUpgradeBaseFee(uint256 _newFee) external onlyOwner {
        upgradeBaseFee = _newFee;
    }

    function setJackpotAddress(address _addr) external onlyOwner {
        pandoPot = IPandoPot(_addr);
    }

    function setDataStorageAddress(address _addr) external onlyOwner {
        dataStorage = IDataStorage(_addr);
    }

    function setPANOracle(address _addr) external onlyOwner {
        PANOracle = IOracle(_addr);
    }

    function setPSROracle(address _addr) external onlyOwner {
        PSROracle = IOracle(_addr);
    }

    function setPath(address [] memory _path) external onlyOwner {
        PANToPSR = _path;
    }

    function setPSRRatio(uint256 _ratio) external onlyOwner {
        PSRRatio = _ratio;
    }

    function setNftAddress(address _droidBot, address _pandoBox) external onlyOwner {
        pandoBox = IPandoBox(_pandoBox);
        droidBot = IDroidBot(_droidBot);
    }

    function setTokenAddress(address _PSR, address _PAN) external onlyOwner {
        PAN = IERC20(_PAN);
        PSR = IERC20(_PSR);
    }

    function setSwapRouter(address _swapRouter) external onlyOwner {
        swapRouter = ISwapRouter02(_swapRouter);
    }

    function setSlippage(uint256 _value) external onlyOwner {
        require(_value <= PRECISION, 'NFT Router: > precision');
        slippage = _value;
    }

    event BoxCreated(address indexed receiver, uint256 level, uint256 option, uint256 indexed newBoxId);
    event BotCreated(address indexed receiver, uint256 indexed boxId, uint256 indexed newBotId);
    event BotUpgraded(address indexed user, uint256 indexed bot0Id, uint256 indexed bot1Id);
}