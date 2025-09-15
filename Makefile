-include .env

.PHONY: 
	all build test

install: 
	forge install

test:
	forge test