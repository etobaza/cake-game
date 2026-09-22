# Формулы и пороги

Все значения относятся к build `6596857`. Источники — выгруженные таблицы, defaults и Kismet. `@N` означает смещение внутри указанной функции. Операции можно открыть командой `query.py code ...`; читаемые файлы лежат в `.local/readable`. Формулы ниже — статическая интерпретация, runtime не тестировался.

## Время дня и появление клиентов

`BP_DailyCycle`, `ExecuteUbergraph_BP_DailyCycle`:

- Default: `StageLength=180`, `ClientSpawnDelay=15`, `Hour=1`.
- В ветви после проверки `Player.IsPlayerStart` длина стадии заменяется: **`StageLength = 100 + 2.5 × Level`**, `@4973–5079`. Поэтому число 180 нельзя безусловно считать действующим временем стадии.
- Период `AddTime`: **`StageLength / 240`**, `@2387–2429`.
- Morning: **`ClientDelayTimer = 15 × (0.95 − 0.01 × Level) × 2.5`**, `@3814–4008`.
- Lunch: **`ClientDelayTimer = 15 × (0.95 − 0.01 × Level)`**, `@4259–4411`.
- Сброс подготовки выставляет `Hour=8`, `Minute=0`, `@4166–4189`; закрывающая ветвь выставляет `Hour=16`, `@2670`.
- Закрывающая проверка клиентов использует timer 3 секунды, `@2744`. Early-end и tutorial имеют отдельные переходы.

`BP_ClientSpawner`, `ExecuteUbergraph_BP_ClientSpawner`, `@372–568`:

```text
period = ClientDelayTimer × clamp(ClientMultiplier, 0.5, 2.0)
timerInitialStartDelay = −0.8 × period
```

`ClientDelayTimer=10` и `ClientMultiplier=1` — defaults спавнера. Первый параметр затем меняет daily cycle. Чем больше `ClientMultiplier`, тем длиннее интервал. Отрицательный initial delay записан буквально; точное поведение первой доставки timer callback требует проверки UE/runtime, оно не подменено догадкой.

## Ожидание клиента и кофе

`BP_Client`, `ExecuteUbergraph_BP_Client`:

- `PatienceProgress` вызывается каждую **1 секунду**, `@3600`.
- Если клиент не tutorial: **`Patience += 0.01`**, `@13713–13794`.
- При `Patience >= 1` клиент уходит и увеличивает `MissedOrders`, `@13884–14101`.
- Порог нетерпения: **0.75**, `@14585`.
- Подача кофе сбрасывает `Patience=0`, `@24725`.

Номинально 0→1 занимает около 100 тиков без пауз, кофе и особых ветвей. Это арифметический вывод; не замер секундомером. В коде присутствуют pause/clear timer, поэтому переносить 100 секунд на все состояния клиента нельзя.

## Продажа, чаевые и XP

`BP_Client`, `ExecuteUbergraph_BP_Client`:

- В столовом пути базовая выплата: **`Food.Value + float(Level) / 25`**, `@23226–23336`.
- Аналогичная надбавка к значению предмета витрины присутствует в `@9050–9182`.
- При `Patience <= 0.75` найден путь чаевых, `@18695–19132`:

```text
tipBase = Food.Value × 0.2 × (1 − Patience)
tipMultiplier = 1 + integer_division(BonusPercentage, 100)
tip = tipBase × tipMultiplier
```

Здесь действительно **`Divide_IntInt`**, затем преобразование в float. При `BonusPercentage` 0–99 эта ветвь даёт множитель 1, при 100 — 2. Это наблюдение байткода; ожидаемый плавный процентный бонус не доказан. Не исправлять автоматически при описании оригинала.

- Путь `FoodReaction` передаёт **`Food.Value × 3`** в `GainExperience`, `@19177–19241`.
- Усыновление кошки имеет вызов `Player.AddMoney(7.5)`, `@3044`. Все условия достижимости и взаимодействие с другими выплатами ещё требуют gameplay-теста.

`BP_Player`, `ExecuteUbergraph_BP_Player`, `@15657–16407`:

```text
if Level < 40:
    Experience += Gain / CRV_Experience(Level)
    shownGain = trunc(Gain × 10)
    if Experience >= 1:
        LevelUp()
```

