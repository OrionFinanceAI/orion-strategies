// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {IMetaMorpho, IMorpho} from "../../lib/metamorpho/src/interfaces/IMetaMorpho.sol";
import {MetaMorphoFactory} from "../../lib/metamorpho/src/MetaMorphoFactory.sol";
import {MetaMorpho} from "../../lib/metamorpho/src/MetaMorpho.sol";
import {Doppelganger, MarketParams, IMorpho, Id, Position, Market} from "../../src/Doppelganger.sol";
import {IERC20} from "../../lib/forge-std/src/interfaces/IERC20.sol";

/**
 * @title FORK_BASE_DoppelGanger
 * @dev This test only run with trigger by forge test `fork-url` set,
 * e.g.
 *
 *  forge test --match-contract FORK_BASE_DoppelGanger --fork-url <your RPC url> -vvv
 */
contract FORK_BASE_DoppelGanger is Test {
    /* ============================= Addresses ============================= */

    // Morpho Addresses
    MetaMorphoFactory factory = MetaMorphoFactory(0xFf62A7c278C62eD665133147129245053Bbf5918);
    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    // Assets
    address usdc = address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    // The vault to copy
    // IMetaMorpho targetVault = IMetaMorpho(0x616a4E1db48e22028f6bbf20444Cd3b8e3273738); // Seamless USDC
    IMetaMorpho targetVault = IMetaMorpho(0xc1256Ae5FF1cf2719D4937adb3bbCCab2E00A2Ca); // Moonwell

    // Markets to track
    Id cbBTC_USDC = Id.wrap(bytes32(0x9103c3b4e834476c9a62ea009ba2c884ee42e94e6e314a26f04d312434191836));
    Id weth_USDC = Id.wrap(bytes32(0x8793cf302b8ffd655ab97bd1c695dbd967807e8367a65cb2f4edaf1380ba1bda));

    /* ============================= Testing States ============================= */

    IMetaMorpho vault;
    Doppelganger doppelganger;

    address alice = address(0xaa);
    address bob = address(0xbb);

    /* =============================  Setup Function and Helpers ============================= */

    /// @dev setup env for the test
    function setUp() public onlyOnBase {
        // create the vault
        vault = IMetaMorpho(
            address(
                factory.createMetaMorpho(address(this), 0, usdc, "Doppelganger Seamless", "free-smUSDC", bytes32(0))
            )
        );

        doppelganger = new Doppelganger(morpho, vault, targetVault);

        // set access control
        vault.setCurator(address(doppelganger));
        vault.setIsAllocator(address(doppelganger), true);

        // add a market
        MarketParams memory cbtc_params = morpho.idToMarketParams(cbBTC_USDC);
        doppelganger.addMarket(cbtc_params);
        vault.acceptCap(cbtc_params);

        // add a market
        MarketParams memory weth_params = morpho.idToMarketParams(weth_USDC);
        doppelganger.addMarket(weth_params);
        vault.acceptCap(weth_params);

        Id[] memory queue = new Id[](2);
        queue[0] = cbBTC_USDC;
        queue[1] = weth_USDC;
        vault.setSupplyQueue(queue);

        // Distribute USDC
        deal(usdc, alice, 10_000e6);
        deal(usdc, bob, 10_000e6);

        // set allowances
        vm.prank(alice);
        IERC20(usdc).approve(address(vault), type(uint256).max);
        vm.prank(bob);
        IERC20(usdc).approve(address(vault), type(uint256).max);
    }

    /// @dev this makes the test only run during fork test with fork-url set to a base RPC!
    modifier onlyOnBase() {
        if (block.chainid != 8453) return;
        _;
    }

    /// @dev get the amount of supplied assets in a market for an account, base on current share price
    function getMorphoSuppliedAssets(Id marketId, address account) public view returns (uint256) {
        Position memory pos = morpho.position(marketId, account);
        Market memory market = morpho.market(marketId);
        return pos.supplyShares * market.totalSupplyAssets / market.totalSupplyShares;
    }

    /* =============================  Test Functions ============================= */

    function test_deposit_and_reallocate() public onlyOnBase {
        vm.startPrank(alice);
        vault.deposit(1000e6, alice);
        vm.stopPrank();

        doppelganger.reallocate();

        // log distributions
        console.log("cbBTC_USDC", getMorphoSuppliedAssets(cbBTC_USDC, address(vault)));
        console.log("weth_USDC", getMorphoSuppliedAssets(weth_USDC, address(vault)));
    }
}
