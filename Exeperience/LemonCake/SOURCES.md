# Sources and evidence quality

## Primary source: the locally installed game

- Steam app `1338330`, build `6596857`, depot `1338331`, manifest `3131561033263652299`.
- Directory: `C:/Program Files (x86)/Steam/steamapps/common/Lemon Cake`.
- Archive: `LemonCake/Content/Paks/LemonCake-WindowsNoEditor.pak`, **480,756,603 bytes**, `V8B`, unencrypted index, compression `None` according to repak.
- Engine: `LemonCake.uproject` → `EngineAssociation=4.24`; shipping EXE strings → `++UE4+Release-4.24-CL-11590370`.
- [build.json](data/build.json) contains the SHA256 of the archive and every installed file. Steam owner/account IDs were not copied into the database.
- [files.csv](data/files.csv) contains all 11,123 extracted archive entries. Their combined size is **472,915,295 bytes**; it differs from the container size because of archive metadata.

Source game asset paths in the documentation are relative to `LemonCake/Content`. For example, `Blueprints/Items/DAT_Recipe.uasset` is located under `.local/unpacked/LemonCake/Content/Blueprints/Items/`. Original `.uexp` and `.ubulk` files remain alongside their assets.

## Additional primary sources

Checked on 2026-09-22:

- [Steam: Lemon Cake](https://store.steampowered.com/app/1338330/Lemon_Cake/?l=english): title, developer/publisher Cozy Bee Games, February 18, 2021 release, single-player, Steam Cloud, 17 achievements, and the general bakery loop. The store describes the product; it is not a source for exact formulas in the installed build.
- [repak](https://github.com/trumank/repak), [release v0.2.3](https://github.com/trumank/repak/releases/tag/v0.2.3): the portable Windows CLI was used; its ZIP SHA256 was checked against the published checksum and pinned in the restore script.
- [UAssetAPI](https://github.com/atenfyr/UAssetAPI), [Basic Usage](https://atenfyr.github.io/UAssetAPI/guide/basic.html): NuGet `1.1.0` was used; the serializer reports commit `7353081`, with engine explicitly set to `VER_UE4_24`. Dependencies are pinned in [packages.lock.json](tools/AssetDump/packages.lock.json).
- [Epic: FName, UE 4.27](https://dev.epicgames.com/documentation/en-us/unreal-engine/fname?application_version=4.27): FName comparison is case-insensitive. This explains why `chocolatePancake` in DAT_Recipe and `ChocolatePancake` in DAT_Item should be matched without regard to case while retaining the original extracted spelling.

The Steam page and third-party descriptions were not used to fill missing numeric table values. Exact game values were extracted locally.

## Evidence levels

1. **Data**: a table field, class default, map override, or configuration entry. Runtime logic may change it.
2. **Static logic**: recovered Blueprint operations, branches, calls, and constants. An `@...` address is an offset within a Kismet function, not a machine-code address in the EXE.
3. **Inference**: interpretation of relationships between operations. Conditions and limits are stated; runtime behavior is unverified.
4. **Runtime**: absent from this investigation. Neither store screenshots nor a startup log count as exercising a mechanic.

`SerializeJson` does not recover the author's source code. Cooked packages lack the complete editor graph context; native libraries, visual mesh correctness, audio, and all behavior variants have not been exhaustively verified.
