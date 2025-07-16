// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import { Id } from "../../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

interface IDoppelganger {
    /// @notice Reverted when a market is not enabled on the target vault.
    error MarketNotEnabled();

    /// @notice Reverted when attempting to add a market that has already been added.
    error MarketAlreadyAdded();

    /// @notice Emitted when `vault.submitCap` reverts because the market configuration was already set.
    event MarketAlreadySet();

    struct PendingAllocation {
        Id marketId; // The ID of the market.
        bool isWithdraw; // True if the operation is a withdrawal, false for a supply.
        uint256 amount; // The target amount for the allocation.
    }
}
