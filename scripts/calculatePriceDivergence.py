import math
from eth_abi import encode_single
import sys
def main(args):
    v3Spot = int(args[1])
    v2Outlier = int(args[2])

    if(v3Spot> v2Outlier):
        proportionalChange = v2Outlier/v3Spot
        priceDivergence = (1*2**128)- proportionalChange
    elif(v3Spot<v2Outlier):
        proportionalChange = v3Spot/v2Outlier
        priceDivergence = (1*2**128)- proportionalChange
    else:
        priceDivergence=0

    if(priceDivergence==340282366920938463463374607431768211456):
        priceDivergence=0
    
    enc = encode_single('uint256', int(priceDivergence))
    print("0x" + enc.hex())

if __name__ == '__main__':
    args = sys.argv
    main(args)