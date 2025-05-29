# Hypermorpho

Hypermorpho is a strategy layer for Metamorpho vaults. It allows you to define new Metamorpho vaults whose behavior is derived from the observed behavior of existing vaults.

By exploiting the full transparency of Metamorpho's onchain curation, Hypermorpho enables you to construct vaults that **mimic**, **respond to**, or **generalize from** the historical and current state of other vaults — including their allocations, performance, TVL, and strategy shifts.

## Core Concept

Metamorpho vaults expose their entire strategy publicly: allocation decisions, market selection, TVL, share prices, and curator activity. Hypermorpho makes it possible to:

- **Mimic** existing vaults 1:1, including reallocations and market selections.
- **Generalize** curator behavior into reusable strategy templates.
- **Build fee-competitive alternatives** that replicate or extend high-performing strategies.
- **Compose curators** by building vaults that act as aggregates or filters of others.

All this is made possible by the lack of privacy at the Metamorpho level — curator decisions are public, reactive, and exploitable.

## How it Works

At the heart of Hypermorpho is a `Doppelganger` helper contract that acts as both curator and allocator for a new vault, enabling it to track the behavior of a source vault. To set up a mimicking vault:

1.  **Initialize `Doppelganger`**: Deploy and initialize the `Doppelganger` contract, providing the address of the target Metamorpho vault you wish to copy.
2.  **Configure Target Vault**: In a new Metamorpho vault (the one you are copying), you must set the deployed `Doppelganger` contract as both its:
    *   Allocator
    *   Curator

Once this two-way linkage is established, the `Doppelganger` contract enables the following actions on the vault:

1.  **Synchronized Market Addition**: Anyone can propose adding a new market to your mimicking vault via the `Doppelganger` contract. The `Doppelganger` will verify if this market exists in the target vault. If it does, the market is added to your mimicking vault.
2.  **Mirrored Reallocations**: Anyone can trigger a reallocation in your mimicking vault through the `Doppelganger` contract. This will distribute the total assets in your vault, mirroring the exact allocation strategy and distribution of the target vault.

**This is just one example strategy. The system is designed to generalize to more advanced patterns that take into account vault history, pricing, performance, and composition.**

## Why Hypermorpho?

"Meta" implies abstraction. Hyper implies power over the meta — the ability to manipulate, generalize, and surpass it. Hypermorpho leverages full observability of the Metamorpho system to unlock new design space for strategy-driven vault creation.