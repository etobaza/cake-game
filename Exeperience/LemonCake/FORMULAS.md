# Formulas and thresholds

All values refer to build `6596857`. Sources are extracted tables, defaults, and Kismet. `@N` denotes an offset within the named function. Open operations with `query.py code ...`; readable files are under `.local/readable`. The formulas below are static interpretations; runtime behavior has not been tested.

## Day timing and customer spawning

`BP_DailyCycle`, `ExecuteUbergraph_BP_DailyCycle`:

- Default: `StageLength=180`, `ClientSpawnDelay=15`, `Hour=1`.
- In the branch after the `Player.IsPlayerStart` check, stage length is replaced with **`StageLength = 100 + 2.5 × Level`**, `@4973–5079`. Therefore, 180 cannot be assumed to be the active stage duration in every case.
- `AddTime` interval: **`StageLength / 240`**, `@2387–2429`.
- Morning: **`ClientDelayTimer = 15 × (0.95 − 0.01 × Level) × 2.5`**, `@3814–4008`.
- Lunch: **`ClientDelayTimer = 15 × (0.95 − 0.01 × Level)`**, `@4259–4411`.
- The preparation reset sets `Hour=8`, `Minute=0`, `@4166–4189`; the closing branch sets `Hour=16`, `@2670`.
- The closing customer check uses a 3-second timer, `@2744`. Early-end and tutorial flows have separate transitions.

`BP_ClientSpawner`, `ExecuteUbergraph_BP_ClientSpawner`, `@372–568`:

```text
period = ClientDelayTimer × clamp(ClientMultiplier, 0.5, 2.0)
timerInitialStartDelay = −0.8 × period
```

`ClientDelayTimer=10` and `ClientMultiplier=1` are spawner defaults. The daily cycle subsequently changes the first parameter. A larger `ClientMultiplier` produces a longer interval. The negative initial delay is recorded literally; the exact timing of the first timer callback requires UE/runtime verification and has not been replaced with a guess.

## Customer waiting and coffee

`BP_Client`, `ExecuteUbergraph_BP_Client`:

- `PatienceProgress` is called every **1 second**, `@3600`.
- For a non-tutorial customer: **`Patience += 0.01`**, `@13713–13794`.
- At `Patience >= 1`, the customer leaves and increments `MissedOrders`, `@13884–14101`.
- Impatience threshold: **0.75**, `@14585`.
- Serving coffee resets `Patience=0`, `@24725`.

Nominally, 0→1 takes about 100 ticks without pauses, coffee, or special branches. This is an arithmetic inference, not a stopwatch measurement. The code pauses and clears timers, so 100 seconds must not be applied to every customer state.

## Sales, tips, and XP

`BP_Client`, `ExecuteUbergraph_BP_Client`:

- Base payment in the seated-service path: **`Food.Value + float(Level) / 25`**, `@23226–23336`.
- A similar addition to the display item's value appears at `@9050–9182`.
- A tip path was found for `Patience <= 0.75`, `@18695–19132`:

```text
tipBase = Food.Value × 0.2 × (1 − Patience)
tipMultiplier = 1 + integer_division(BonusPercentage, 100)
tip = tipBase × tipMultiplier
```

The operation is specifically **`Divide_IntInt`**, followed by conversion to float. For `BonusPercentage` 0–99, this branch gives a multiplier of 1; at 100, it gives 2. This is a bytecode observation; a smooth percentage bonus has not been established. Do not silently correct it when describing the original.

- The `FoodReaction` path passes **`Food.Value × 3`** to `GainExperience`, `@19177–19241`.
- Cat adoption contains a `Player.AddMoney(7.5)` call, `@3044`. All reachability conditions and interactions with other payments still require a gameplay test.

`BP_Player`, `ExecuteUbergraph_BP_Player`, `@15657–16407`:

```text
if Level < 40:
    Experience += Gain / CRV_Experience(Level)
    shownGain = trunc(Gain × 10)
    if Experience >= 1:
        LevelUp()
```

