#!/bin/bash

# Check if the network flag is present
if [[ $@ == *"--network "* ]]; then
    network=$(echo $@ | grep -oP '(?<=--network=)[^ ]+' | head -n1)
    npx hardhat test --network=$network ./test/TLDComplete.test.ts
else
    npx hardhat test ./test/TLDComplete.test.ts
fi