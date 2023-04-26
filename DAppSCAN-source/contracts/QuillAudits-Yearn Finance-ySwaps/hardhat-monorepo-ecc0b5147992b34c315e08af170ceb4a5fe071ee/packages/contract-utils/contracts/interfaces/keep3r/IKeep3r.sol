// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4 <0.9.0;

interface IKeep3r {
  event Keep3rSet(address _keep3r);
  event Keep3rRequirementsSet(address _bond, uint256 _minBond, uint256 _earned, uint256 _age, bool _onlyEOA);

  function keep3r() external view returns (address _keep3r);

  function bond() external view returns (address _bond);

  function minBond() external view returns (uint256 _minBond);

  function earned() external view returns (uint256 _earned);

  function age() external view returns (uint256 _age);

  function onlyEOA() external view returns (bool _onlyEOA);

  function setKeep3r(address _keep3r) external;

  function setKeep3rRequirements(
    address _bond,
    uint256 _minBond,
    uint256 _earned,
    uint256 _age,
    bool _onlyEOA
  ) external;
}
