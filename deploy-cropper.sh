#!/bin/bash

####################################################
# Deploy the cropper
#
# Requires MCD environment variables to be in scope https://changelog.makerdao.com/releases/mainnet/active/contracts.json
#
# Usage: ./deploy-cropper.sh
####################################################

echo "Deploying contracts..."

CROPPER=$(dapp create Cropper)
CROPPER_IMP=$(dapp create CropperImp $MCD_VAT)

echo "Set implementation..."

seth send $CROPPER 'setImplementation(address)' $CROPPER_IMP

echo "Set permissions..."

seth send $CROPPER 'rely(address)' $MCD_PAUSE_PROXY
seth send $CROPPER 'deny(address)' $ETH_FROM

echo "Cropper: $CROPPER"
echo "CropperImp: $CROPPER_IMP"
