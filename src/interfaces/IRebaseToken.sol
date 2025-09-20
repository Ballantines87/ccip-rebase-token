// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRebaseToken {
    function mint(address _to, uint256 _amount) external;

    function burn(address _from, uint256 _amount) external;

    function setInterestRate(uint256 _newInterestRate) external;

    function grantMintAndBurnRole(address _account) external;

    function getUserInterestRate(
        address _user
    ) external view returns (uint256 userInterestRate);

    function getUserLastUpdatedTimestamp(
        address _user
    ) external view returns (uint256 userLastUpdatedTimestamp);

    function getSmartContractInterestRate()
        external
        view
        returns (uint256 smartContractInterestRate);

    function getUserPrincipalBalanceOf(
        address _user
    ) external view returns (uint256 balance);
}
