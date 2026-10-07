// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Rise (RISE)
/// @notice Fixed-supply community token with standard, fee-free ERC-20 transfers.
/// @dev The deploying factory receives the entire supply and performs the launch allocation.
///      There are no external mint, burn, administration, or upgrade entry points.
contract Rise is ERC20 {
    constructor() ERC20("Rise", "RISE") {
        _mint(msg.sender, 1_000_000_000 * 10 ** 18);
    }
}
