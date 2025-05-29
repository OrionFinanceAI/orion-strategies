// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

// import from MetaMorpho repo so the type is compatible
import {Position, Market} from "../lib/metamorpho/lib/morpho-blue/src/interfaces/IMorpho.sol";
import {MarketParamsLib} from "../lib/metamorpho/lib/morpho-blue/src/libraries/MarketParamsLib.sol";
import {
    IMetaMorpho,
    MarketConfig,
    Id,
    MarketParams,
    IMorpho,
    MarketAllocation
} from "../lib/metamorpho/src/interfaces/IMetaMorpho.sol";

import {IDoppelganger} from "./interfaces/IDoppelganger.sol";

/**
 * @title Doppelganger
 * @dev A contract that replicates the allocation of a target MetaMorpho vault.
 *      This contract allows anyone to add markets to the managed vault and reallocate assets
 *      based on the target vault's allocations.
 */
contract Doppelganger is IDoppelganger {
    using MarketParamsLib for MarketParams;

    /// @dev The Morpho contract instance.
    IMorpho public immutable morpho;

    /// @dev The target MetaMorpho vault to replicate.
    IMetaMorpho public immutable targetVault;

    /// @dev The MetaMorpho vault managed by this contract.
    IMetaMorpho public immutable vault;

    /// @dev An array of market IDs added to `vault`.
    Id[] public markets;

    /// @dev Maps market IDs to their parameters. A zero address for `loanToken` indicates the market has not been added.
    mapping(Id => MarketParams) public marketParams;

    constructor(IMorpho _morpho, IMetaMorpho _vault, IMetaMorpho _targetVault) {
        morpho = _morpho;
        targetVault = _targetVault;
        vault = _vault;
    }

    /// @notice Adds a market to the managed vault.
    /// @dev This function can be called by anyone if the market is configured in the `targetVault`.
    ///      Requires this contract to be the curator of `vault`.
    ///      The supply cap for the market can be accepted on `vault` by anyone after the timelock period.
    function addMarket(MarketParams calldata _marketParams) external {
        Id marketId = _marketParams.id();

        // Verify this market is not already added.
        if (marketParams[marketId].loanToken != address(0)) revert MarketAlreadyAdded();

        // Verify this market is configured on the target vault.
        MarketConfig memory marketConfig = targetVault.config(marketId);
        if (!marketConfig.enabled) revert MarketNotEnabled();

        // Update storage.
        markets.push(marketId);
        marketParams[marketId] = _marketParams;

        // External call: add the market to `vault`. MetaMorpho performs a safe cast to uint184 for the cap.
        try vault.submitCap(_marketParams, type(uint184).max) {} catch {}
    }

    /// @notice Reallocates assets in the managed vault based on the `targetVault`'s allocations.
    /// @dev This function can be called by anyone.
    ///      Execution might revert if a withdrawal from a market fails due to insufficient liquidity.
    function reallocate() external {
        uint256 vaultSize = vault.lastTotalAssets();

        // Calculate the total size of the target vault based on tracked markets.
        // This prevents disproportional allocations if new markets are available on `targetVault` but not yet added to `vault`.
        uint256 targetVaultSize;

        uint8 length = uint8(markets.length);
        uint256[] memory targetVaultAllocations = new uint256[](length);

        // For each tracked market, determine the target vault's allocation.
        for (uint256 i = 0; i < length; i++) {
            Id marketId = markets[i];

            uint256 amount = _getSuppliedAsset(marketId, address(targetVault));
            targetVaultAllocations[i] = amount;

            targetVaultSize += amount;
        }

        // Calculate the desired allocation for each market in `vault`.
        PendingAllocation[] memory pendingAllocations = new PendingAllocation[](length);
        for (uint256 i = 0; i < length; i++) {
            Id marketId = markets[i];
            uint256 targetVaultAllocation = targetVaultAllocations[i];

            uint256 newAllocation = targetVaultAllocation * vaultSize / targetVaultSize;

            uint256 currentAllocation = _getSuppliedAsset(marketId, address(vault));
            bool isWithdraw = newAllocation < currentAllocation;

            pendingAllocations[i] =
                PendingAllocation({marketId: marketId, isWithdraw: isWithdraw, amount: newAllocation});
        }
        // Prepare parameters for the `reallocate` call on `vault`.
        MarketAllocation[] memory allocations = new MarketAllocation[](length);

        // Index for the next withdrawal operation in the `allocations` array.
        uint256 j = 0;
        // Index for the next supply operation in the `allocations` array.
        uint256 k = length - 1;

        // Populate the `allocations` array: withdrawals first, then supplies.
        // This order is a convention for `vault.reallocate`.
        for (uint256 i = 0; i < length; i++) {
            bool isWithdraw = pendingAllocations[i].isWithdraw;
            uint256 idx = isWithdraw ? j++ : k--;

            allocations[idx] = MarketAllocation({
                marketParams: marketParams[pendingAllocations[i].marketId],
                assets: pendingAllocations[i].amount
            });
        }

        // The last allocation in the array must be a supply operation.
        // Set its amount to `type(uint256).max` to supply all remaining assets and avoid dust.
        allocations[length - 1].assets = type(uint256).max;

        // Execute the reallocation.
        vault.reallocate(allocations);
    }

    /// @dev Retrieves the amount of supplied assets in a specific market for a given account, based on the current share price.
    /// @param marketId The ID of the market.
    /// @param account The account address.
    /// @return The amount of supplied assets in the market for the account.
    function _getSuppliedAsset(Id marketId, address account) internal view returns (uint256) {
        // TODO: This function currently calls `morpho.market(marketId)` twice for each allocation calculation during `reallocate`.
        Market memory market = morpho.market(marketId);

        Position memory position = morpho.position(marketId, account);

        return position.supplyShares * market.totalSupplyAssets / market.totalSupplyShares;
    }
}
