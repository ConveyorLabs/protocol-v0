// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";
import "../LimitOrderBook.sol";
import "../LimitOrderRouter.sol";
import "../LimitOrderQuoter.sol";
import "../../lib/interfaces/uniswap-v3/IQuoter.sol";

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
}

contract LimitOrderQuoterTest is DSTest {
    //Initialize limit-v0 contract for testing
    LimitOrderRouter limitOrderRouter;
    ExecutionWrapper limitOrderQuoter;

    LimitOrderSwapRouter orderRouter;
    //Initialize OrderBook
    LimitOrderBook orderBook;
    IQuoter iQuoter;
    ScriptRunner scriptRunner;

    Swap swapHelper;
    Swap swapHelperUniV2;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address TAXED_TOKEN = 0xE7eaec9Bca79d537539C00C58Ae93117fB7280b9; //
    address TAXED_TOKEN_1 = 0xe0a189C975e4928222978A74517442239a0b86ff; //
    address TAXED_TOKEN_2 = 0xd99793A840cB0606456916d1CF5eA199ED93Bf97; //6% tax CHAOS token 27
    address TAXED_TOKEN_3 = 0xcFEB09C3c5F0f78aD72166D55f9e6E9A60e96eEC;

    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    uint32 constant MAX_U32 = 2**32 - 1;

    //Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    // bytes32 _sushiHexDem =
    //     hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [
        _uniswapV2HexDem,
        // _sushiHexDem,
        bytes32(0)
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

    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000; //0.00001
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
    uint256 forkId;

    function setUp() public {
        scriptRunner = new ScriptRunner();
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        swapHelperUniV2 = new Swap(uniV2Addr, WETH);

        limitOrderQuoter = new ExecutionWrapper(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );
        cheatCodes.makePersistent(address(limitOrderQuoter));
        iQuoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    }

    //================================================================
    //======================= Order Simulation Unit Tests ============
    //================================================================
    function testFindBestTokenToTokenExecutionPrice() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;

        LimitOrderSwapRouter.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = LimitOrderSwapRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 36584244663945024000000000000000000000,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        LimitOrderSwapRouter.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice1 = LimitOrderSwapRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 36584244663945024000000000000000000001,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        LimitOrderSwapRouter.TokenToTokenExecutionPrice[]
            memory executionPrices = new LimitOrderSwapRouter.TokenToTokenExecutionPrice[](
                2
            );
        executionPrices[0] = tokenToTokenExecutionPrice;
        executionPrices[1] = tokenToTokenExecutionPrice1;

        uint256 bestPriceIndexBuy = limitOrderQuoter
            .findBestTokenToTokenExecutionPrice(executionPrices, true);
        uint256 bestPriceIndexSell = limitOrderQuoter
            .findBestTokenToTokenExecutionPrice(executionPrices, false);

        assertEq(bestPriceIndexBuy, 0);
        assertEq(bestPriceIndexSell, 1);
    }

    ///@notice Simulate AToBPrice Change V2 reserve tests
    function testSimulateAToBPriceChangeV2ReserveOutputs(uint112 _amountIn)
        public
    {
        uint112 reserveAIn = 7957765096999155822679329;
        uint112 reserveBIn = 4628057647836077568601;

        address pool = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        bool underflow;
        assembly {
            underflow := lt(reserveAIn, _amountIn)
        }

        if (!underflow) {
            if (_amountIn != 0) {
                (, uint128 reserveA, uint128 reserveB, ) = limitOrderQuoter
                    .simulateAToBPriceChange(
                        _amountIn,
                        reserveAIn,
                        reserveBIn,
                        pool,
                        true
                    );
                string memory path = "scripts/simulateNewReserves.py";
                string[] memory args = new string[](3);
                args[0] = uint2str(_amountIn);
                args[1] = uint2str(reserveAIn);
                args[2] = uint2str(reserveBIn);
                bytes memory outputReserveB = scriptRunner.runPythonScript(
                    path,
                    args
                );
                uint256 expectedReserveB = bytesToUint(outputReserveB);

                uint256 expectedReserveA = reserveAIn + _amountIn;

                assertEq(reserveA, expectedReserveA);

                //Adjust precision as python script has lower precision than ConveyorMath library
                assertEq(reserveB / 10**9, expectedReserveB / 10**9);
            }
        }
    }

    ///@notice Simulate AToB price change v2 spot price test
    function testSimulateAToBPriceChangeV2SpotPrice(uint64 _amountIn) public {
        uint112 reserveAIn = 7957765096999155822679329;
        uint112 reserveBIn = 4628057647836077568601;

        address pool = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
        bool underflow;
        assembly {
            underflow := lt(reserveAIn, _amountIn)
        }

        if (!underflow) {
            if (_amountIn != 0) {
                (uint256 spotPrice, , , ) = limitOrderQuoter
                    .simulateAToBPriceChange(
                        _amountIn,
                        reserveAIn,
                        reserveBIn,
                        pool,
                        true
                    );
                string memory path = "scripts/simulateSpotPriceChange.py";
                string[] memory args = new string[](3);
                args[0] = uint2str(_amountIn);
                args[1] = uint2str(reserveAIn);
                args[2] = uint2str(reserveBIn);
                bytes memory spotOut = scriptRunner.runPythonScript(path, args);
                uint256 spotPriceExpected = bytesToUint(spotOut);
                //Adjust precision since python script is lower precision, 128.128 >>75 still leaves 53 bits of precision decimals and 128 bits of precision integers
                assertEq(spotPrice >> 75, spotPriceExpected >> 75);
            }
        }
    }

    function testSimulateAmountOutV3_Fuzz1_ZeroForOneTrue(uint64 _alphaX)
        public
    {
        bool run = true;
        if (_alphaX == 0) {
            run = false;
        }

        if (run) {
            address poolAddress = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            address tokenIn = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddress)
                .slot0();
            uint128 liquidity = IUniswapV3Pool(poolAddress).liquidity();
            uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceX96,
                liquidity,
                _alphaX,
                true
            );
            uint256 amountOut = iQuoter.quoteExactInputSingle(
                tokenIn,
                WETH,
                3000,
                _alphaX,
                sqrtPriceLimitX96
            );
            uint256 amountOutMin = limitOrderQuoter
                .calculateAmountOutMinAToWeth(
                    poolAddress,
                    _alphaX,
                    0,
                    3000,
                    tokenIn
                );

            assertEq(amountOut, amountOutMin);
        }
    }

    function testSimulateAmountOutV3_Fuzz1_ZeroForOneFalse(uint64 _alphaX)
        public
    {
        bool run = true;
        if (_alphaX == 0) {
            run = false;
        }

        if (run) {
            address poolAddress = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            address tokenOut = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddress)
                .slot0();
            uint128 liquidity = IUniswapV3Pool(poolAddress).liquidity();
            uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceX96,
                liquidity,
                _alphaX,
                false
            );
            uint256 amountOut = iQuoter.quoteExactInputSingle(
                WETH,
                tokenOut,
                3000,
                _alphaX,
                sqrtPriceLimitX96
            );
            uint256 amountOutMin = limitOrderQuoter
                .calculateAmountOutMinAToWeth(
                    poolAddress,
                    _alphaX,
                    0,
                    3000,
                    WETH
                );

            assertEq(amountOut, amountOutMin);
        }
    }

    //Block # 15233771
    ///@notice Simulate WethToB price change v2 test
    function testSimulateWethToBPriceChangeV2() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        //Weth/Uni
        LimitOrderSwapRouter.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = LimitOrderSwapRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 0,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        (uint256 newSpotPriceB, , ) = limitOrderQuoter
            .simulateWethToBPriceChange(
                5000000000000000000,
                tokenToTokenExecutionPrice
            );
        assertEq(newSpotPriceB, 63714967732803596813954797656252367241216);
    }

    //Block # 15233771
    ///@notice Simulate AToWeth price change V2 test
    function testSimulateAToWethPriceChangeV2() public {
        uint8[] memory decimals = new uint8[](2);
        decimals[0] = 18;
        decimals[1] = 18;
        //Weth/Uni
        LimitOrderSwapRouter.TokenToTokenExecutionPrice
            memory tokenToTokenExecutionPrice = LimitOrderSwapRouter
                .TokenToTokenExecutionPrice({
                    aToWethReserve0: 8014835235973799779324680,
                    aToWethReserve1: 4595913824638810919416,
                    wethToBReserve0: 1414776373420924126438282,
                    wethToBReserve1: 7545889283955278550784,
                    price: 0,
                    lpAddressAToWeth: 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11,
                    lpAddressWethToB: 0xd3d2E2692501A5c9Ca623199D38826e513033a17
                });

        (uint256 newSpotPriceA, , , uint128 amountOut) = limitOrderQuoter
            .simulateAToWethPriceChange(
                50000000000000000000000,
                tokenToTokenExecutionPrice
            );
        assertEq(newSpotPriceA, 192714735056741134836410079523110912);
        assertEq(amountOut, 28408586008574759898);
    }

    ///@notice Helper function to convert string to int for ffi tests
    function uint2str(uint256 _i) internal pure returns (string memory str) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 length;
        while (j != 0) {
            length++;
            j /= 10;
        }
        bytes memory bstr = new bytes(length);
        uint256 k = length;
        j = _i;
        while (j != 0) {
            bstr[--k] = bytes1(uint8(48 + (j % 10)));
            j /= 10;
        }
        str = string(bstr);
    }

    ///@notice Helper to convert bytes to uint for ffi tests
    function bytesToUint(bytes memory b) internal pure returns (uint256) {
        uint256 number;
        for (uint256 i = 0; i < b.length; i++) {
            number =
                number +
                uint256(uint8(b[i])) *
                (2**(8 * (b.length - (i + 1))));
        }
        return number;
    }
}

