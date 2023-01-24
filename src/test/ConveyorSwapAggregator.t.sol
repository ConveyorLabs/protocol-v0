// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Swap.sol";
import "../interfaces/IConveyorSwapAggregator.sol";
import "../lib/ConveyorTickMath.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function createSelectFork(string calldata, uint256)
        external
        returns (uint256);

    function rollFork(uint256 forkId, uint256 blockNumber) external;

    function activeFork() external returns (uint256);

    function makePersistent(address) external;
}

contract ConveyorSwapAggregatorTest is DSTest {
    IConveyorSwapAggregator conveyorSwapAggregator;

    Swap swapHelper;
    CheatCodes cheatCodes;
    uint256 forkId;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);

        address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        swapHelper = new Swap(uniV2Addr, WETH);
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        conveyorSwapAggregator = IConveyorSwapAggregator(
            address(
                new ConveyorSwapAggregator(
                    0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
                )
            )
        );
        forkId = cheatCodes.activeFork();
        cheatCodes.makePersistent(address(conveyorSwapAggregator));
        cheatCodes.makePersistent(address(this));

        cheatCodes.makePersistent(
            address(0xba5BDe662c17e2aDFF1075610382B9B691296350)
        );
        // cheatCodes.makePersistent(
        //     address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)
        // );
        cheatCodes.makePersistent(
            address(conveyorSwapAggregator.CONVEYOR_SWAP_EXECUTOR())
        );
        cheatCodes.makePersistent(address(swapHelper));
    }

    function testSwapUniv2SingleLP() public {
        cheatCodes.rollFork(forkId, 16000200);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(
            address(conveyorSwapAggregator),
            type(uint256).max
        );

        ConveyorSwapAggregator.Call[]
            memory calls = new ConveyorSwapAggregator.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(this));

        ConveyorSwapAggregator.SwapAggregatorMulticall
            memory multicall = ConveyorSwapAggregator.SwapAggregatorMulticall(
                lp,
                calls
            );

        conveyorSwapAggregator.swap(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall
        );
    }

    function testSwapExactEthForTokens() public {
        cheatCodes.rollFork(forkId, 16000200);

        cheatCodes.deal(address(this), type(uint128).max);
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountOutMin = 1;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        ConveyorSwapAggregator.Call[]
            memory calls = new ConveyorSwapAggregator.Call[](1);

        calls[0] = newUniV2Call(lp, 1, 0, address(this));

        ConveyorSwapAggregator.SwapAggregatorMulticall
            memory multicall = ConveyorSwapAggregator.SwapAggregatorMulticall(
                lp,
                calls
            );

        conveyorSwapAggregator.swapExactEthForToken{value: amountIn}(tokenOut, amountOutMin, multicall);
        
    }

    function testSwapExactTokenForETH() public {
        cheatCodes.rollFork(forkId, 16000200);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(
            address(conveyorSwapAggregator),
            type(uint256).max
        );

        ConveyorSwapAggregator.Call[]
            memory calls = new ConveyorSwapAggregator.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorSwapAggregator));

        ConveyorSwapAggregator.SwapAggregatorMulticall
            memory multicall = ConveyorSwapAggregator.SwapAggregatorMulticall(
                lp,
                calls
            );

        conveyorSwapAggregator.swapExactTokenForEth(tokenIn, amountIn, amountOutMin, multicall);
           
    }

    function testSwapUniv2MultiLP() public {
        cheatCodes.rollFork(forkId, 16000233);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint256 amountIn = 825000000;
        address tokenOut = 0x2e85ae1C47602f7927bCabc2Ff99C40aA222aE15;
        uint256 amountOutMin = 4948702184313056519683340;
        address firstLP = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
        address secondLP = 0xdC1D67Bc953Bf67F007243c7DED42d67410a6De5;

        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(
            address(conveyorSwapAggregator),
            type(uint256).max
        );

        ConveyorSwapAggregator.Call[]
            memory calls = new ConveyorSwapAggregator.Call[](2);

        calls[0] = newUniV2Call(firstLP, 0, 680641423375285542, secondLP);
        calls[1] = newUniV2Call(
            secondLP,
            4948702184313056519683340,
            0,
            address(this)
        );

        ConveyorSwapAggregator.SwapAggregatorMulticall
            memory multicall = ConveyorSwapAggregator.SwapAggregatorMulticall(
                firstLP,
                calls
            );

        conveyorSwapAggregator.swap(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall
        );
    }

    function testSwapUniv3SingleLP() public {
        cheatCodes.deal(address(this), type(uint256).max);
        address tokenIn = 0xba5BDe662c17e2aDFF1075610382B9B691296350;
        uint256 amountIn = 5678000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 453245423220749265;
        address lp = 0x7685cD3ddD862b8745B1082A6aCB19E14EAA74F3;

        //Deposit weth to address(this)
        (bool depositSuccess, ) = address(tokenOut).call{
            value: 500000000 ether
        }(abi.encodeWithSignature("deposit()"));
        require(depositSuccess, "deposit failed");
        IUniswapV3Pool(lp).swap(
            address(this),
            false,
            500 ether,
            TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(false, tokenOut, address(this))
        );

        IERC20(tokenIn).approve(
            address(conveyorSwapAggregator),
            type(uint256).max
        );

        ConveyorSwapAggregator.Call[]
            memory calls = new ConveyorSwapAggregator.Call[](1);

        calls[0] = newUniV3Call(
            lp,
            conveyorSwapAggregator.CONVEYOR_SWAP_EXECUTOR(),
            address(this),
            true,
            amountIn,
            tokenIn
        );
        console.log(IERC20(tokenIn).balanceOf(address(this)));

        forkId = cheatCodes.activeFork();
        cheatCodes.rollFork(forkId, 16000218);
        console.log(IERC20(tokenIn).balanceOf(address(this)));
        ConveyorSwapAggregator.SwapAggregatorMulticall
            memory multicall = ConveyorSwapAggregator.SwapAggregatorMulticall(
                conveyorSwapAggregator.CONVEYOR_SWAP_EXECUTOR(),
                calls
            );

        conveyorSwapAggregator.swap(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall
        );
    }

    // function testBenchParaswapUsdcEth() public {
    //     cheatCodes.deal(address(this), type(uint256).max);
    //     address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     uint256 amountIn = 572272000;
    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     uint256 amountOutMin = 1;
    //     address lp = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    //     //Deposit weth to address(this)
    //     (bool depositSuccess, ) = address(tokenOut).call{
    //         value: 500000000 ether
    //     }(abi.encodeWithSignature("deposit()"));
    //     require(depositSuccess, "deposit failed");
    //     IUniswapV3Pool(lp).swap(
    //         address(this),
    //         false,
    //         5 ether,
    //         TickMath.MAX_SQRT_RATIO - 1,
    //         abi.encode(false, tokenOut, address(this))
    //     );

    //     ConveyorSwapAggregator.Call[]
    //         memory calls = new ConveyorSwapAggregator.Call[](1);

    //     calls[0] = newUniV3Call(
    //         lp,
    //         conveyorSwapAggregator.CONVEYOR_SWAP_EXECUTOR(),
    //         address(this),
    //         true,
    //         amountIn,
    //         tokenIn
    //     );

    //     forkId = cheatCodes.activeFork();
    //     cheatCodes.rollFork(forkId, 16349359);
    //     console.log(IERC20(tokenIn).balanceOf(address(this)));
    //     IERC20(tokenIn).approve(
    //         address(conveyorSwapAggregator),
    //         type(uint256).max
    //     );
    //     console.log(IERC20(tokenIn).balanceOf(address(this)));
    //     ConveyorSwapAggregator.SwapAggregatorMulticall
    //         memory multicall = ConveyorSwapAggregator.SwapAggregatorMulticall(
    //             conveyorSwapAggregator.CONVEYOR_SWAP_EXECUTOR(),
    //             calls
    //         );

    //     conveyorSwapAggregator.swapExactTokenForEth(tokenIn, amountIn, amountOutMin, multicall);
           
    // }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory data
    ) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address tokenIn, address _sender) = abi.decode(
            data,
            (bool, address, address)
        );

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne
            ? uint256(amount0Delta)
            : uint256(amount1Delta);

        if (!(_sender == address(this))) {
            ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
            IERC20(tokenIn).transferFrom(_sender, msg.sender, amountIn);
        } else {
            IERC20(tokenIn).transfer(msg.sender, amountIn);
        }
    }

    ///@notice Helper function to create a single mock call for a v3 swap.
    function newUniV3Call(
        address _lp,
        address _sender,
        address _receiver,
        bool _zeroForOne,
        uint256 _amountIn,
        address _tokenIn
    ) public pure returns (ConveyorSwapAggregator.Call memory) {
        ///@notice Pack the required data for the call.
        bytes memory data = abi.encode(_zeroForOne, _tokenIn, _sender);
        ///@notice Encode the callData for the call.
        bytes memory callData = abi.encodeWithSignature(
            "swap(address,bool,int256,uint160,bytes)",
            _receiver,
            _zeroForOne,
            int256(_amountIn),
            _zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1,
            data
        );
        ///@notice Return the call
        return ConveyorSwapAggregator.Call({target: _lp, callData: callData});
    }

    ///@notice Helper function to create a single mock call for a v2 swap.
    function newUniV2Call(
        address _lp,
        uint256 amount0Out,
        uint256 amount1Out,
        address _receiver
    ) public pure returns (ConveyorSwapAggregator.Call memory) {
        bytes memory callData = abi.encodeWithSignature(
            "swap(uint256,uint256,address,bytes)",
            amount0Out,
            amount1Out,
            _receiver,
            new bytes(0)
        );
        return ConveyorSwapAggregator.Call({target: _lp, callData: callData});
    }
}