The XP field is normalized; the displayed number is not the increment to `Experience`. `CRV_Experience` contains cubic keys `(0, 50)`, `(2, 125)`, `(40, 1650)` with authored tangents. Complete keys: [curves.json](data/curves.json). Interpolation is not linear; do not reconstruct intermediate levels by drawing straight lines between the points.

## Oven

`BP_KitchenOven` defaults: `CompletedCookTime=15`, `BurnedCookTime=30`, `FirewoodTime=90`, `BurnDelayExtra=15`.

- `CompletedCookTime` is replaced by `DAT_Recipe.BakeTime`, `ExecuteUbergraph_BP_KitchenOven @2144`.
- Each cook tick increments `CurrentCookTime` by 1, `@4193–4235`.
- Readiness is checked with **`CurrentCookTime >= CompletedCookTime`**, `@5257`.
- Burning: **`CurrentCookTime >= CompletedCookTime + BurnedCookTime`**, `@4276–4322`.
- On burning, the cooked item is destroyed and `BurnedFood` is created; `PastriesBurned` is incremented.
- The oven upgrade at `WBP_ShopSingle.ExecuteUbergraph_WBP_ShopSingle @6180` assigns **`BurnedCookTime=60`**.

The recipe's table time and the grace period before burning are separate values. `BurnDelayExtra=15` exists, but its presence alone does not establish a final 15-second grace period.

## Menu bonuses

Amounts: [DAT_Bonus.json](data/tables/DAT_Bonus.json). Conditions: `WBP_DailyOverview.IsBonusActive`.

| ID | Value | Static-code condition | Offset |
| --- | ---: | --- | --- |
| CheapPastry | +10 | Average `DAT_Item.Value` ≤ 2 | @1446 |
| QuickBake | +10 | Average `DAT_Recipe.BakeTime` ≤ 10 | @2219 |
| DifferentType | +20 | At least 4 distinct categories | @2981 |
| VeganOption | +15 | A row has `IsVegan=true` | @3039–3526 |
| GlutenFreeOption | +15 | A row has `IsGlutenFree=true` | @3550–4037 |
| NewRecipe | +50 | The menu intersects `NewRecipes` | @4061–4566 |
| PricyPastry | −10 | Average `DAT_Item.Value` ≥ 3 | @5286 |
| SlowBake | −10 | Average `DAT_Recipe.BakeTime` ≥ 20 | @6059 |
| SameType | −12 | At most 2 distinct categories | @6821 |
| OldRecipe | −25 | A menu recipe has `BonusDayOldRecipe[index] >= 2` | @7274–7377 |
| NoBakeOption | −15 | No Bread/Cookie/Donut/Cake/Pie category | @7487–8346 |
| LowOption | −10 | At most 2 menu recipes | @8451 |
| HighOption | +10 | At least 5 menu recipes | @8590 |

The bonus accumulator starts at zero and performs `clamp(sum, 0, 100)` **after each addition**, `WBP_DailyOverview.ExecuteUbergraph_WBP_DailyOverview @21287, @22142–22235`. This is not always equivalent to clamping the final sum once: iteration order can affect the result.

Do not simplify `OldRecipe` to "a recipe older than two days": the condition uses a specific history array, separate from `RecipeActiveDays`. Trace its update order before reproducing the behavior exactly.

## Ingredients and basic parameters

Level overrides for `BP_ItemSpawner`: plants usually use `SpawnTimer=15`; flour/sugar/milk/egg use 3; honey uses 5; coffee uses 2; firewood uses 1. Full table and tags: [WORLD.md](WORLD.md). Care, capacity, unlocking, and the timer lifecycle affect actual production.

`BP_Player` defaults: `Money=5`, `Level=1`, `WalkSpeed=500`, `SprintRecharge=3`. `BP_CatCafe.CatsToSpawn=2`; `BP_ClientSpawner.GlobalCatAdoptionRate≈0.9`. These are parameters, not measured gameplay probabilities after all branches and upgrades.
