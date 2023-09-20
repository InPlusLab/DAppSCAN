// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../libraries/DecimalMath.sol";
import "../interfaces/IDsgToken.sol";

contract vDSGToken is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // ============ Storage(ERC20) ============

    string public name = "vDSG Membership Token";
    string public symbol = "vDSG";
    uint8 public decimals = 18;

    uint256 public _MIN_PENALTY_RATIO_ = 15 * 10**16; // 15%
    uint256 public _MAX_PENALTY_RATIO_ = 80 * 10**16; // 80%
    uint256 public _MIN_MINT_RATIO_ = 10 * 10**16; //10%
    uint256 public _MAX_MINT_RATIO_ = 80 * 10**16; //80%

    mapping(address => mapping(address => uint256)) internal _allowed;

    // ============ Storage ============

    address public _dsgToken;
    address public _dsgTeam;
    address public _dsgReserve;

    bool public _canTransfer;

    // staking reward parameters
    uint256 public _dsgPerBlock;
    uint256 public constant _superiorRatio = 10**17; // 0.1
    uint256 public constant _dsgRatio = 100; // 100
    uint256 public _dsgFeeBurnRatio = 30 * 10**16; //30%
    uint256 public _dsgFeeReserveRatio = 20 * 10**16; //20%

    // accounting
    uint112 public alpha = 10**18; // 1
    uint112 public _totalBlockDistribution;
    uint32 public _lastRewardBlock;

    uint256 public _totalBlockReward;
    uint256 public _totalStakingPower;
    mapping(address => UserInfo) public userInfo;
    
    uint256 public _superiorMinDSG = 1000e18; //The superior must obtain the min DSG that should be pledged for invitation rewards

    struct UserInfo {
        uint128 stakingPower;
        uint128 superiorSP;
        address superior;
        uint256 credit;
        uint256 creditDebt;
    }

    // ============ Events ============

    event MintVDSG(address user, address superior, uint256 mintDSG);
    event RedeemVDSG(address user, uint256 receiveDSG, uint256 burnDSG, uint256 feeDSG, uint256 reserveDSG);
    event DonateDSG(address user, uint256 donateDSG);
    event SetCanTransfer(bool allowed);

    event PreDeposit(uint256 dsgAmount);
    event ChangePerReward(uint256 dsgPerBlock);
    event UpdateDSGFeeBurnRatio(uint256 dsgFeeBurnRatio);

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);

    // ============ Modifiers ============

    modifier canTransfer() {
        require(_canTransfer, "vDSGToken: not allowed transfer");
        _;
    }

    modifier balanceEnough(address account, uint256 amount) {
        require(availableBalanceOf(account) >= amount, "vDSGToken: available amount not enough");
        _;
    }

    // ============ Constructor ============

    constructor(
        address dsgToken,
        address dsgTeam,
        address dsgReserve
    ) public {
        _dsgToken = dsgToken;
        _dsgTeam = dsgTeam;
        _dsgReserve = dsgReserve;

        changePerReward(15*10**18);
    }

    // ============ Ownable Functions ============`

    function setCanTransfer(bool allowed) public onlyOwner {
        _canTransfer = allowed;
        emit SetCanTransfer(allowed);
    }

    function changePerReward(uint256 dsgPerBlock) public onlyOwner {
        _updateAlpha();
        _dsgPerBlock = dsgPerBlock;
        emit ChangePerReward(dsgPerBlock);
    }

    function updateDSGFeeBurnRatio(uint256 dsgFeeBurnRatio) public onlyOwner {
        _dsgFeeBurnRatio = dsgFeeBurnRatio;
        emit UpdateDSGFeeBurnRatio(_dsgFeeBurnRatio);
    }

    function updateDSGFeeReserveRatio(uint256 dsgFeeReserve) public onlyOwner {
        _dsgFeeReserveRatio = dsgFeeReserve;
    }

    function updateTeamAddress(address team) public onlyOwner {
        _dsgTeam = team;
    }

    function updateReserveAddress(address newAddress) public onlyOwner {
        _dsgReserve = newAddress;
    }
    
    function setSuperiorMinDSG(uint256 val) public onlyOwner {
        _superiorMinDSG = val;
    }

    function emergencyWithdraw() public onlyOwner {
        uint256 dsgBalance = IERC20(_dsgToken).balanceOf(address(this));
        IERC20(_dsgToken).safeTransfer(owner(), dsgBalance);
    }

    // ============ Mint & Redeem & Donate ============

    function mint(uint256 dsgAmount, address superiorAddress) public {
        require(
            superiorAddress != address(0) && superiorAddress != msg.sender,
            "vDSGToken: Superior INVALID"
        );
        require(dsgAmount >= 1e18, "vDSGToken: must mint greater than 1");
        

        UserInfo storage user = userInfo[msg.sender];

        if (user.superior == address(0)) {
            require(
                superiorAddress == _dsgTeam || userInfo[superiorAddress].superior != address(0),
                "vDSGToken: INVALID_SUPERIOR_ADDRESS"
            );
            user.superior = superiorAddress;
        }
        
        if(_superiorMinDSG > 0) {
            uint256 curDSG = dsgBalanceOf(user.superior);
            if(curDSG < _superiorMinDSG) {
                user.superior = _dsgTeam;
            }
        }

        _updateAlpha();

        IERC20(_dsgToken).safeTransferFrom(msg.sender, address(this), dsgAmount);

        uint256 newStakingPower = DecimalMath.divFloor(dsgAmount, alpha);

        _mint(user, newStakingPower);

        emit MintVDSG(msg.sender, superiorAddress, dsgAmount);
    }

    function redeem(uint256 vDsgAmount, bool all) public balanceEnough(msg.sender, vDsgAmount) {
        _updateAlpha();
        UserInfo storage user = userInfo[msg.sender];

        uint256 dsgAmount;
        uint256 stakingPower;

        if (all) {
            stakingPower = uint256(user.stakingPower).sub(DecimalMath.divFloor(user.credit, alpha));
            dsgAmount = DecimalMath.mulFloor(stakingPower, alpha);
        } else {
            dsgAmount = vDsgAmount.mul(_dsgRatio);
            stakingPower = DecimalMath.divFloor(dsgAmount, alpha);
        }

        _redeem(user, stakingPower);

        (uint256 dsgReceive, uint256 burnDsgAmount, uint256 withdrawFeeAmount, uint256 reserveAmount) = getWithdrawResult(dsgAmount);

        IERC20(_dsgToken).safeTransfer(msg.sender, dsgReceive);

        if (burnDsgAmount > 0) {
            IDsgToken(_dsgToken).burn(burnDsgAmount);
        }
        if (reserveAmount > 0) {
            IERC20(_dsgToken).safeTransfer(_dsgReserve, reserveAmount);
        }

        if (withdrawFeeAmount > 0) {
            alpha = uint112(
                uint256(alpha).add(
                    DecimalMath.divFloor(withdrawFeeAmount, _totalStakingPower)
                )
            );
        }

        emit RedeemVDSG(msg.sender, dsgReceive, burnDsgAmount, withdrawFeeAmount, reserveAmount);
    }

    function donate(uint256 dsgAmount) public {

        IERC20(_dsgToken).safeTransferFrom(msg.sender, address(this), dsgAmount);

        alpha = uint112(
            uint256(alpha).add(DecimalMath.divFloor(dsgAmount, _totalStakingPower))
        );
        emit DonateDSG(msg.sender, dsgAmount);
    }

    // function preDepositedBlockReward(uint256 dsgAmount) public {

    //     IERC20(_dsgToken).safeTransferFrom(msg.sender, address(this), dsgAmount);

    //     _totalBlockReward = _totalBlockReward.add(dsgAmount);
    //     emit PreDeposit(dsgAmount);
    // }

    // ============ ERC20 Functions ============

    function totalSupply() public view returns (uint256 vDsgSupply) {
        uint256 totalDsg = IERC20(_dsgToken).balanceOf(address(this));
        (,uint256 curDistribution) = getLatestAlpha();
        
        uint256 actualDsg = totalDsg.add(curDistribution);
        vDsgSupply = actualDsg / _dsgRatio;
    }

    function balanceOf(address account) public view returns (uint256 vDsgAmount) {
        vDsgAmount = dsgBalanceOf(account) / _dsgRatio;
    }

    function transfer(address to, uint256 vDsgAmount) public returns (bool) {
        _updateAlpha();
        _transfer(msg.sender, to, vDsgAmount);
        return true;
    }

    function approve(address spender, uint256 vDsgAmount) canTransfer public returns (bool) {
        _allowed[msg.sender][spender] = vDsgAmount;
        emit Approval(msg.sender, spender, vDsgAmount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 vDsgAmount
    ) public returns (bool) {
        require(vDsgAmount <= _allowed[from][msg.sender], "ALLOWANCE_NOT_ENOUGH");
        _updateAlpha();
        _transfer(from, to, vDsgAmount);
        _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(vDsgAmount);
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return _allowed[owner][spender];
    }

    // ============ Helper Functions ============

    function getLatestAlpha() public view returns (uint256 newAlpha, uint256 curDistribution) {
        if (_lastRewardBlock == 0) {
            curDistribution = 0;
        } else {
            curDistribution = _dsgPerBlock * (block.number - _lastRewardBlock);
        }
        if (_totalStakingPower > 0) {
            newAlpha = uint256(alpha).add(DecimalMath.divFloor(curDistribution, _totalStakingPower));
        } else {
            newAlpha = alpha;
        }
    }

    function availableBalanceOf(address account) public view returns (uint256 vDsgAmount) {
        vDsgAmount = balanceOf(account);
    }

    function dsgBalanceOf(address account) public view returns (uint256 dsgAmount) {
        UserInfo memory user = userInfo[account];
        (uint256 newAlpha,) = getLatestAlpha();
        uint256 nominalDsg =  DecimalMath.mulFloor(uint256(user.stakingPower), newAlpha);
        if(nominalDsg > user.credit) {
            dsgAmount = nominalDsg - user.credit;
        } else {
            dsgAmount = 0;
        }
    }

    function getWithdrawResult(uint256 dsgAmount)
    public
    view
    returns (
        uint256 dsgReceive,
        uint256 burnDsgAmount,
        uint256 withdrawFeeDsgAmount,
        uint256 reserveDsgAmount
    )
    {
        uint256 feeRatio = getDsgWithdrawFeeRatio();

        withdrawFeeDsgAmount = DecimalMath.mulFloor(dsgAmount, feeRatio);
        dsgReceive = dsgAmount.sub(withdrawFeeDsgAmount);

        burnDsgAmount = DecimalMath.mulFloor(withdrawFeeDsgAmount, _dsgFeeBurnRatio);
        reserveDsgAmount = DecimalMath.mulFloor(withdrawFeeDsgAmount, _dsgFeeReserveRatio);

        withdrawFeeDsgAmount = withdrawFeeDsgAmount.sub(burnDsgAmount);
        withdrawFeeDsgAmount = withdrawFeeDsgAmount.sub(reserveDsgAmount);
    }

    function getDsgWithdrawFeeRatio() public view returns (uint256 feeRatio) {
        uint256 dsgCirculationAmount = getCirculationSupply();

        uint256 x =
        DecimalMath.divCeil(
            totalSupply() * 100,
            dsgCirculationAmount
        );

        feeRatio = getRatioValue(x);
    }

    function setRatioValue(uint256 min, uint256 max) public onlyOwner {
        require(max > min, "bad num");

        _MIN_PENALTY_RATIO_ = min;
        _MAX_PENALTY_RATIO_ = max;
    }
    //SWC-101-Integer Overflow and Underflow: L351-L357
    function setMintLimitRatio(uint256 min, uint256 max) public onlyOwner {
        require(max < 10**18, "bad max");
        require( (max - min)/10**16 > 0, "bad max - min");

        _MIN_MINT_RATIO_ = min;
        _MAX_MINT_RATIO_ = max;
    }

    function getRatioValue(uint256 input) public view returns (uint256) {

        // y = 15% (x < 0.1)
        // y = 5% (x > 0.5)
        // y = 0.175 - 0.25 * x

        if (input <= _MIN_MINT_RATIO_) {
            return _MAX_PENALTY_RATIO_;
        } else if (input >= _MAX_MINT_RATIO_) {
            return _MIN_PENALTY_RATIO_;
        } else {
            uint256 step = (_MAX_PENALTY_RATIO_ - _MIN_PENALTY_RATIO_) * 10 / ((_MAX_MINT_RATIO_ - _MIN_MINT_RATIO_) / 1e16);
            return _MAX_PENALTY_RATIO_ + step - DecimalMath.mulFloor(input, step*10);
        }
    }

    function getSuperior(address account) public view returns (address superior) {
        return userInfo[account].superior;
    }

    // ============ Internal Functions ============

    function _updateAlpha() internal {
        (uint256 newAlpha, uint256 curDistribution) = getLatestAlpha();
        uint256 newTotalDistribution = curDistribution.add(_totalBlockDistribution);
        require(newAlpha <= uint112(-1) && newTotalDistribution <= uint112(-1), "OVERFLOW");
        alpha = uint112(newAlpha);
        _totalBlockDistribution = uint112(newTotalDistribution);
        _lastRewardBlock = uint32(block.number);
        
        if( curDistribution > 0) {
            IDsgToken(_dsgToken).mint(address(this), curDistribution);
        
            _totalBlockReward = _totalBlockReward.add(curDistribution);
            emit PreDeposit(curDistribution);
        }
        
    }

    function _mint(UserInfo storage to, uint256 stakingPower) internal {
        require(stakingPower <= uint128(-1), "OVERFLOW");
        UserInfo storage superior = userInfo[to.superior];
        uint256 superiorIncreSP = DecimalMath.mulFloor(stakingPower, _superiorRatio);
        uint256 superiorIncreCredit = DecimalMath.mulFloor(superiorIncreSP, alpha);

        to.stakingPower = uint128(uint256(to.stakingPower).add(stakingPower));
        to.superiorSP = uint128(uint256(to.superiorSP).add(superiorIncreSP));

        superior.stakingPower = uint128(uint256(superior.stakingPower).add(superiorIncreSP));
        superior.credit = uint128(uint256(superior.credit).add(superiorIncreCredit));

        _totalStakingPower = _totalStakingPower.add(stakingPower).add(superiorIncreSP);
    }

    function _redeem(UserInfo storage from, uint256 stakingPower) internal {
        from.stakingPower = uint128(uint256(from.stakingPower).sub(stakingPower));

        uint256 userCreditSP = DecimalMath.divFloor(from.credit, alpha);
        if(from.stakingPower > userCreditSP) {
            from.stakingPower = uint128(uint256(from.stakingPower).sub(userCreditSP));
        } else {
            userCreditSP = from.stakingPower;
            from.stakingPower = 0;
        }
        from.creditDebt = from.creditDebt.add(from.credit);
        from.credit = 0;

        // superior decrease sp = min(stakingPower*0.1, from.superiorSP)
        uint256 superiorDecreSP = DecimalMath.mulFloor(stakingPower, _superiorRatio);
        superiorDecreSP = from.superiorSP <= superiorDecreSP ? from.superiorSP : superiorDecreSP;
        from.superiorSP = uint128(uint256(from.superiorSP).sub(superiorDecreSP));
        uint256 superiorDecreCredit = DecimalMath.mulFloor(superiorDecreSP, alpha);

        UserInfo storage superior = userInfo[from.superior];
        if(superiorDecreCredit > superior.creditDebt) {
            uint256 dec = DecimalMath.divFloor(superior.creditDebt, alpha);
            superiorDecreSP = dec >= superiorDecreSP ? 0 : superiorDecreSP.sub(dec);
            superiorDecreCredit = superiorDecreCredit.sub(superior.creditDebt);
            superior.creditDebt = 0;
        } else {
            superior.creditDebt = superior.creditDebt.sub(superiorDecreCredit);
            superiorDecreCredit = 0;
            superiorDecreSP = 0;
        }
        uint256 creditSP = DecimalMath.divFloor(superior.credit, alpha);

        if (superiorDecreSP >= creditSP) {
            superior.credit = 0;
            superior.stakingPower = uint128(uint256(superior.stakingPower).sub(creditSP));
        } else {
            superior.credit = uint128(
                uint256(superior.credit).sub(superiorDecreCredit)
            );
            superior.stakingPower = uint128(uint256(superior.stakingPower).sub(superiorDecreSP));
        }

        _totalStakingPower = _totalStakingPower.sub(stakingPower).sub(superiorDecreSP).sub(userCreditSP);
    }

    function _transfer(
        address from,
        address to,
        uint256 vDsgAmount
    ) internal canTransfer balanceEnough(from, vDsgAmount) {
        require(from != address(0), "transfer from the zero address");
        require(to != address(0), "transfer to the zero address");
        require(from != to, "transfer from same with to");

        uint256 stakingPower = DecimalMath.divFloor(vDsgAmount * _dsgRatio, alpha);

        UserInfo storage fromUser = userInfo[from];
        UserInfo storage toUser = userInfo[to];

        _redeem(fromUser, stakingPower);
        _mint(toUser, stakingPower);

        emit Transfer(from, to, vDsgAmount);
    }

     function getCirculationSupply() public view returns (uint256 supply) {
        supply = IERC20(_dsgToken).totalSupply();
    }
}