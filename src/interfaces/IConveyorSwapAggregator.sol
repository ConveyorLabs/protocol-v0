// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import "../ConveyorSwapAggregator.sol";

interface IConveyorSwapAggregator {
    function swap(
        address tokenIn,
        uint256 amountIn,
        address tokenOut,
        uint256 amountOutMin,
        ConveyorSwapAggregator.SwapAggregatorMulticall
            calldata swapAggregatorMulticall
    ) external;

    function swapExactEthForToken(
        address tokenOut,
        uint256 amountOutMin,
        ConveyorSwapAggregator.SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) external payable;

    function swapExactTokenForEth(
        address tokenIn,
        uint256 amountIn,
        uint256 amountOutMin,
        ConveyorSwapAggregator.SwapAggregatorMulticall calldata swapAggregatorMulticall
    ) external;

    function CONVEYOR_SWAP_EXECUTOR() external view returns (address);
}
