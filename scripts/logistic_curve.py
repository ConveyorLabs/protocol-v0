
import math
import sys
from eth_abi import encode_single
import argparse


def main(args):
    if (int(args) >= 1000000):
        enc = encode_single('uint256', int(4611686018427388))
        print("0x" + enc.hex())
        return
    if ((int(args)/75000)*2**64 >= (0x400000000000000000)):
        enc = encode_single('uint256', int(4611686018427388))
        print("0x" + enc.hex())
        return

    fee = (0.225/(math.e**(int(args)/100000)))+0.025
    adjusted64x64 = (fee)/(10**2)
    enc = encode_single('uint256', int(adjusted64x64*2**64))
    print("0x" + enc.hex())


if __name__ == '__main__':
    args = sys.argv
    main(args[1])
