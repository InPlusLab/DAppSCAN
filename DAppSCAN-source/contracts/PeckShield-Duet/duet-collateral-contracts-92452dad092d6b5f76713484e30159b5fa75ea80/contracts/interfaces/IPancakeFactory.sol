interface IPancakeFactory {
  function getPair(address tokenA, address tokenB) external view returns (address pair);
}