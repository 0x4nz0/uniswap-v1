// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Exchange.sol";

contract Factory {
    mapping(address => address) public tokenToExchange;
}