contract ExecutionWrapper is LimitOrderQuoter {
    constructor(address _weth) LimitOrderQuoter(_weth) {}

    function simulateAToBPriceChange(
        uint128 alphaX,
        uint128 reserveA,
        uint128 reserveB,
        address pool,
        bool isTokenToWeth
    )
        public
        returns (
            uint256,
            uint128,
            uint128,
            uint128
        )
    {
        return
            _simulateAToBPriceChange(
                alphaX,
                reserveA,
                reserveB,
                pool,
                isTokenToWeth
            );
    }

    function simulateAToWethPriceChange(
        uint128 alphaX,
        LimitOrderSwapRouter.TokenToTokenExecutionPrice memory executionPrice
    )
        public
        returns (
            uint256 newSpotPriceA,
            uint128 newReserveAToken,
            uint128 newReserveAWeth,
            uint128 amountOut
        )
    {
        return _simulateAToWethPriceChange(alphaX, executionPrice);
    }

    function simulateWethToBPriceChange(
        uint128 alphaX,
        LimitOrderSwapRouter.TokenToTokenExecutionPrice memory executionPrice
    )
        public
        returns (
            uint256 newSpotPriceB,
            uint128 newReserveBWeth,
            uint128 newReserveBToken
        )
    {
        return _simulateWethToBPriceChange(alphaX, executionPrice);
    }
}
