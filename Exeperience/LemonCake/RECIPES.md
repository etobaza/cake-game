# Каталог рецептов

Источник: `Blueprints/Items/DAT_Recipe.uasset`, build `6596857`. Табличные значения; не измерение полного цикла приготовления.

`Value` — базовое значение таблицы, `BakeTime` — поле времени. Нулевое `BakeTime` не доказывает мгновенное приготовление: существуют миксер и морозильник. Диетические флаги сохранены буквально, даже если противоречат составу. Порядок строк не означает уровень открытия.

Полные записи, ссылки на иконки и исходные enum IDs: [DAT_Recipe.json](data/tables/DAT_Recipe.json).

| № | ID | Категория | Value | BakeTime | Ингредиенты | Vegan | GlutenFree |
| --- | --- | --- | ---: | ---: | --- | --- | --- |
| 0 | `FrenchBaguette` | Bread | 1.5 | 5 | Flour | True | False |
| 1 | `SweetRoll` | Donut | 1.75 | 8 | Flour, Sugar | True | False |
| 2 | `MarshmallowTwist` | Candy | 0.75 | 0 | Sugar | True | True |
| 3 | `SweetPretzel` | Bread | 1.75 | 10 | Flour, Sugar | True | False |
| 4 | `ChocolateCookie` | Cookie | 2 | 12 | Flour, Cocoa | True | False |
| 5 | `ChocolateCroissant` | Bread | 2.25 | 12 | Flour, Sugar, Cocoa | True | False |
| 6 | `StrawberryDonut` | Donut | 2.5 | 14 | Flour, Sugar, Strawberry | True | False |
| 7 | `EggBenedict` | Bread | 2 | 12 | Flour, Egg | False | False |
| 8 | `CherryJelly` | Donut | 2.25 | 12 | Flour, Sugar, Cherry | True | False |
| 9 | `ChocolateStrawberry` | Candy | 2 | 0 | Strawberry, Cocoa | True | True |
| 10 | `BlueberryBagel` | Bread | 2.5 | 14 | Flour, Blueberry | True | False |
| 11 | `HoneyTaffy` | Candy | 1.75 | 0 | Honey | False | True |
| 12 | `BerryCrumble` | Pie | 3 | 20 | Flour, Sugar, Strawberry, Blueberry | True | False |
| 13 | `RaisinBread` | Bread | 2.5 | 15 | Flour, Sugar, Grape | True | False |
| 14 | `AppleTart` | Pie | 3 | 25 | Flour, Apple | True | False |
| 15 | `StrawberryScone` | Cookie | 2.5 | 14 | Flour, Egg, Strawberry | False | False |
| 16 | `ChocolateEclair` | Donut | 3 | 16 | Flour, Milk, Cocoa | False | False |
| 17 | `RainbowLollipop` | Candy | 2.75 | 0 | Sugar, Blueberry, Strawberry, Grape | True | True |
| 18 | `CarrotGranolaBar` | Cookie | 3.25 | 22 | Flour, Carrot, Grape | True | False |
| 19 | `BlueberryCheesecake` | Cake | 3.5 | 28 | Milk, Sugar, Blueberry | False | True |
| 20 | `GrapePopsicle` | Frozen | 1.75 | 0 | Sugar, Grape | True | True |
| 21 | `AppleStrudel` | Donut | 2.75 | 20 | Flour, Egg, Apple | False | False |
| 22 | `MilkChocolate` | Candy | 2 | 0 | Cocoa, Milk, Sugar | False | True |
| 23 | `SoftServe` | Frozen | 2 | 0 | Milk, Sugar | False | True |
| 24 | `HoneyCruller` | Donut | 2.25 | 15 | Flour, Egg, Honey | False | False |
| 25 | `CaramelFlan` | Pie | 2.5 | 18 | Milk, Egg, Sugar | False | True |
| 26 | `chocolatePancake` | Cake | 2.75 | 10 | Flour, Milk, Egg, Cocoa | False | False |
| 27 | `CarrotPie` | Pie | 2.5 | 16 | Flour, Egg, Carrot | False | False |
| 28 | `CaramelApple` | Candy | 2.25 | 0 | Apple, Milk, Sugar | False | True |
| 29 | `CherryBundtCake` | Cake | 3.75 | 30 | Flour, Milk, Egg, Cherry | False | False |
| 30 | `IceCreamSandwich` | Frozen | 2.5 | 0 | Milk, Sugar, Cocoa | False | True |
| 31 | `RedVelvetCake` | Cake | 3 | 25 | Flour, Sugar, Milk | False | False |
| 32 | `StrawberryIceCream` | Frozen | 2.5 | 0 | Milk, Sugar, Strawberry | False | True |
| 33 | `CherryBiscotti` | Cookie | 2.5 | 18 | Flour, Sugar, Milk, Cherry | False | False |
| 34 | `HoneyMacaron` | Cookie | 3.25 | 25 | Flour, Honey, Egg, Milk | False | False |
| 35 | `LemonSorbet` | Frozen | 2.75 | 0 | Sugar, Lemon | True | True |
| 36 | `CarrotCupcake` | Cake | 2.75 | 10 | Flour, Sugar, Carrot | True | False |
| 37 | `LemonWafer` | Cookie | 3 | 18 | Flour, Milk, Lemon | False | False |
| 38 | `LemonMeringue` | Pie | 3.5 | 30 | Flour, Egg, Lemon | False | False |
| 39 | `WaffleSundae` | Frozen | 3.75 | 0 | Flour, Milk, Cherry, Cocoa | False | False |
| 40 | `CherryPie` | Pie | 3.75 | 25 | Flour, Milk, Sugar, Cherry | True | False |
| 41 | `LemonCake` | Cake | 4 | 30 | Flour, Sugar, Milk, Lemon | False | False |
