/**
 * @title: Idle Rebalancer contract
 * @summary: Used for calculating amounts to lend on each implemented protocol.
 *           This implementation works with Compound and Fulcrum only,
 *           when a new protocol will be added this should be replaced
 * @author: William Bergamo, idle.finance
 */
pragma solidity 0.5.11;

import "../interfaces/CERC20.sol";
import "../interfaces/iERC20Fulcrum.sol";
import "../interfaces/ILendingProtocol.sol";
import "../interfaces/WhitePaperInterestRateModel.sol";

import "@openzeppelin/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

contract IdleRebalancerMock is Ownable {
  using SafeMath for uint256;
  address public idleToken;
  // protocol token (cToken) address
  address public cToken;
  // protocol token (iToken) address
  address public iToken;
  // cToken protocol wrapper IdleCompound
  address public cWrapper;
  // iToken protocol wrapper IdleFulcrum
  address public iWrapper;
  // max % difference between next supply rate of Fulcrum and Compound
  uint256 public maxRateDifference; // 10**17 -> 0.1 %
  // max % difference between off-chain user supplied params for rebalance and actual amount to be rebalanced
  uint256 public maxSupplyedParamsDifference; // 100000 -> 0.001%
  // max number of recursive calls for bisection algorithm
  uint256 public maxIterations;
  address[] public _tokenAddresses;
  uint256[] public _amounts;

  /**
   * @param _cToken : cToken address
   * @param _iToken : iToken address
   * @param _cWrapper : cWrapper address
   * @param _iWrapper : iWrapper address
   */
  constructor(address _cToken, address _iToken, address _cWrapper, address _iWrapper) public {
    cToken = _cToken;
    iToken = _iToken;
    cWrapper = _cWrapper;
    iWrapper = _iWrapper;
    maxRateDifference = 10**17; // 0.1%
    maxSupplyedParamsDifference = 100000; // 0.001%
    maxIterations = 30;
  }

  /**
   * Throws if called by any account other than IdleToken contract.
   */
  modifier onlyIdle() {
    require(msg.sender == idleToken, "Ownable: caller is not IdleToken contract");
    _;
  }

  // onlyOwner
  /**
   * sets idleToken address
   * @param _idleToken : idleToken address
   */
  function setIdleToken(address _idleToken)
    external onlyOwner {
      idleToken = _idleToken;
  }

  // onlyOwner
  /**
   * sets cToken address
   * @param _cToken : cToken address
   */
  function setCToken(address _cToken)
    external onlyOwner {
      cToken = _cToken;
  }

  /**
   * sets iToken address
   * @param _iToken : iToken address
   */
  function setIToken(address _iToken)
    external onlyOwner {
      iToken = _iToken;
  }

  /**
   * sets cToken wrapper address
   * @param _cWrapper : cToken wrapper address
   */
  function setCTokenWrapper(address _cWrapper)
    external onlyOwner {
      cWrapper = _cWrapper;
  }

  /**
   * sets iToken wrapper address
   * @param _iWrapper : iToken wrapper address
   */
  function setITokenWrapper(address _iWrapper)
    external onlyOwner {
      iWrapper = _iWrapper;
  }

  /**
   * sets maxIterations for bisection recursive calls
   * @param _maxIterations : max rate difference in percentage scaled by 10**18
   */
  function setMaxIterations(uint256 _maxIterations)
    external onlyOwner {
      maxIterations = _maxIterations;
  }

  /**
   * sets maxRateDifference
   * @param _maxDifference : max rate difference in percentage scaled by 10**18
   */
  function setMaxRateDifference(uint256 _maxDifference)
    external onlyOwner {
      maxRateDifference = _maxDifference;
  }

  /**
   * sets maxSupplyedParamsDifference
   * @param _maxSupplyedParamsDifference : max rate difference in percentage scaled by 10**18
   */
  function setMaxSupplyedParamsDifference(uint256 _maxSupplyedParamsDifference)
    external onlyOwner {
      maxSupplyedParamsDifference = _maxSupplyedParamsDifference;
  }
  // end onlyOwner

  /**
   * Used by IdleToken contract to calculate the amount to be lended
   * on each protocol in order to get the best available rate for all funds.
   *
   * @return tokenAddresses : array with all token addresses used,
   *                          currently [cTokenAddress, iTokenAddress]
   * @return amounts : array with all amounts for each protocol in order,
   *                   currently [amountCompound, amountFulcrum]
   */
  function calcRebalanceAmounts(uint256[] calldata)
    external view onlyIdle
    returns (address[] memory, uint256[] memory)
  {

    return (_tokenAddresses, _amounts);
  }
  /**
   * Used by IdleToken contract to check if provided amounts
   * causes the rates of Fulcrum and Compound to be balanced
   * (counting a tolerance)
   *
   * @param rebalanceParams : first element is the total amount to be rebalanced,
   *                   the rest is an array with all amounts for each protocol in order,
   *                   currently [amountCompound, amountFulcrum]
   * @param paramsCompound : array with all params (except for the newDAIAmount)
   *                          for calculating next supply rate of Compound
   * @param paramsFulcrum : array with all params (except for the newDAIAmount)
   *                          for calculating next supply rate of Fulcrum
   * @return bool : if provided amount correctly rebalances the pool
   */
  function checkRebalanceAmounts(
    uint256[] memory rebalanceParams,
    uint256[] memory paramsCompound,
    uint256[] memory paramsFulcrum
  )
    internal view
    returns (bool, uint256[] memory checkedAmounts)
  {
    // This is the amount that should be rebalanced no more no less
    uint256 actualAmountToBeRebalanced = rebalanceParams[0]; // n
    // interest is earned between when tx was submitted and when it is mined so params sent by users
    // should always be slightly less than what should be rebalanced
    uint256 totAmountSentByUser;
    for (uint8 i = 1; i < rebalanceParams.length; i++) {
      totAmountSentByUser = totAmountSentByUser.add(rebalanceParams[i]);
    }

    // check if amounts sent from user are less than actualAmountToBeRebalanced and
    // at most `actualAmountToBeRebalanced - 0.001% of (actualAmountToBeRebalanced)`
    if (totAmountSentByUser > actualAmountToBeRebalanced ||
        totAmountSentByUser.add(totAmountSentByUser.div(maxSupplyedParamsDifference)) < actualAmountToBeRebalanced) {
      return (false, new uint256[](2));
    }

    uint256 interestToBeSplitted = actualAmountToBeRebalanced.sub(totAmountSentByUser);

    // sets newDAIAmount for each protocol
    paramsCompound[9] = rebalanceParams[1].add(interestToBeSplitted.div(2));
    paramsFulcrum[5] = rebalanceParams[2].add(interestToBeSplitted.div(2));

    // calculate next rates with amountCompound and amountFulcrum

    // For Fulcrum see https://github.com/bZxNetwork/bZx-monorepo/blob/development/packages/contracts/extensions/loanTokenization/contracts/LoanToken/LoanTokenLogicV3.sol#L1418
    // fulcrumUtilRate = fulcrumBorrow.mul(10**20).div(assetSupply);
    uint256 currFulcRate = (paramsFulcrum[1].mul(10**20).div(paramsFulcrum[2])) > 90 ether ?
      ILendingProtocol(iWrapper).nextSupplyRate(paramsFulcrum[5]) :
      ILendingProtocol(iWrapper).nextSupplyRateWithParams(paramsFulcrum);
    uint256 currCompRate = ILendingProtocol(cWrapper).nextSupplyRateWithParams(paramsCompound);
    bool isCompoundBest = currCompRate > currFulcRate;
    // |fulcrumRate - compoundRate| <= tolerance
    bool areParamsOk =
      (currFulcRate.add(maxRateDifference) >= currCompRate && isCompoundBest) ||
      (currCompRate.add(maxRateDifference) >= currFulcRate && !isCompoundBest);

    uint256[] memory actualParams = new uint256[](2);
    actualParams[0] = paramsCompound[9];
    actualParams[1] = paramsFulcrum[5];

    return (areParamsOk, actualParams);
  }

  /**
   * Internal implementation of our bisection algorithm
   *
   * @param amountCompound : amount to be lended in compound in current iteration
   * @param amountFulcrum : amount to be lended in Fulcrum in current iteration
   * @param tolerance : max % difference between next supply rate of Fulcrum and Compound
   * @param currIter : current iteration
   * @param maxIter : max number of iterations
   * @param n : amount of underlying tokens (eg. DAI) to rebalance
   * @param paramsCompound : array with all params (except for the newDAIAmount)
   *                          for calculating next supply rate of Compound
   * @param paramsFulcrum : array with all params (except for the newDAIAmount)
   *                          for calculating next supply rate of Fulcrum
   * @return amounts : array with all amounts for each protocol in order,
   *                   currently [amountCompound, amountFulcrum]
   */
  function bisectionRec(
    uint256 amountCompound, uint256 amountFulcrum,
    uint256 tolerance, uint256 currIter, uint256 maxIter, uint256 n,
    uint256[] memory paramsCompound,
    uint256[] memory paramsFulcrum
  )
    internal view
    returns (uint256[] memory amounts) {

    // sets newDAIAmount for each protocol
    paramsCompound[9] = amountCompound;
    paramsFulcrum[5] = amountFulcrum;

    // calculate next rates with amountCompound and amountFulcrum

    // For Fulcrum see https://github.com/bZxNetwork/bZx-monorepo/blob/development/packages/contracts/extensions/loanTokenization/contracts/LoanToken/LoanTokenLogicV3.sol#L1418
    // fulcrumUtilRate = fulcrumBorrow.mul(10**20).div(assetSupply);

    uint256 currFulcRate = (paramsFulcrum[1].mul(10**20).div(paramsFulcrum[2])) > 90 ether ?
      ILendingProtocol(iWrapper).nextSupplyRate(amountFulcrum) :
      ILendingProtocol(iWrapper).nextSupplyRateWithParams(paramsFulcrum);

    uint256 currCompRate = ILendingProtocol(cWrapper).nextSupplyRateWithParams(paramsCompound);
    bool isCompoundBest = currCompRate > currFulcRate;

    // bisection interval update, we choose to halve the smaller amount
    uint256 step = amountCompound < amountFulcrum ? amountCompound.div(2) : amountFulcrum.div(2);

    // base case
    // |fulcrumRate - compoundRate| <= tolerance
    if (
      ((currFulcRate.add(tolerance) >= currCompRate && isCompoundBest) ||
      (currCompRate.add(tolerance) >= currFulcRate && !isCompoundBest)) ||
      currIter >= maxIter
    ) {
      amounts = new uint256[](2);
      amounts[0] = amountCompound;
      amounts[1] = amountFulcrum;
      return amounts;
    }

    return bisectionRec(
      isCompoundBest ? amountCompound.add(step) : amountCompound.sub(step),
      isCompoundBest ? amountFulcrum.sub(step) : amountFulcrum.add(step),
      tolerance, currIter + 1, maxIter, n,
      paramsCompound, // paramsCompound[9] would be overwritten on next iteration
      paramsFulcrum // paramsFulcrum[5] would be overwritten on next iteration
    );
  }


  function _setCalcAmounts(address[] memory _tokenAddressesLocal, uint256[] memory _amountsLocal) public {
    _tokenAddresses = _tokenAddressesLocal;
    _amounts = _amountsLocal;
  }

  // Fake method to make bisectionRec public and testable
  function bisectionRecPublic(
    uint256 amountCompound, uint256 amountFulcrum,
    uint256 tolerance, uint256 currIter, uint256 maxIter, uint256 n,
    uint256[] memory paramsCompound,
    uint256[] memory paramsFulcrum
  )
    public view
    returns (uint256[] memory)
  {
    return bisectionRec(
      amountCompound, amountFulcrum,
      tolerance, currIter, maxIter, n,
      paramsCompound, paramsFulcrum
    );
  }

  // Fake method to make checkRebalanceAmounts public and testable
  function checkRebalanceAmountsPublic(
    uint256[] memory rebalanceParams,
    uint256[] memory paramsCompound,
    uint256[] memory paramsFulcrum
  )
    public view
    returns (bool, uint256[] memory)
  {
    return checkRebalanceAmounts(
      rebalanceParams,
      paramsCompound,
      paramsFulcrum
    );
  }
}
