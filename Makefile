-include .env

.PHONY: 
	all build test

build:
	forge build

install: 
	forge install

test:
	forge test