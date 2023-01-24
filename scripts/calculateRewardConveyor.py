import math
from eth_abi import encode_single
import sys
def main(args):
    percentFee = int(args[1])
    wethValue = int(args[2])

    percentFeeBase10= percentFee*2**-64
    if (percentFee <= 92233720368547760):
        
        conveyorPercent = (percentFeeBase10 + (0.005-percentFeeBase10)/2+0.001)*10**2

    else:
        conveyorPercent= 0.6
    
    wethTotal = wethValue*percentFeeBase10
    conveyorReward = conveyorPercent*wethTotal
    beaconReward = wethTotal-conveyorReward

    enc = encode_single('uint256', int(conveyorReward))
    print("0x" + enc.hex())

if __name__ == '__main__':
    args = sys.argv
    main(args)