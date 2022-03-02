#!/bin/bash

####################################################
# Example deployment script for a Synthetix-style rewards contract
#
# Requires MCD environment variables to be in scope https://changelog.makerdao.com/releases/mainnet/active/contracts.json
#
# Usage: ./deploy-synthetix.sh <ILK> <GEM> <BONUS> <POOL>
# Lido Example: ./deploy-synthetix.sh CRVV1STETHETH-A 0x06325440D014e39736583c165C2963BA99fAf14E 0x5A98FcBEA516Cf06857215779Fd812CA3beF1B32 0x99ac10631F69C753DDb595D074422a0922D9056B
####################################################

ILK=$(seth --to-bytes32 "$(seth --from-ascii "$1")")
GEM=$2
BONUS=$3
POOL=$4

echo "Deploying contracts..."

CROPJOIN=$(dapp create CropJoin)
CROPJOIN_IMP=$(dapp create SynthetixJoinImp $MCD_VAT $ILK $GEM $BONUS $POOL)

echo "Set implementation..."

seth send $CROPJOIN 'setImplementation(address)' $CROPJOIN_IMP

echo "Set permissions..."

seth send $CROPJOIN 'rely(address)' $MCD_PAUSE_PROXY
seth send $CROPJOIN 'deny(address)' $ETH_FROM

echo "CropJoin: $CROPJOIN"
echo "CropJoinImp: $CROPJOIN_IMP"
