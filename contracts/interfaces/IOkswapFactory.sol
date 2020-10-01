pragma solidity >=0.5.0;

interface IOkswapFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function teamAmount() external view returns (uint);
    function vcAmount() external view returns (uint);
    function isBonusPair(address) external view returns (bool);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);
    function changeSetter(address) external;
    function setFeeHolder(address) external;
    function setBurnHolder(address) external;
    function setVcHolder(address) external;

    function pairCodeHash() external pure returns (bytes32);
    function addBonusPair(uint, uint, address, address, bool) external ;
    function getBonusConfig(address) external view returns (uint, uint,address,address,address,address);
    function getElac() external view returns (uint, uint);
    function setElac(uint,uint) external;
    function updateTeamAmount(uint) external;
    function updateVcAmount(uint) external;
    function realize(address,uint) external;

    function getSysCf() external view returns (uint);
}
