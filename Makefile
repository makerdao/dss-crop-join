export DAPP_TEST_NUMBER = 10950483

all      :; dapp build
clean    :; dapp clean
test     :; dapp test --rpc
test-now :; DAPP_TEST_NUMBER=$$(seth block latest number) dapp test --rpc
deploy   :; dapp create Usdc
