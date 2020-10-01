pragma solidity =0.6.12;

import './OKSwapERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IOkswapFactory.sol';
import './interfaces/IUniswapV2Callee.sol';
import './interfaces/IUniswapV2Pair.sol';
import './interfaces/IOKra.sol';
import './libraries/SafeMath.sol';


contract OKSwapPair is OKSwapERC20 {

    address public okra;

    using SafeMathUniswap  for uint;
    using UQ112x112 for uint224;

    uint public   constant MINIMUM_LIQUIDITY = 10 ** 3;
    uint public constant BONUS_BLOCKNUM = 36000;
    uint public constant BASECAP = 5120 * (10 ** 18);
    uint public constant TEAM_BLOCKNUM = 13200000;
    uint private constant TEAM_CAP = 15000000 * (10 ** 18);
    uint private constant VC_CAP = 5000000 * (10 ** 18);
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public   factory;
    address public   token0;
    address public  token1;
    

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public  price0CumulativeLast;
    uint public  price1CumulativeLast;
    uint public  kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    mapping(address => uint) public userPools;

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'OKSwap: LOCKED');
        unlocked = 0;
        _;
        unlocked = 1;
    }


    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'OKSwap: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);
    event Harvest(address indexed sender, uint amount);

    constructor() public {
        factory = msg.sender;
    }

    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1, address _okra) external {
        require(msg.sender == factory, 'OKSwap: FORBIDDEN');
        // sufficient check
        token0 = _token0;
        token1 = _token1;
        okra = _okra;
    }


    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {
        require(balance0 <= uint112(- 1) && balance1 <= uint112(- 1), 'OKSwap: OVERFLOW');
        uint32 blockTimestamp = uint32(block.timestamp % 2 ** 32);
        uint32 timeElapsed = blockTimestamp - blockTimestampLast;
        // overflow is desired
        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {
//        address feeTo = IOkswapFactory(factory).feeTo();
        (,,,address feeHolder,address burnHolder,) = IOkswapFactory(factory).getBonusConfig(address(this));
        feeOn = true;
        uint _kLast = kLast;
        // gas savings
        if (_kLast != 0) {
            uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
            uint rootKLast = Math.sqrt(_kLast);
            if (rootK > rootKLast) {
                uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                uint denominator = rootK.mul(5).add(rootKLast);
                uint liquidity = numerator.mul(2) / denominator;
                if (liquidity > 0) {
                    if (feeHolder != address(0)) _mint(feeHolder, liquidity);
                    if (burnHolder != address(0)) _mint(burnHolder, liquidity);
                }
            }
        }

    }

    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        uint balance0 = IERC20Uniswap(token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(token1).balanceOf(address(this));
        uint amount0 = balance0.sub(_reserve0);
        uint amount1 = balance1.sub(_reserve1);
        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply;
        // gas savings, must be defined here since totalSupply can update in _mintFee
        if (_totalSupply == 0) {
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);
            _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }
        require(liquidity > 0, 'OKSwap: INSUFFICIENT_LIQUIDITY_MINTED');
        if (IOkswapFactory(factory).isBonusPair(address(this))) {
            uint startAtBlock = userPools[to];
            if (startAtBlock > 0) {
                uint liquid = balanceOf[to];
                userPools[to] = startAtBlock.mul(liquid).add(block.number.mul(liquidity)) / liquid.add(liquidity);
            }else{
                userPools[to] = block.number;
            }
           
        }
        _mint(to, liquidity);
        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1);
        // reserve0 and reserve1 are up-to-date
        
        emit Mint(msg.sender, amount0, amount1);
    }

    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to,address user,bool emerg) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        // gas savings
        address _token0 = token0;
        // gas savings
        address _token1 = token1;
        // gas savings
        uint balance0 = IERC20Uniswap(_token0).balanceOf(address(this));
        uint balance1 = IERC20Uniswap(_token1).balanceOf(address(this));
        uint liquidity = balanceOf[address(this)];

        bool feeOn = _mintFee(_reserve0, _reserve1);
        uint _totalSupply = totalSupply;
        // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply;
        amount1 = liquidity.mul(balance1) / _totalSupply;
        // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'OKSwap: INSUFFICIENT_LIQUIDITY_BURNED');
        _burn(address(this), liquidity);
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20Uniswap(_token0).balanceOf(address(this));
        balance1 = IERC20Uniswap(_token1).balanceOf(address(this));

        _update(balance0, balance1, _reserve0, _reserve1);
        if (feeOn) kLast = uint(reserve0).mul(reserve1);
        // reserve0 and reserve1 are up-to-date

        if (!emerg) _getHarvest(user);

        emit Burn(msg.sender, amount0, amount1, to);
    }
    
    function _getHarvest(address _to) private {

            (uint based,,,,,) = IOkswapFactory(factory).getBonusConfig(address(this));
            if (based > 0 ) {
                uint harvestLiquid = balanceOf[_to];
                uint pendingAmount = _getHarvestAmount(harvestLiquid, based, userPools[_to]);
                uint max = BASECAP + IOKra(okra).balanceOf(_to);
                uint mintAmount = pendingAmount <= max ? pendingAmount : max;
                userPools[_to] = block.number;
                IOkswapFactory(factory).realize(_to, mintAmount);

                emit Harvest(msg.sender, mintAmount);
            }

    }

    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint[3] memory amount, address to, bytes calldata data) external lock {
        uint amount0Out = amount[0];
        uint amount1Out = amount[1];
        uint amountIn = amount[2];

        require(amount0Out > 0 || amount1Out > 0, 'OKSwap: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves();
        // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'OKSwap: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;
        {// scope for _token{0,1}, avoids stack too deep errors
            require(to != token0 && to != token1, 'OKSwap: INVALID_TO');
            if (amount0Out > 0) {_safeTransfer(token0, to, amount0Out);assign(amount0Out,token1,token0,amountIn,to);}
            if (amount1Out > 0) {_safeTransfer(token1, to, amount1Out);assign(amount1Out,token0,token1,amountIn,to);}
            if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
            balance0 = IERC20Uniswap(token0).balanceOf(address(this));
            balance1 = IERC20Uniswap(token1).balanceOf(address(this));

        }

        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'OKSwap: INSUFFICIENT_INPUT_AMOUNT');
        {// scope for reserve{0,1}Adjusted, avoids stack too deep errors
            uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
            uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
            require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000 ** 2), 'UniswapV2: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);

        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }
    

    function assign(uint amountOut,address tokenIn, address tokenOut, uint amountIn, address to) private {
        (,,address tokenAddress,,,) = IOkswapFactory(factory).getBonusConfig(address(this));
        if (tokenAddress == tokenIn) {
            _tradeBonus(tokenIn, amountIn, to);
        }else if (tokenAddress == tokenOut) {
            _tradeBonus(tokenIn, amountOut, to);
        } 
    }
    
    
    function _tradeBonus(address _token, uint _amountOut, address _to) private {
        IOkswapFactory _factory = IOkswapFactory(factory);
        if (_token != address(okra) && _factory.isBonusPair(address(this))) {
            uint sysCf = _factory.getSysCf();
            (uint elac0,uint elac1) = IOkswapFactory(factory).getElac();
            (,uint share, ,address teamHolder,,address vcHolder) = _factory.getBonusConfig(address(this));
            uint tradeMint = _amountOut.div(100).mul(share).div(sysCf);
            tradeMint = tradeMint.mul(elac0).div(elac1);
            _realize(tradeMint,_to,teamHolder,vcHolder);
        }
    }


    function _realize(uint tradeMint,address _to,address teamHolder,address vcHolder) private {
        if (tradeMint > 0) {
            IOkswapFactory(factory).realize(_to, tradeMint);
            uint syncMint = tradeMint.div(100).mul(2);
            uint vcNum = IOkswapFactory(factory).vcAmount();
            uint vcMint = vcNum.add(syncMint) >= VC_CAP ? VC_CAP.sub(vcNum) : syncMint;
            if (vcMint > 0 && vcHolder != address(0)) {
                IOkswapFactory(factory).updateVcAmount(vcMint);
                IOkswapFactory(factory).realize(vcHolder, vcMint);
            }
            if (block.number >= TEAM_BLOCKNUM) {
                uint teamNum = IOkswapFactory(factory).teamAmount();
                syncMint = syncMint.mul(3);
                uint teamMint = teamNum.add(syncMint) >= TEAM_CAP ? TEAM_CAP.sub(teamNum) : syncMint;
                if (teamMint > 0 && teamHolder != address(0)){
                    IOkswapFactory(factory).updateTeamAmount(teamMint);
                    IOkswapFactory(factory).realize(teamHolder, teamMint);
                }
            }

            emit Harvest(msg.sender, tradeMint);
        }
    }

    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0;
        address _token1 = token1;
        _safeTransfer(_token0, to, IERC20Uniswap(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20Uniswap(_token1).balanceOf(address(this)).sub(reserve1));
    }


    function _getHarvestAmount(uint _amount, uint _based, uint _startBlock) private view returns (uint){
        uint sysCf = IOkswapFactory(factory).getSysCf();
        (uint elac0,uint elac1) = IOkswapFactory(factory).getElac();

        uint point = (block.number.sub(_startBlock)) / BONUS_BLOCKNUM;

        uint mintAmount;
        if (point == 0) {
            mintAmount = _amount.mul(block.number.sub(_startBlock));
        } else if (point == 1) {
            uint amount0 = _amount.mul(BONUS_BLOCKNUM);
            uint amount1 = _amount.mul(block.number.sub(_startBlock).sub(BONUS_BLOCKNUM));
            mintAmount = amount0.add(amount1.mul(2));
        } else {
            uint amount0 = _amount.mul(BONUS_BLOCKNUM);
            uint amount1 = _amount.mul(block.number.sub(_startBlock).sub(BONUS_BLOCKNUM).sub(BONUS_BLOCKNUM));
            mintAmount = amount0.add(amount0.mul(2)).add(amount1.mul(3));
        }

        return mintAmount.mul(elac0).div(elac1).div(sysCf).mul(100).div(_based);
    }


    function getblock(address _user) external view returns (uint256){
        return userPools[_user];
    }

    function pending(address _user) external view returns (uint256) {
        (uint _based,,,,,) = IOkswapFactory(factory).getBonusConfig(address(this));
        uint sysCf = IOkswapFactory(factory).getSysCf();
        (uint elac0,uint elac1) = IOkswapFactory(factory).getElac();
        uint _startBlock = userPools[_user];
        uint _amount = balanceOf[_user];
        require(block.number >= _startBlock, "OKSwap:FAIL");

        uint point = (block.number.sub(_startBlock)) / BONUS_BLOCKNUM;
        uint mintAmount;
        if (point == 0) {
            mintAmount = _amount.mul(block.number.sub(_startBlock));
        } else if (point == 1) {
            uint amount0 = _amount.mul(BONUS_BLOCKNUM);
            uint amount1 = _amount.mul(block.number.sub(_startBlock).sub(BONUS_BLOCKNUM));
            mintAmount = amount0.add(amount1.mul(2));
        } else {
            uint amount0 = _amount.mul(BONUS_BLOCKNUM);
            uint amount1 = _amount.mul(block.number.sub(_startBlock).sub(BONUS_BLOCKNUM).sub(BONUS_BLOCKNUM));
            mintAmount = amount0.add(amount0.mul(2)).add(amount1.mul(3));
        }
        return mintAmount.mul(elac0).div(elac1).div(sysCf).mul(100).div(_based);
    }


    function harvestNow() external {
        address _to = msg.sender;
        (uint based,,,,, ) = IOkswapFactory(factory).getBonusConfig(address(this));
        require(based > 0, 'OKSwap: FAIL_BASED');
        uint _amount = balanceOf[_to];
        uint pendingAmount = _getHarvestAmount(_amount, based, userPools[_to]);
        uint max = BASECAP + IOKra(okra).balanceOf(_to);
        uint mintAmount = pendingAmount <= max ? pendingAmount : max;
        userPools[_to] = block.number;
        IOkswapFactory(factory).realize(_to, mintAmount);
        emit Harvest(msg.sender, mintAmount);
    }

    // force reserves to match balances
    function sync() external lock {
        _update(IERC20Uniswap(token0).balanceOf(address(this)), IERC20Uniswap(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
