-include .env

.PHONY: 
	all build test

build:
	forge build

build-via-ir:
	forge build --via-ir

install: 
	forge install

test:
	forge test