// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

interface IIssuer {
    // Views
    function anySynthOrSNXRateIsInvalid()
        external
        view
        returns (bool anyRateInvalid);

    function availableCurrencyKeys() external view returns (bytes32[] memory);

    function availableSynthCount() external view returns (uint256);

    function canBurnSynths(address account) external view returns (bool);

    function collateral(address account) external view returns (uint256);

    function collateralisationRatio(address issuer)
        external
        view
        returns (uint256);

    function collateralisationRatioAndAnyRatesInvalid(address _issuer)
        external
        view
        returns (uint256 cratio, bool anyRateIsInvalid);

    function debtBalanceOf(address issuer, bytes32 currencyKey)
        external
        view
        returns (uint256 debtBalance);

    function issuanceRatio() external view returns (uint256);

    function lastIssueEvent(address account) external view returns (uint256);

    function maxIssuableSynths(address issuer)
        external
        view
        returns (uint256 maxIssuable);

    function minimumStakeTime() external view returns (uint256);

    function remainingIssuableSynths(address issuer)
        external
        view
        returns (
            uint256 maxIssuable,
            uint256 alreadyIssued,
            uint256 totalSystemDebt
        );

    function synthsByAddress(address synthAddress)
        external
        view
        returns (bytes32);

    function totalIssuedSynths(bytes32 currencyKey, bool excludeEtherCollateral)
        external
        view
        returns (uint256);

    function transferableSynthetixAndAnyRateIsInvalid(
        address account,
        uint256 balance
    ) external view returns (uint256 transferable, bool anyRateIsInvalid);

    // Restricted: used internally to Synthetix
    function issueSynths(address from, uint256 amount) external;

    function issueSynthsOnBehalf(
        address issueFor,
        address from,
        uint256 amount
    ) external;

    function issueMaxSynths(address from) external;

    function issueMaxSynthsOnBehalf(address issueFor, address from) external;

    function burnSynths(address from, uint256 amount) external;

    function burnSynthsOnBehalf(
        address burnForAddress,
        address from,
        uint256 amount
    ) external;

    function burnSynthsToTarget(address from) external;

    function burnSynthsToTargetOnBehalf(address burnForAddress, address from)
        external;
}
