# Источники и достоверность

## Основной источник: локальная установленная игра

- Steam app `1338330`, build `6596857`, depot `1338331`, manifest `3131561033263652299`.
- Каталог: `C:/Program Files (x86)/Steam/steamapps/common/Lemon Cake`.
- Архив: `LemonCake/Content/Paks/LemonCake-WindowsNoEditor.pak`, **480 756 603 байта**, `V8B`, индекс не зашифрован, compression `None` по repak.
- Движок: `LemonCake.uproject` → `EngineAssociation=4.24`; строки shipping EXE → `++UE4+Release-4.24-CL-11590370`.
- [build.json](data/build.json) содержит SHA256 архива и каждого установленного файла. Steam owner/account ID не переносился в базу.
- [files.csv](data/files.csv) содержит все 11 123 записи распакованного архива. Их общий размер — **472 915 295 байт**; он отличается от размера контейнера из-за служебных данных.

Пути исходных игровых ассетов в документации относительны `LemonCake/Content`. Например, `Blueprints/Items/DAT_Recipe.uasset` находится в `.local/unpacked/LemonCake/Content/Blueprints/Items/`. Исходные `.uexp` и `.ubulk` сохраняются рядом.

## Дополнительные первичные источники

Проверены 2026-09-22:

- [Steam: Lemon Cake](https://store.steampowered.com/app/1338330/Lemon_Cake/?l=english): название, разработчик/издатель Cozy Bee Games, выпуск 18 февраля 2021 года, одиночная игра, Steam Cloud, 17 достижений; общий цикл пекарни. Магазин — описание продукта, не источник точных формул установленной сборки.
- [repak](https://github.com/trumank/repak), [release v0.2.3](https://github.com/trumank/repak/releases/tag/v0.2.3): использован portable Windows CLI; SHA256 ZIP проверен по опубликованному checksum и закреплён в restore-скрипте.
- [UAssetAPI](https://github.com/atenfyr/UAssetAPI), [Basic Usage](https://atenfyr.github.io/UAssetAPI/guide/basic.html): использован NuGet `1.1.0`, сериализатор сообщает commit `7353081`; движок явно `VER_UE4_24`. Зависимости закреплены в [packages.lock.json](tools/AssetDump/packages.lock.json).

Страница Steam и сторонние описания не использовались для подстановки отсутствующих чисел в таблицы. Точные игровые значения извлечены локально.

## Уровни доказательности

1. **Данные**: поле таблицы, class default, override карты, строка конфигурации. Может быть изменено логикой в runtime.
2. **Статическая логика**: восстановленные операции Blueprint, ветви, вызовы и константы. Адрес `@...` — смещение в функции Kismet, не адрес машинного кода EXE.
3. **Вывод**: интерпретация связи нескольких операций. Указываем условия и ограничения; runtime не проверен.
4. **Runtime**: в этом исследовании отсутствует. Ни скриншоты магазина, ни стартовый лог не считаются прохождением механики.

`SerializeJson` не означает восстановление авторского исходника. Cooked-пакеты не содержат полный редакторский контекст графов; native-библиотеки, визуальная корректность мешей, звук и все варианты поведения не проверены исчерпывающе.
