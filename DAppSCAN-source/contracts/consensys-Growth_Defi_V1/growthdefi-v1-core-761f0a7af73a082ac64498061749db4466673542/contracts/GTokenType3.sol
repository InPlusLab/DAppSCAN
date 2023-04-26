// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.6.0;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import { GToken } from "./GToken.sol";
import { GVoting } from "./GVoting.sol";
import { GFormulae } from "./GFormulae.sol";
import { G } from "./G.sol";

/**
 * @notice This contract implements the functionality for the gToken Type 3.
 *         It has a higher deposit/withdrawal fee when compared to other
 *         gTokens (10%). Half of the collected fee used to reward token
 *         holders while the other half is burned along with the same proportion
 *         of the reserve. It is used in the implementation of stkGRO.
 */
contract GTokenType3 is ERC20, ReentrancyGuard, GToken, GVoting
{
	using SafeMath for uint256;

	uint256 constant DEPOSIT_FEE = 10e16; // 10%
	uint256 constant WITHDRAWAL_FEE = 10e16; // 10%

	uint256 constant VOTING_ROUND_INTERVAL = 1 days;

	address public immutable override reserveToken;

	mapping (address => address) public override candidate;

	mapping (address => uint256) private votingRound;
	mapping (address => uint256[2]) private voting;

	/**
	 * @dev Constructor for the gToken contract.
	 * @param _name The ERC-20 token name.
	 * @param _symbol The ERC-20 token symbol.
	 * @param _decimals The ERC-20 token decimals.
	 * @param _reserveToken The ERC-20 token address to be used as reserve
	 *                      token (e.g. GRO for sktGRO).
	 */
	constructor (string memory _name, string memory _symbol, uint8 _decimals, address _reserveToken)
		ERC20(_name, _symbol) public
	{
		_setupDecimals(_decimals);
		reserveToken = _reserveToken;
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         received/minted upon depositing to the contract.
	 * @param _cost The amount of reserve token being deposited.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _depositFee The current deposit fee as obtained by depositFee().
	 * @return _netShares The net amount of shares being received.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcDepositSharesFromCost(uint256 _cost, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee) public pure override returns (uint256 _netShares, uint256 _feeShares)
	{
		return GFormulae._calcDepositSharesFromCost(_cost, _totalReserve, _totalSupply, _depositFee);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reserve token to be deposited in order to receive the desired
	 *         amount of shares.
	 * @param _netShares The amount of this gToken shares to receive.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _depositFee The current deposit fee as obtained by depositFee().
	 * @return _cost The cost, in the reserve token, to be paid.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcDepositCostFromShares(uint256 _netShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _depositFee) public pure override returns (uint256 _cost, uint256 _feeShares)
	{
		return GFormulae._calcDepositCostFromShares(_netShares, _totalReserve, _totalSupply, _depositFee);
	}

	/**
	 * @notice Allows for the beforehand calculation of shares to be
	 *         given/burned upon withdrawing from the contract.
	 * @param _cost The amount of reserve token being withdrawn.
	 * @param _totalReserve The reserve balance as obtained by totalReserve()
	 * @param _totalSupply The shares supply as obtained by totalSupply()
	 * @param _withdrawalFee The current withdrawal fee as obtained by withdrawalFee()
	 * @return _grossShares The total amount of shares being deducted,
	 *                      including fees.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcWithdrawalSharesFromCost(uint256 _cost, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee) public pure override returns (uint256 _grossShares, uint256 _feeShares)
	{
		return GFormulae._calcWithdrawalSharesFromCost(_cost, _totalReserve, _totalSupply, _withdrawalFee);
	}

	/**
	 * @notice Allows for the beforehand calculation of the amount of
	 *         reserve token to be withdrawn given the desired amount of
	 *         shares.
	 * @param _grossShares The amount of this gToken shares to provide.
	 * @param _totalReserve The reserve balance as obtained by totalReserve().
	 * @param _totalSupply The shares supply as obtained by totalSupply().
	 * @param _withdrawalFee The current withdrawal fee as obtained by withdrawalFee().
	 * @return _cost The cost, in the reserve token, to be received.
	 * @return _feeShares The fee amount of shares being deducted.
	 */
	function calcWithdrawalCostFromShares(uint256 _grossShares, uint256 _totalReserve, uint256 _totalSupply, uint256 _withdrawalFee) public pure override returns (uint256 _cost, uint256 _feeShares)
	{
		return GFormulae._calcWithdrawalCostFromShares(_grossShares, _totalReserve, _totalSupply, _withdrawalFee);
	}

	/**
	 * @notice Provides the amount of reserve tokens currently being help by
	 *         this contract.
	 * @return _totalReserve The amount of the reserve token corresponding
	 *                       to this contract's balance.
	 */
	function totalReserve() public view virtual override returns (uint256 _totalReserve)
	{
		return G.getBalance(reserveToken);
	}

	/**
	 * @notice Provides the current minting/deposit fee. This fee is
	 *         applied to the amount of this gToken shares being created
	 *         upon deposit. The fee defaults to 10%.
	 * @return _depositFee A percent value that accounts for the percentage
	 *                     of shares being minted at each deposit that be
	 *                     collected as fee.
	 */
	function depositFee() public view override returns (uint256 _depositFee) {
		return DEPOSIT_FEE;
	}

	/**
	 * @notice Provides the current burning/withdrawal fee. This fee is
	 *         applied to the amount of this gToken shares being redeemed
	 *         upon withdrawal. The fee defaults to 10%.
	 * @return _withdrawalFee A percent value that accounts for the
	 *                        percentage of shares being burned at each
	 *                        withdrawal that be collected as fee.
	 */
	function withdrawalFee() public view override returns (uint256 _withdrawalFee) {
		return WITHDRAWAL_FEE;
	}

	/**
	 * @notice Provides the number of votes a given candidate has at the end
	 *         of the previous voting interval. The interval is 24 hours
	 *         and resets at 12AM UTC. See _transferVotes().
	 * @param _candidate The candidate for which we want to know the number
	 *                   of delegated votes.
	 * @return _votes The candidate number of votes. It is the sum of the
	 *                balances of the voters that have him as cadidate at
	 *                the end of the previous voting interval.
	 */
	function votes(address _candidate) public view override returns (uint256 _votes)
	{
		uint256 _votingRound = block.timestamp.div(VOTING_ROUND_INTERVAL);
		// if the candidate balance was last updated the current round
		// uses the backup instead (position 1), otherwise uses the most
		// up-to-date balance (position 0)
		return voting[_candidate][votingRound[_candidate] < _votingRound ? 0 : 1];
	}

	/**
	 * @notice Performs the minting of gToken shares upon the deposit of the
	 *         reserve token. The actual number of shares being minted can
	 *         be calculated using the calcDepositSharesFromCost function.
	 *         In every deposit, 10% of the shares is retained in terms of
	 *         deposit fee. The fee amount and half of its equivalent
	 *         reserve amount are immediately burned. The funds will be
	 *         pulled in by this contract, therefore they must be previously
	 *         approved.
	 * @param _cost The amount of reserve token being deposited in the
	 *              operation.
	 */
	function deposit(uint256 _cost) public override nonReentrant
	{
		address _from = msg.sender;
		require(_cost > 0, "cost must be greater than 0");
		(uint256 _netShares, uint256 _feeShares) = GFormulae._calcDepositSharesFromCost(_cost, totalReserve(), totalSupply(), depositFee());
		require(_netShares > 0, "shares must be greater than 0");
		G.pullFunds(reserveToken, _from, _cost);
		_mint(_from, _netShares);
		_burnReserveFromShares(_feeShares.div(2));
	}

	/**
	 * @notice Performs the burning of gToken shares upon the withdrawal of
	 *         the reserve token. The actual amount of the reserve token to
	 *         be received can be calculated using the
	 *         calcWithdrawalCostFromShares function. In every withdrawal,
	 *         10% of the shares is retained in terms of withdrawal fee.
	 *         The fee amount and half of its equivalent reserve amount are
	 *         immediately burned.
	 * @param _grossShares The gross amount of this gToken shares being
	 *                     redeemed in the operation.
	 */
	function withdraw(uint256 _grossShares) public override nonReentrant
	{
		address _from = msg.sender;
		require(_grossShares > 0, "shares must be greater than 0");
		(uint256 _cost, uint256 _feeShares) = GFormulae._calcWithdrawalCostFromShares(_grossShares, totalReserve(), totalSupply(), withdrawalFee());
		require(_cost > 0, "cost must be greater than 0");
		_cost = G.min(_cost, G.getBalance(reserveToken));
		G.pushFunds(reserveToken, _from, _cost);
		_burn(_from, _grossShares);
		_burnReserveFromShares(_feeShares.div(2));
	}

	/**
	 * @notice Changes the voter's choice for candidate and vote delegation.
	 *         It is only going to be reflected in the voting by the next
	 *         interval. The interval is 24 hours and resets at 12AM UTC.
	 *         This function will emit a ChangeCandidate event.
	 * @param _newCandidate The new candidate chosen.
	 */
	function setCandidate(address _newCandidate) public override nonReentrant
	{
		address _voter = msg.sender;
		uint256 _votes = balanceOf(_voter);
		address _oldCandidate = candidate[_voter];
		candidate[_voter] = _newCandidate;
		_transferVotes(_oldCandidate, _newCandidate, _votes);
		emit ChangeCandidate(_voter, _oldCandidate, _newCandidate);
	}

	/**
	 * @dev Burns a given amount of shares worth of the reserve token.
	 *      See burnReserve().
	 * @param _grossShares The amount of shares for which the equivalent,
	 *                     in the reserve token, will be burned.
	 */
	function _burnReserveFromShares(uint256 _grossShares) internal virtual
	{
		// we use the withdrawal formula to calculated how much is burned (withdrawn) from the contract
		// since the fee is 0 using the deposit formula would yield the same amount
		(uint256 _feeCost,) = GFormulae._calcWithdrawalCostFromShares(_grossShares, totalReserve(), totalSupply(), 0);
		_burnReserve(_feeCost);
	}

	/**
	 * @dev Burns the given amount of the reserve token. The default behavior
	 *      of the function for general ERC-20 is to send the funds to
	 *      address(0), but that can be overriden by a subcontract.
	 * @param _reserveAmount The amount of the reserve token being burned.
	 */
	function _burnReserve(uint256 _reserveAmount) internal virtual
	{
		G.pushFunds(reserveToken, address(0), _reserveAmount);
	}

	/**
	 * @dev This hook is called whenever tokens are minted, burned and
	 *      transferred. This contract forbids token transfers by design.
	 *      Token minting and burning will be reflected in the additional
	 *      votes being credited or debited to the chosen candidate.
	 *      See _transferVotes().
	 * @param _from The provider of funds. Address 0 for minting.
	 * @param _to The receiver of funds. Address 0 for burning.
	 * @param _amount The amount being transfered.
	 */
	function _beforeTokenTransfer(address _from, address _to, uint256 _amount) internal override
	{
		require(_from == address(0) || _to == address(0), "transfer prohibited");
		address _oldCandidate = candidate[_from];
		address _newCandidate = candidate[_to];
		uint256 _votes = _amount;
		_transferVotes(_oldCandidate, _newCandidate, _votes);
	}

	/**
	 * @dev Implements the vote transfer logic. It will deduct the votes
	 *      from one candidate and credit it to another candidate. If
	 *      either of candidates is the 0 address, the the voter is either
	 *      setting its initial candidate or abstaining himself from voting.
	 *      The change is only reflected after the voting interval resets.
	 *      We use a 2 element array to keep track of votes. The amount on
	 *      position 0 is always the current vote count for the candidate.
	 *      The amount on position 1 is a backup that reflect the vote count
	 *      prior to the current round only if it has been updated for the
	 *      current round. We also record the last voting round where the
	 *      candidate balance was updated. If the last round is the current
	 *      then we use the backup value on position 1, otherwise we use
	 *      the most up to date value on position 0. This function will
	 *      emit a ChangeVotes event upon candidate vote balance change.
	 *      See _updateVotes().
	 * @param _oldCandidate The candidate to deduct votes from.
	 * @param _newCandidate The candidate to credit voter for.
	 * @param _votes the number of votes being transfered.
	 */
	function _transferVotes(address _oldCandidate, address _newCandidate, uint256 _votes) internal
	{
		if (_votes == 0) return;
		if (_oldCandidate == _newCandidate) return;
		if (_oldCandidate != address(0)) {
			// position 0 always has the most up-to-date balance
			uint256 _oldVotes = voting[_oldCandidate][0];
			uint256 _newVotes = _oldVotes.sub(_votes);
			// updates position 0 backing up the previous amount
			_updateVotes(_oldCandidate, _newVotes);
			emit ChangeVotes(_oldCandidate, _oldVotes, _newVotes);
		}
		if (_newCandidate != address(0)) {
			// position 0 always has the most up-to-date balance
			uint256 _oldVotes = voting[_newCandidate][0];
			uint256 _newVotes = _oldVotes.add(_votes);
			// updates position 0 backing up the previous amount
			_updateVotes(_newCandidate, _newVotes);
			emit ChangeVotes(_newCandidate, _oldVotes, _newVotes);
		}
	}

	/**
	 * @dev Updates the candidate's current vote balance (position 0) and
	 *      backs up the vote balance for the previous interval (position 1).
	 *      The routine makes sure we do not overwrite and corrupt the
	 *      backup if multiple vote updates happen within a single roung.
	 *      See _transferVotes().
	 * @param _candidate The candidate for which we are updating the votes.
	 * @param _votes The candidate's new vote balance.
	 */
	function _updateVotes(address _candidate, uint256 _votes) internal
	{
		uint256 _votingRound = block.timestamp.div(VOTING_ROUND_INTERVAL);
		// if the candidates voting round is not the current it means
		// we are updating the voting balance for the first time in
		// the current round, that is the only time we want to make a
		// backup of the vote balance for the previous roung
		if (votingRound[_candidate] < _votingRound) {
			votingRound[_candidate] = _votingRound;
			// position 1 is the backup if there are updates in
			// the current round
			voting[_candidate][1] = voting[_candidate][0];
		}
		// position 0 always hold the up-to-date vote balance
		voting[_candidate][0] = _votes;
	}
}