XP-поле нормализовано; показанное число не равно прибавке к полю `Experience`. Кривая `CRV_Experience` содержит кубические ключи `(0, 50)`, `(2, 125)`, `(40, 1650)` с авторскими tangents. Полные ключи: [curves.json](data/curves.json). Интерполяция не линейная; не восстанавливайте промежуточные уровни линейкой между точками.

## Печь

`BP_KitchenOven` defaults: `CompletedCookTime=15`, `BurnedCookTime=30`, `FirewoodTime=90`, `BurnDelayExtra=15`.

- `CompletedCookTime` заменяется `DAT_Recipe.BakeTime`, `ExecuteUbergraph_BP_KitchenOven @2144`.
- В cook tick `CurrentCookTime` увеличивается на 1, `@4193–4235`.
- Готовность проверяется по **`CurrentCookTime >= CompletedCookTime`**, `@5257`.
- Сгорание: **`CurrentCookTime >= CompletedCookTime + BurnedCookTime`**, `@4276–4322`.
- При сгорании готовый предмет уничтожается и создаётся `BurnedFood`; счётчик `PastriesBurned` увеличивается.
- Улучшение печи в `WBP_ShopSingle.ExecuteUbergraph_WBP_ShopSingle @6180` назначает **`BurnedCookTime=60`**.

Таким образом, табличное время рецепта и запас до сгорания — разные величины. Поле `BurnDelayExtra=15` существует, но его присутствие само по себе не доказывает итоговый запас 15 секунд.

## Бонусы меню

Суммы: [DAT_Bonus.json](data/tables/DAT_Bonus.json). Условия: `WBP_DailyOverview.IsBonusActive`.

| ID | Значение | Условие в статическом коде | Адрес |
| --- | ---: | --- | --- |
| CheapPastry | +10 | Среднее `DAT_Item.Value` ≤ 2 | @1446 |
| QuickBake | +10 | Среднее `DAT_Recipe.BakeTime` ≤ 10 | @2219 |
| DifferentType | +20 | Не менее 4 разных категорий | @2981 |
| VeganOption | +15 | Есть строка с `IsVegan=true` | @3039–3526 |
| GlutenFreeOption | +15 | Есть строка с `IsGlutenFree=true` | @3550–4037 |
| NewRecipe | +50 | Меню пересекается со списком `NewRecipes` | @4061–4566 |
| PricyPastry | −10 | Среднее `DAT_Item.Value` ≥ 3 | @5286 |
| SlowBake | −10 | Среднее `DAT_Recipe.BakeTime` ≥ 20 | @6059 |
| SameType | −12 | Не более 2 разных категорий | @6821 |
| OldRecipe | −25 | В меню есть рецепт с `BonusDayOldRecipe[index] >= 2` | @7274–7377 |
| NoBakeOption | −15 | Нет категории Bread/Cookie/Donut/Cake/Pie | @7487–8346 |
| LowOption | −10 | В меню не более 2 рецептов | @8451 |
| HighOption | +10 | В меню не менее 5 рецептов | @8590 |

Сборщик бонусов начинает с нуля и **после каждого прибавления** выполняет `clamp(sum, 0, 100)`, `WBP_DailyOverview.ExecuteUbergraph_WBP_DailyOverview @21287, @22142–22235`. Это не всегда эквивалентно одному clamp после общей суммы: порядок обхода может влиять на результат.

`OldRecipe` нельзя сокращать до «рецепт старше двух дней»: условие использует конкретный history-массив, отдельно от `RecipeActiveDays`. Порядок его обновления нужно проследить перед точной адаптацией.

## Ингредиенты и базовые параметры

Overrides уровня для `BP_ItemSpawner`: растения обычно `SpawnTimer=15`; flour/sugar/milk/egg — 3; honey — 5; coffee — 2; firewood — 1. Полная таблица и теги: [WORLD.md](WORLD.md). Уход, вместимость, разблокировка и timer lifecycle влияют на фактический выход продукции.

`BP_Player` defaults: `Money=5`, `Level=1`, `WalkSpeed=500`, `SprintRecharge=3`. `BP_CatCafe.CatsToSpawn=2`; `BP_ClientSpawner.GlobalCatAdoptionRate≈0.9`. Это параметры, а не измеренные игровые вероятности после всех ветвей и апгрейдов.
