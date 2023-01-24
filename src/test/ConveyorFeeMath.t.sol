// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "../lib/ConveyorFeeMath.sol";
import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v3/ISwapRouter.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "../LimitOrderSwapRouter.sol";
import "./utils/ScriptRunner.sol";
import "../../lib/libraries/Uniswap/LowGasSafeMath.sol";
import "../../lib/libraries/Uniswap/FullMath.sol";
import "../LimitOrderBook.sol";
import "../LimitOrderQuoter.sol";
import "../ConveyorExecutor.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract ConveyorFeeMathTest is DSTest {
    CheatCodes cheatCodes;

    ScriptRunner scriptRunner;

    LimitOrderExecutorWrapper limitOrderExecutor;

    //Factory and router address's
    address _uniV2Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    //uniV3 swap router
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    //weth
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //pancake, sushi, uni create2 factory initialization bytecode
    bytes32 _sushiHexDem =
        0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;
    bytes32 _uniswapV2HexDem =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    //Dex[] dexes array of dex structs
    bytes32[] _hexDems = [_uniswapV2HexDem, _sushiHexDem, _uniswapV2HexDem];
    address[] _dexFactories = [
        _uniV2FactoryAddress,
        _sushiFactoryAddress,
        _uniV3FactoryAddress
    ];
    bool[] _isUniV2 = [true, true, false];

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        scriptRunner = new ScriptRunner();

        limitOrderExecutor = new LimitOrderExecutorWrapper(
            _hexDems,
            _dexFactories,
            _isUniV2
        );
    }

    // ///@notice Test to calculate the Order Reward beacon
    function testCalculateOrderRewardBeacon(uint64 wethValue) public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (!(wethValue < 10**18)) {
            uint128 fee = limitOrderExecutor.calculateFee(
                wethValue,
                usdc,
                weth
            );
            //1.8446744073709550
            (, uint128 rewardBeacon) = ConveyorFeeMath.calculateReward(
                fee,
                wethValue
            );

            //Pack the args
            string memory path = "scripts/calculateRewardBeacon.py";
            string[] memory args = new string[](3);
            args[0] = uint2str(fee);
            args[1] = uint2str(wethValue);

            //Python script output, off by a small decimals precision
            bytes memory spotOut = scriptRunner.runPythonScript(path, args);
            uint256 beaconRewardExpected = bytesToUint(spotOut);

            //Assert the values
            assertEq(rewardBeacon / 10**3, beaconRewardExpected / 10**3);
        }
    }

    ///@notice Test calculate Conveyor Reward
    function testCalculateOrderRewardConveyor(uint64 wethValue) public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        if (!(wethValue < 10**18)) {
            uint128 fee = limitOrderExecutor.calculateFee(
                wethValue,
                usdc,
                weth
            );
            //1.8446744073709550
            (uint128 rewardConveyor, ) = ConveyorFeeMath.calculateReward(
                fee,
                wethValue
            );

            //Pack the arguments
            string memory path = "scripts/calculateRewardConveyor.py";
            string[] memory args = new string[](3);
            args[0] = uint2str(fee);
            args[1] = uint2str(wethValue);

            //Get the bytes out from the python script
            bytes memory spotOut = scriptRunner.runPythonScript(path, args);
            uint256 conveyorRewardExpected = bytesToUint(spotOut);

            //Assert the outputs with a precision buffer on fuzz
            assertEq(rewardConveyor / 10**3, conveyorRewardExpected / 10**3);
        }
    }

    //================================================================
    //======================= Helper functions =======================
    //================================================================

    ///@notice Helper function to convert bytes to uint
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

    ///@notice Helper function to convert a uint to a string
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
}

//wrapper around LimitOrderSwapRouter to expose internal functions for testing
contract LimitOrderExecutorWrapper is LimitOrderSwapRouter {
    constructor(
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    ) LimitOrderSwapRouter(_initBytecodes, _dexFactories, _isUniV2) {}

    function getV3PoolFee(address pairAddress)
        public
        view
        returns (uint24 poolFee)
    {
        return getV3PoolFee(pairAddress);
    }

    function lpIsNotUniV3(address lp) public returns (bool) {
        return _lpIsNotUniV3(lp);
    }

    // receive() external payable {}

    function swapV2(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _receiver,
        address _sender
    ) public returns (uint256) {
        return
            _swapV2(
                _tokenIn,
                _tokenOut,
                _lp,
                _amountIn,
                _amountOutMin,
                _receiver,
                _sender
            );
    }

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

    function calculateV2SpotPrice(
        address token0,
        address token1,
        address _factory,
        bytes32 _initBytecode
    ) public view returns (SpotReserve memory spRes, address poolAddress) {
        return _calculateV2SpotPrice(token0, token1, _factory, _initBytecode);
    }

    function calculateV3SpotPrice(
        address token0,
        address token1,
        uint24 FEE,
        address _factory
    ) public returns (SpotReserve memory, address) {
        return _calculateV3SpotPrice(token0, token1, FEE, _factory);
    }

    function swap(
        address _tokenIn,
        address _tokenOut,
        address _lp,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _receiver,
        address _sender
    ) public returns (uint256 amountReceived) {
        return
            _swap(
                _tokenIn,
                _tokenOut,
                _lp,
                _fee,
                _amountIn,
                _amountOutMin,
                _receiver,
                _sender
            );
    }
}
