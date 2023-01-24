// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";
import "../lib/ConveyorTickMath.sol";
import "../../lib/interfaces/uniswap-v3/IQuoter.sol";
import "../LimitOrderSwapRouter.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;

    function makePersistent(address) external;

    function createSelectFork(string calldata, uint256)
        external
        returns (uint256);

    function rollFork(uint256 forkId, uint256 blockNumber) external;

    function activeFork() external returns (uint256);
}

contract ConveyorTickMathTest is DSTest {
    //Initialize test contract instances
    ConveyorTickMathWrapper conveyorTickMath;
    SwapRouterWrapper swapRouter;
    IQuoter iQuoter;
    //Swap helper
    Swap swapHelper;
    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address poolAddress = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
    //Test Pool addresses
    address daiWethPoolV3 = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
    address usdcWethPoolV3 = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    uint32 constant MAX_U32 = 2**32 - 1;

    //Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    // bytes32 _sushiHexDem =
    //     hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [
        _uniswapV2HexDem,
        // _sushiHexDem,
        _uniswapV2HexDem
    ];
    address[] _dexFactories = [
        _uniV2FactoryAddress,
        // _sushiFactoryAddress,
        _uniV3FactoryAddress
    ];
    bool[] _isUniV2 = [
        true,
        //  true,
        false
    ];
    address _uniV2Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    uint256 forkId;

    function setUp() public {
        swapHelper = new Swap(_uniV2Address, WETH);
        //Initalize cheatCodes
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        //Iniialize ConveyorTickMath contract wrapper
        conveyorTickMath = new ConveyorTickMathWrapper();
        //Initialize the v3 quoter
        iQuoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
        //Initialize the Sw

        swapRouter = new SwapRouterWrapper(_hexDems, _dexFactories, _isUniV2);
        cheatCodes.makePersistent(address(swapRouter));
        cheatCodes.makePersistent(address(conveyorTickMath));
    }

    ///@notice Test simulateAmountOutOnSqrtPriceX96 Quoted Amount out calculation.
    ///@dev This tests the case when swapping token0 for token1 in the v3 pool.
    function testSimulateAmountOutOnSqrtPriceX96__ZeroForOneFalse(
        uint128 _alphaX
    ) public {
        bool run = true;
        if (_alphaX == 0) {
            run = false;
        }

        if (run) {
            int24 tickSpacing = IUniswapV3Pool(daiWethPoolV3).tickSpacing();
            address token0 = IUniswapV3Pool(daiWethPoolV3).token0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();

            //Get the expected amountOut in Dai from the v3 quoter.
            uint256 amountOutExpected = iQuoter.quoteExactInputSingle(
                WETH,
                DAI,
                3000,
                _alphaX,
                TickMath.MAX_SQRT_RATIO - 1
            );
            (uint128 amountOutToValidate,)=
                conveyorTickMath._simulateAmountOutOnSqrtPriceX96(
                    token0,
                    WETH,
                    daiWethPoolV3,
                    _alphaX,
                    tickSpacing,
                    liquidity,
                    3000
                
            );

          
            assertEq(amountOutToValidate, amountOutExpected);
        }
    }

    ///@notice Test simulateAmountOutOnSqrtPriceX96 Quoted Amount out calculation.
    ///@dev This tests the case when swapping token1 for token0 in the v3 pool.
    function testSimulateAmountOutOnSqrtPriceX96__ZeroForOneTrue(
        uint128 _alphaX
    ) public {
        if (_alphaX > 0) {
            int24 tickSpacing = IUniswapV3Pool(daiWethPoolV3).tickSpacing();
            address token0 = IUniswapV3Pool(daiWethPoolV3).token0();
            uint128 liquidity = IUniswapV3Pool(daiWethPoolV3).liquidity();

            //Get the expected amountOut in Dai from the v3 quoter.
            uint256 amountOutExpected = iQuoter.quoteExactInputSingle(
                DAI,
                WETH,
                3000,
                _alphaX,
                TickMath.MIN_SQRT_RATIO + 1
            );

            //Get the quoted amount out from _simulateAmountOutOnSqrtPriceX96.
            (uint128 amountOutToValidate,)=conveyorTickMath._simulateAmountOutOnSqrtPriceX96(
                    token0,
                    DAI,
                    daiWethPoolV3,
                    _alphaX,
                    tickSpacing,
                    liquidity,
                    3000
                
            );

            assertEq(amountOutToValidate, amountOutExpected);
        }
    }

    ///@notice Test simulateAmountOutOnSqrtPriceX96 on an input quantity that crosses to the next initialized tick in the pool.
    ///@dev The liquditiy should change in the pool upon crossing a tick, and therefore the exchange rate.
    function testSimulateAmountOutOnSqrtPriceX96CrossTick(uint128 _alphaX)
        public
    {
        bool run = true;
        if (_alphaX == 0) {
            run = false;
        }
        if (run) {
            //Get the tick spacing on the pool
            int24 tickSpacing = IUniswapV3Pool(usdcWethPoolV3).tickSpacing();
            //Get token0 from the pool
            address token0 = IUniswapV3Pool(usdcWethPoolV3).token0();
            //Get the liquidity currently in the pool.
            uint128 liquidity = IUniswapV3Pool(usdcWethPoolV3).liquidity();

            //Calculate the simulated amountOut to validate accuracy on from ConveyorTickMath
            (uint128 amountOutToValidate,) = 
                conveyorTickMath._simulateAmountOutOnSqrtPriceX96(
                    token0,
                    WETH,
                    usdcWethPoolV3,
                    _alphaX,
                    tickSpacing,
                    liquidity,
                    500
                );
            

            //Get the expected amountOut in Dai from the v3 quoter.
            uint256 amountOutExpected = iQuoter.quoteExactInputSingle(
                WETH,
                USDC,
                500,
                _alphaX,
                TickMath.MAX_SQRT_RATIO - 1
            );

            assertEq(amountOutToValidate, amountOutExpected);
        }
    }

    //Block: 15233771
    function testFromSqrtX96() public {
        forkId = cheatCodes.activeFork();
        cheatCodes.rollFork(forkId, 15233771);

        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        //USDC spot price
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddress)
            .slot0();

        uint256 priceUSDC = conveyorTickMath._fromSqrtX96(
            sqrtPriceX96,
            true,
            tokenIn,
            tokenOut
        );
        uint256 priceWETH = conveyorTickMath._fromSqrtX96(
            sqrtPriceX96,
            false,
            tokenIn,
            tokenOut
        );
        console.log(priceWETH);
        assertEq(194786572365129798010721349067079679, priceUSDC);
        assertEq(594456218574771757927683806232862281426471, priceWETH);
    }

    receive() external payable {}
}

contract ConveyorTickMathWrapper is ConveyorTickMath {
    function _fromSqrtX96(
        uint160 sqrtPriceX96,
        bool token0IsReserve0,
        address token0,
        address token1
    ) public view returns (uint256 priceX128) {
        return fromSqrtX96(sqrtPriceX96, token0IsReserve0, token0, token1);
    }

    function _simulateAmountOutOnSqrtPriceX96(
        address token0,
        address tokenIn,
        address lpAddressAToWeth,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) public view returns (uint128 amountOut, uint160 sqrtPriceX96Next) {
        return
            simulateAmountOutOnSqrtPriceX96(
                token0,
                tokenIn,
                lpAddressAToWeth,
                amountIn,
                tickSpacing,
                liquidity,
                fee
            );
    }
}

contract SwapRouterWrapper is LimitOrderSwapRouter {
    constructor(
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    ) LimitOrderSwapRouter(_initBytecodes, _dexFactories, _isUniV2) {}

    function swapV3(
        address _lp,
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _receiver,
        address _sender
    ) public returns (uint256) {
        return
            _swapV3(
                _lp,
                _tokenIn,
                _tokenOut,
                _fee,
                _amountIn,
                _amountOutMin,
                _receiver,
                _sender
            );
    }
}
