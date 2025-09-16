# Cross-Chain Rebase Token

1. A protocol that allows users to deposit into a vault contract and, in return, receive rebase tokens that represent their underlying balance

2. Rebase token - balanceOf() function is dynamic to show the changing balance with time.
   - Balance increases linearly (aka in direct correlation) with time
   - We're going to mint tokens to our users every time they perform an action (i.e. minting, burning, transferring or... bridging)


3. Interest rate
   - we're going to individually set an interest rate for each user based on some global interest rate of the protocol at the time the user deposits into the vault
   - this global interest rate can only decrease to incentivize/reward early adopters
   - this is going to increase token adoption!