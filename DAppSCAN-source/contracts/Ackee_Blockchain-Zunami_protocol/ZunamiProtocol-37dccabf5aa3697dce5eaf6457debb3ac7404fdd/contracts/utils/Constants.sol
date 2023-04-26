//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

library Constants {
    bytes32 internal constant USDC_TICKER = "usdc";
    bytes32 internal constant USDT_TICKER = "usdt";
    bytes32 internal constant DAI_TICKER = "dai";
    bytes32 internal constant CRV_TICKER = "a3CRV";

    uint256 internal constant CVX_BUSD_PID = 3;
    uint256 internal constant CVX_SUSD_PID = 4;
    uint256 internal constant CVX_USDK_PID = 12;
    uint256 internal constant CVX_USDN_PID = 13;
    uint256 internal constant CVX_MUSD_PID = 14;
    uint256 internal constant CVX_RSV_PID = 15;
    uint256 internal constant CVX_DUSD_PID = 17;
    uint256 internal constant CVX_AAVE_PID = 24;
    uint256 internal constant CVX_USDP_PID = 28;
    uint256 internal constant CVX_IRONBANK_PID = 29;
    uint256 internal constant CVX_TUSD_PID = 31;
    uint256 internal constant CVX_FRAX_PID = 32;
    uint256 internal constant CVX_LUSD_PID = 33;
    uint256 internal constant CVX_BUSDV2_PID = 34;
    uint256 internal constant CVX_MIM_PID = 40;
    uint256 internal constant CVX_OUSD_PID = 56;
    uint256 internal constant TRADE_DEADLINE = 2000;

    address internal constant CVX_ADDRESS =
        0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address internal constant CRV_ADDRESS =
        0xD533a949740bb3306d119CC777fa900bA034cd52;
    address internal constant USDC_ADDRESS =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant USDT_ADDRESS =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant DAI_ADDRESS =
        0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address internal constant TUSD_ADDRESS =
        0x0000000000085d4780B73119b644AE5ecd22b376;
    address internal constant SUSD_ADDRESS =
        0x57Ab1ec28D129707052df4dF418D58a2D46d5f51;
    address internal constant BUSD_ADDRESS =
        0x4Fabb145d64652a948d72533023f6E7A623C7C53;
    address internal constant OUSD_ADDRESS =
        0x2A8e1E676Ec238d8A992307B495b45B3fEAa5e86;
    address internal constant MUSD_ADDRESS =
        0xe2f2a5C287993345a840Db3B0845fbC70f5935a5;
    address internal constant MIM_ADDRESS =
        0x99D8a9C45b2ecA8864373A26D1459e3Dff1e17F3;
    address internal constant DUSD_ADDRESS =
        0x5BC25f649fc4e26069dDF4cF4010F9f706c23831;
    address internal constant LUSD_ADDRESS =
        0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address internal constant USDP_ADDRESS =
        0x1456688345527bE1f37E9e627DA0837D6f08C925;
    address internal constant USDN_ADDRESS =
        0x674C6Ad92Fd080e4004b2312b45f796a192D27a0;
    address internal constant USDK_ADDRESS =
        0x1c48f86ae57291F7686349F12601910BD8D470bb;
    address internal constant FRAX_ADDRESS =
        0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address internal constant RSV_ADDRESS =
        0x196f4727526eA7FB1e17b2071B3d8eAA38486988;
    address internal constant WETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant SUSHI_ROUTER_ADDRESS =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address internal constant SUSHI_CRV_WETH_ADDRESS =
        0x58Dc5a51fE44589BEb22E8CE67720B5BC5378009;
    address internal constant SUSHI_WETH_CVX_ADDRESS =
        0x05767d9EF41dC40689678fFca0608878fb3dE906;
    address internal constant SUSHI_WETH_USDT_ADDRESS =
        0x06da0fd433C1A5d7a4faa01111c044910A184553;
    address internal constant CVX_BOOSTER_ADDRESS =
         0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address internal constant CRV_3POOL_ADDRESS =
        0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address internal constant CRV_3POOL_LP_ADDRESS =
        0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;
    address internal constant CRV_AAVE_ADDRESS =
        0xDeBF20617708857ebe4F679508E7b7863a8A8EeE;
    address internal constant CRV_AAVE_LP_ADDRESS =
        0xFd2a8fA60Abd58Efe3EeE34dd494cD491dC14900;
    address internal constant CVX_AAVE_REWARDS_ADDRESS =
        0xE82c1eB4BC6F92f85BF7EB6421ab3b882C3F5a7B;
    address internal constant CVX_AAVE_EXTRA_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant AAVE_EXTRA_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant AAVE_EXTRA_PAIR_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant CRV_IRONBANK_ADDRESS =
        0x2dded6Da1BF5DBdF597C45fcFaa3194e53EcfeAF;
    address internal constant CRV_IRONBANK_LP_ADDRESS =
        0x5282a4eF67D9C33135340fB3289cc1711c13638C;
    address internal constant CVX_IRONBANK_REWARDS_ADDRESS =
        0x3E03fFF82F77073cc590b656D42FceB12E4910A8;
    address internal constant CRV_TUSD_ADDRESS =
        0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1;
    address internal constant CRV_TUSD_LP_ADDRESS =
        0xEcd5e75AFb02eFa118AF914515D6521aaBd189F1;
    address internal constant CVX_TUSD_REWARDS_ADDRESS =
        0x308b48F037AAa75406426dACFACA864ebd88eDbA;
    address internal constant CRV_SUSD_ADDRESS =
        0xA5407eAE9Ba41422680e2e00537571bcC53efBfD;
    address internal constant CRV_SUSD_LP_ADDRESS =
        0xC25a3A3b969415c80451098fa907EC722572917F;
    address internal constant CVX_SUSD_REWARDS_ADDRESS =
        0x22eE18aca7F3Ee920D01F25dA85840D12d98E8Ca;
    address internal constant CVX_SUSD_EXTRA_ADDRESS =
        0x81fCe3E10D12Da6c7266a1A169c4C96813435263;
    address internal constant SUSD_EXTRA_ADDRESS =
        0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F;
    address internal constant SUSD_EXTRA_PAIR_ADDRESS =
        0xA1d7b2d891e3A1f9ef4bBC5be20630C2FEB1c470;
    address internal constant CRV_USDK_ADDRESS =
        0x3E01dD8a5E1fb3481F0F589056b428Fc308AF0Fb;
    address internal constant CRV_USDK_LP_ADDRESS =
        0x97E2768e8E73511cA874545DC5Ff8067eB19B787;
    address internal constant CVX_USDK_REWARDS_ADDRESS =
        0xa50e9071aCaD20b31cd2bbe4dAa816882De82BBe;
    address internal constant CRV_USDP_ADDRESS =
        0x42d7025938bEc20B69cBae5A77421082407f053A;
    address internal constant CRV_USDP_LP_ADDRESS =
        0x7Eb40E450b9655f4B3cC4259BCC731c63ff55ae6;
    address internal constant CVX_USDP_REWARDS_ADDRESS =
        0x24DfFd1949F888F91A0c8341Fc98a3F280a782a8;
    address internal constant CVX_USDP_EXTRA_ADDRESS =
        0x5F91615268bE6b4aDD646b2560785B8F17dccBb4;
    address internal constant USDP_EXTRA_ADDRESS =
        0x92E187a03B6CD19CB6AF293ba17F2745Fd2357D5;
    address internal constant USDP_EXTRA_PAIR_ADDRESS =
        0x69aa90C6cD099BF383Bd9A0ac29E61BbCbF3b8D9;
    address internal constant CRV_BUSD_ADDRESS =
        0x79a8C46DeA5aDa233ABaFFD40F3A0A2B1e5A4F27;
    address internal constant CRV_BUSD_LP_ADDRESS =
        0x3B3Ac5386837Dc563660FB6a0937DFAa5924333B;
    address internal constant CVX_BUSD_REWARDS_ADDRESS =
        0x602c4cD53a715D8a7cf648540FAb0d3a2d546560;
    address internal constant CRV_BUSDV2_ADDRESS =
        0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a;
    address internal constant CRV_BUSDV2_LP_ADDRESS =
        0x4807862AA8b2bF68830e4C8dc86D0e9A998e085a;
    address internal constant CVX_BUSDV2_REWARDS_ADDRESS =
        0xbD223812d360C9587921292D0644D18aDb6a2ad0;
    address internal constant CRV_OUSD_ADDRESS =
        0x87650D7bbfC3A9F10587d7778206671719d9910D;
    address internal constant CRV_OUSD_LP_ADDRESS =
        0x87650D7bbfC3A9F10587d7778206671719d9910D;
    address internal constant CRV_OUSD_EXTRA_ADDRESS =
        0x8A05801c1512F6018e450b0F69e9Ca7b985fCea3;
    address internal constant OUSD_EXTRA_ADDRESS =
        0x8207c1FfC5B6804F6024322CcF34F29c3541Ae26;
    address internal constant OUSD_EXTRA_PAIR_ADDRESS =
        0x72ea6Ca0D47b337f1EA44314d9d90E2A897eDaF5;
    address internal constant CVX_OUSD_REWARDS_ADDRESS =
        0x7D536a737C13561e0D2Decf1152a653B4e615158;
    address internal constant CRV_USDN_ADDRESS =
        0x0f9cb53Ebe405d49A0bbdBD291A65Ff571bC83e1;
    address internal constant CRV_USDN_LP_ADDRESS =
        0x4f3E8F405CF5aFC05D68142F3783bDfE13811522;
    address internal constant CVX_USDN_REWARDS_ADDRESS =
        0x4a2631d090e8b40bBDe245e687BF09e5e534A239;
    address internal constant CRV_LUSD_ADDRESS =
        0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA;
    address internal constant CRV_LUSD_LP_ADDRESS =
        0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA;
    address internal constant CVX_LUSD_REWARDS_ADDRESS =
        0x2ad92A7aE036a038ff02B96c88de868ddf3f8190;
    address internal constant CVX_LUSD_EXTRA_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant LUSD_EXTRA_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant LUSD_EXTRA_PAIR_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant CRV_MUSD_ADDRESS =
        0x8474DdbE98F5aA3179B3B3F5942D724aFcdec9f6;
    address internal constant CRV_MUSD_LP_ADDRESS =
        0x1AEf73d49Dedc4b1778d0706583995958Dc862e6;
    address internal constant CVX_MUSD_REWARDS_ADDRESS =
        0xDBFa6187C79f4fE4Cda20609E75760C5AaE88e52;
    address internal constant CVX_MUSD_EXTRA_ADDRESS =
        0x93A5C724c4992FCBDA6b96F06fa15EB8B5c485b7;
    address internal constant MUSD_EXTRA_ADDRESS =
        0xa3BeD4E1c75D00fa6f4E5E6922DB7261B5E9AcD2;
    address internal constant MUSD_EXTRA_PAIR_ADDRESS =
        0x663242D053057f317A773D7c262B700616d0b9A0;
    address internal constant CRV_DUSD_ADDRESS =
        0x8038C01A0390a8c547446a0b2c18fc9aEFEcc10c;
    address internal constant CRV_DUSD_LP_ADDRESS =
        0x3a664Ab939FD8482048609f652f9a0B0677337B9;
    address internal constant CVX_DUSD_REWARDS_ADDRESS =
        0x1992b82A8cCFC8f89785129D6403b13925d6226E;
    address internal constant CVX_DUSD_EXTRA_ADDRESS =
        0x666F8eEE6FD6839853993977CC86a7A51425673C;
    address internal constant DUSD_EXTRA_ADDRESS =
        0x20c36f062a31865bED8a5B1e512D9a1A20AA333A;
    address internal constant DUSD_EXTRA_PAIR_ADDRESS =
        0x663242D053057f317A773D7c262B700616d0b9A0;
    address internal constant CRV_RSV_ADDRESS =
        0xC18cC39da8b11dA8c3541C598eE022258F9744da;
    address internal constant CRV_RSV_LP_ADDRESS =
        0xC2Ee6b0334C261ED60C72f6054450b61B8f18E35;
    address internal constant CVX_RSV_REWARDS_ADDRESS =
        0xedfCCF611D7c40F43e77a1340cE2C29EEEC27205;
    address internal constant CVX_RSV_EXTRA_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant RSV_EXTRA_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant RSV_EXTRA_PAIR_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant CRV_FRAX_ADDRESS =
        0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    address internal constant CRV_FRAX_LP_ADDRESS =
        0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    address internal constant CVX_FRAX_REWARDS_ADDRESS =
        0xB900EF131301B307dB5eFcbed9DBb50A3e209B2e;
    address internal constant CVX_FRAX_EXTRA_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant FRAX_EXTRA_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant FRAX_EXTRA_PAIR_ADDRESS =
        0x0000000000000000000000000000000000000000;
    address internal constant CRV_MIM_ADDRESS =
        0x5a6A4D54456819380173272A5E8E9B9904BdF41B;
    address internal constant CRV_MIM_LP_ADDRESS =
        0x5a6A4D54456819380173272A5E8E9B9904BdF41B;
    address internal constant CVX_MIM_REWARDS_ADDRESS =
        0xFd5AbF66b003881b88567EB9Ed9c651F14Dc4771;
    address internal constant CVX_MIM_EXTRA_ADDRESS =
        0x69a92f1656cd2e193797546cFe2EaF32EACcf6f7;
    address internal constant MIM_EXTRA_ADDRESS =
        0x090185f2135308BaD17527004364eBcC2D37e5F6;
    address internal constant MIM_EXTRA_PAIR_ADDRESS =
        0xb5De0C3753b6E1B4dBA616Db82767F17513E6d4E;
}
