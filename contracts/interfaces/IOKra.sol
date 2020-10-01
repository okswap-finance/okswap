pragma solidity >=0.5.0;

interface IOKra {
    function  mint(address _to, uint256 _amount) external returns (uint);
    function balanceOf(address owner) external view returns (uint);
}