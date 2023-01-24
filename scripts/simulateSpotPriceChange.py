import math
from eth_abi import encode_single
import sys
def main(args):
    alphaX=int(args[1])
    reserveIn = int(args[2])
    reserveOut = int(args[3])

    reserveA= reserveIn+alphaX

    reserveB = (int) ((reserveIn*reserveOut)/(reserveA))

    simulatedSpotPrice = (reserveB/reserveA)*2**128

    enc = encode_single('uint256', int(simulatedSpotPrice))
    print("0x" + enc.hex())


if __name__ == '__main__':
    args = sys.argv
    main(args)