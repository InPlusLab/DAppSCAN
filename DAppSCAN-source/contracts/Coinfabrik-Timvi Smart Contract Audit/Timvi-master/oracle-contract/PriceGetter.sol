pragma solidity 0.4.25;

import '../contracts/helpers/Address.sol';

interface Aggregator {
    function currentAnswer() external view returns(uint256);
    function updatedHeight() external view returns(uint256);
}

contract PriceGetter {
    using Address for address;

    Aggregator aggr;

    uint256 public expiration;

    constructor() public {
        if (address(0x79fEbF6B9F76853EDBcBc913e6aAE8232cFB9De9).isContract()) {
            // mainnet
            aggr = Aggregator(0x79fEbF6B9F76853EDBcBc913e6aAE8232cFB9De9);
            expiration = 120;
        } else if (address(0x0Be00A19538Fac4BE07AC360C69378B870c412BF).isContract()) {
            // ropsten
            aggr = Aggregator(0x0Be00A19538Fac4BE07AC360C69378B870c412BF);
            expiration = 4000;
        } else if (address(0x1AddCFF77Ca0F032c7dCA322fd8bFE61Cae66A62).isContract()) {
            // rinkeby
            aggr = Aggregator(0x1AddCFF77Ca0F032c7dCA322fd8bFE61Cae66A62);
            expiration = 1000;
        } else revert();
    }

    function ethUsdPrice() public view returns (uint256) {
        require(block.number - aggr.updatedHeight() < expiration, "Oracle data are outdated");
        return aggr.currentAnswer() / 1000;
    }
}
