all      :; dapp --use solc:0.6.12 build
clean    :; dapp clean
test     :; dapp --use solc:0.6.12 test --rpc -v --fuzz-runs 10
test-dev     :; dapp --use solc:0.6.12 test --rpc -v --fuzz-runs 10 --match test_kick_via_bark
