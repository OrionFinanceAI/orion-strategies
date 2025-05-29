// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;


import {Script} from "../lib/forge-std/src/Script.sol";
import {MetaMorpho} from "../lib/metamorpho/src/MetaMorpho.sol";
import {Doppelganger, Id, IMorpho, MarketParams} from "../src/Doppelganger.sol";



contract SetupCopyCat is Script {

    Doppelganger public doppelganger = Doppelganger(0x739384145fD7230cB6c25d5eDC49d701f4fd50E6);

    MetaMorpho public targetVault = MetaMorpho(0x616a4E1db48e22028f6bbf20444Cd3b8e3273738);
    MetaMorpho public vault = MetaMorpho(0xe4e956f8f1C4D72114731184Fdc8a26238eB9351);

    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

    function run() public {
        vm.startBroadcast();

        uint256 len = targetVault.withdrawQueueLength();
        for (uint256 i = 0; i < len; i++) {
            Id id = targetVault.withdrawQueue(i);

            MarketParams memory marketParams = morpho.idToMarketParams(id);

            doppelganger.addMarket(marketParams);
            vault.acceptCap(marketParams);
        }

        vm.stopBroadcast();
    }
}
