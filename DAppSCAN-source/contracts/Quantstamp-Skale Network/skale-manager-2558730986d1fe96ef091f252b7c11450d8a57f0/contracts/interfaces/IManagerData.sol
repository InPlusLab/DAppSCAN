pragma solidity 0.5.16;

interface IManagerData {
    function setMinersCap(uint newMinersCap) external;
    function setStageTimeAndStageNodes(uint newStageNodes) external;
    function minersCap() external view returns (uint);
    function startTime() external view returns (uint32);
    function stageTime() external view returns (uint32);
    function stageNodes() external view returns (uint);
}