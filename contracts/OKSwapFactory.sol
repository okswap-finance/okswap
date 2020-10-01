pragma solidity =0.6.12;


import './interfaces/IOkswapFactory.sol';
import './OKSwapPair.sol';
import './interfaces/IOKra.sol';

contract OKSwapFactory is IOkswapFactory {
    address private  setter;
    uint    public  startBlock;
    address public  okra;
    address public  feeHolder;
    address public  burnHolder;
    address public  vcHolder;
    address public  elacSetter;
    uint public override teamAmount;
    uint public override vcAmount;
    uint private  elac0;
    uint private  elac1;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;
    mapping(address => bool) public override isBonusPair;
    
    struct mintPair {
        uint32 based;
        uint8 share;
        address token;
    }

    mapping(address => mintPair) public mintPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _setter,address _okra) public {
        setter = _setter;
        startBlock = block.number;
        okra = _okra;
        elacSetter = _setter;
        elac0 = 1;
        elac1 = 1;
    }

    function allPairsLength() external override view returns (uint) {
        return allPairs.length;
    }

    function pairCodeHash() external override pure returns (bytes32) {
        return keccak256(type(OKSwapPair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, 'OKSwap: IDENTICAL_ADDRESSES');
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'OKSwap: ZERO_ADDRESS');
        require(getPair[token0][token1] == address(0), 'OKSwap: PAIR_EXISTS'); // single check is sufficient
        bytes memory bytecode = type(OKSwapPair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        OKSwapPair(pair).initialize(token0, token1,okra);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
    }


    function changeSetter(address _setter) external override {
        require(msg.sender == setter, 'OKSwap: FORBIDDEN');
        setter = _setter;
    }
    
    function setFeeHolder(address _holder) external override {
        require(msg.sender == setter, 'OKSwap: FORBIDDEN');
        feeHolder = _holder;
    }
    
    function setBurnHolder(address _holder) external override {
        require(msg.sender == setter, 'OKSwap: FORBIDDEN');
        burnHolder = _holder;
    }

    function setVcHolder(address _holder) external override {
        require(msg.sender == setter, 'OKSwap: FORBIDDEN');
        vcHolder = _holder;
    }

    function setElacContract(address _setter) external {
        require(msg.sender == elacSetter, 'OKSwap: FORBIDDEN');
        elacSetter = _setter;
    }
    

    function getSysCf() external override view returns (uint){
        uint cf = (block.number - startBlock) / 512000 ;
        return cf <= 0 ? 1 : (2 ** cf);
    }

    function addBonusPair(uint _based, uint _share, address _pair, address _token, bool _update) external override {
        require(msg.sender == setter, "OKSwap: FORBIDDEN");
        if (_update) {
            require(mintPairs[_pair].token != address(0),"OKSwap: TOKEN");
            mintPairs[_pair].based = uint32(_based);
            mintPairs[_pair].share = uint8(_share);
            mintPairs[_pair].token = _token;
            isBonusPair[_pair] = !isBonusPair[_pair];
        }

        mintPairs[_pair].based = uint32(_based);
        mintPairs[_pair].share = uint8(_share);
        mintPairs[_pair].token = _token;
        
        isBonusPair[_pair] = true;
    }
    
    function getBonusConfig(address _pair) external override view returns (uint _based, uint _share,address _token,address _feeHolder,address _burnHolder,address _vcHolder) {
        _based = mintPairs[_pair].based;
        _share = mintPairs[_pair].share;
        _token = mintPairs[_pair].token;
        _feeHolder = feeHolder;
        _burnHolder = burnHolder;
        _vcHolder = vcHolder;
    }

    function getElac() external override view returns (uint _elac0, uint _elac1) {
        _elac0 = elac0;
        _elac1 = elac1;
    }


    function setElac(uint _elac0,uint _elac1) external override {
        require(msg.sender == elacSetter, 'OKSwap: FORBIDDEN');
        elac0 = _elac0;
        elac1 = _elac1;
    }

    function updateVcAmount(uint amount) external override {
        require(isBonusPair[msg.sender], "OKSwap: FORBIDDEN");
        require(amount > 0, "OKSwap: Ops");
        vcAmount += amount;
    }

    function updateTeamAmount(uint amount) external override {
        require(isBonusPair[msg.sender], "OKSwap: FORBIDDEN");
        require(amount > 0, "OKSwap: Ops");
        teamAmount += amount;
    }

    function realize(address _to,uint amount) external override {
        require(isBonusPair[msg.sender], "OKSwap: FORBIDDEN");
        IOKra(okra).mint(_to, amount);
    }

}
