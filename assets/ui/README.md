# Invite HUD artwork

`invite-friends.png` is the original transparent PNG generated with the built-in ImageGen tool on 2026-10-11. It contains two cream/turquoise speech bubbles with a gold plus and cocoa outlines. The source retains its alpha channel and is 1254 by 1254 pixels.

The uploaded image is `rbxassetid://72029296612385`, named `funset_ui_invite_friends`, owned by group `712136202`. `ReplicatedStorage/Shared/Configs/Friends.luau` is the runtime asset and layout owner. `InviteHandler/Control` places the icon immediately to the left of the existing Friend Boost text; the PNG contains no button background or caption.

## Generation prompt

Use case: stylized-concept. Asset type: one small Roblox bakery game HUD Invite icon, transparent PNG. Primary request: a clear cheerful invitation symbol made from two overlapping plump rounded speech bubbles and a small gold plus badge. Back bubble warm cream #FDEAC3, front bubble saturated soft turquoise deeper than a bright turquoise bakery wall, gold plus badge at lower right. Chunky hand-painted cartoon game icon, like a colorful bakery shop cart or gift icon: bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 82 percent of a square canvas. Plus sign readable when scaled to 34px. Actual transparent background, clean alpha edges, no surrounding button/card/container, no scene, no lettering, no faces, no watermark, no tiny decorative details. Friendly warm game art; readable against both warm wood and bright turquoise. Generate a single polished production icon.

# Loading screen artwork

Both images were generated with the Codex CLI image generator on 2026-10-14 from in-game screenshots (and `invite-friends.png` as the icon style reference), then uploaded through Roblox Studio. The authored `ReplicatedFirst.LoadingScreen` uses them; `ReplicatedFirst/Loading.client.luau` drives it.

- `loading-background.png`: 1536 by 1024 RGB bakery interior, uploaded as `rbxassetid://122067093949828`, drawn full screen with `ScaleType.Crop`.
- `loading-cake.png`: 1254 by 1254 transparent strawberry layer cake on a cream stand, uploaded as `rbxassetid://83400406464065`, the bobbing badge art.

## Background generation prompt

A wide landscape 3:2 loading-screen background for a cozy Roblox bakery tycoon game, in the same chunky smooth low-poly toon Roblox look as the reference: a bright bakery interior with turquoise-and-white striped walls, warm glossy orange wood floor and beams, cream rounded arches, small triangle bunting flags in turquoise, red and cream, wooden wall shelves with stacked plates and little potted plants, a glass display counter filled with colorful cakes, cupcakes and sweet rolls, and a round brick wood-fired oven glowing softly. Warm afternoon sunlight through big windows, soft depth of field. Keep the central and lower-middle area calm and slightly softer (open floor, no busy detail) so a title, a progress bar and a tip line can be overlaid there. No people, no characters, no animals, no text, no letters, no logos, no UI, no watermark. Palette anchored on turquoise #3CC6C9, orange #EEA54B, cream #FDEAC3, cocoa brown #5F3333 and tomato red #E34A3A.

## Cake generation prompt

A square 1:1 transparent PNG game icon of one cute two-tier strawberry layer cake standing on a small cream cake stand: pink frosting drips, white whipped-cream swirls, plump red strawberries on top with a single cherry, a few sprinkles. Chunky hand-painted cartoon game icon, bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, warm cream #FDEAC3 stand, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 80 percent of the canvas, readable when scaled down to 64 px. Actual transparent background with clean alpha edges, no surrounding button, card, circle or shadow plate, no scene, no text, no face, no watermark.

# Store product icons

Uploaded on 2026-10-15 as Creator Dashboard product icons, replacing the placeholder (`88963008124478`) the first three products shared. They were generated with the Codex CLI image generator on 2026-10-14, with `invite-friends.png` and `loading-cake.png` attached as style references. Each is a 1254 by 1254 transparent PNG. In game, the featured Starter Pack row keeps its authored gift art and the reward-screen skip plates have no icon, so these images are only the Dashboard product icons.

- `starter-pack.png`: an open cream-and-turquoise gift box with a gold bow, a pink cupcake and gold coins (product `starter_pack`, icon `104737582313244`).
- `skip-daily.png`: a blank cream calendar page with a turquoise header and a gold fast-forward badge (product `skip_daily`, icon `74587734918217`).
- `skip-playtime.png`: a gold-rimmed cream-and-turquoise stopwatch with a gold fast-forward badge and coins (product `skip_playtime`, icon `106532204543851`).
- `skip-daily-all.png`: a fanned stack of three calendar pages with a gold triple chevron and coins (product `skip_daily_all`, `3718628937`, icon `77174434849627`). Generated on 2026-10-15 with `skip-daily.png` as a third reference so the pair matches.

## Starter pack generation prompt

Use case: stylized-concept. Asset type: one Roblox bakery game store product icon, transparent PNG, square 1024x1024 or larger. Primary request: a "Starter Pack" bundle for a new bakery: an open cream-and-turquoise bakery gift box tied with a gold ribbon bow, a frosted pink cupcake with a cherry and a small stack of shiny gold coins peeking out of the box, a few gold coins in front of it. Chunky hand-painted cartoon game icon matching the two attached reference images: bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, warm cream #FDEAC3 and soft turquoise accents, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 82 percent of a square canvas. Actual transparent background with clean alpha edges, no surrounding button/card/container, no scene, no lettering, no numbers, no faces, no watermark, no tiny decorative details. Friendly warm game art, readable at 84px against both warm wood and bright turquoise. Generate a single polished production icon.

## Skip 1 Day generation prompt

Use case: stylized-concept. Asset type: one Roblox bakery game store product icon, transparent PNG, square 1024x1024 or larger. Primary request: a "Skip 1 Day" daily reward icon: a chunky cream tear-off calendar page with a turquoise header band and two binder rings, with a big glossy gold double-chevron fast-forward arrow badge overlapping its lower right corner. The calendar page is blank (no digits, no text). Chunky hand-painted cartoon game icon matching the two attached reference images: bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, warm cream #FDEAC3 and soft turquoise accents, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 82 percent of a square canvas. Actual transparent background with clean alpha edges, no surrounding button/card/container, no scene, no lettering, no numbers, no faces, no watermark, no tiny decorative details. Friendly warm game art, readable at 84px against both warm wood and bright turquoise. Generate a single polished production icon.

## Skip All Days generation prompt

Use case: stylized-concept. Asset type: one Roblox bakery game store product icon, transparent PNG, square 1024x1024 or larger. Primary request: a "Skip All Days" daily reward icon, the bigger sibling of the attached calendar icon: a fanned stack of three chunky cream tear-off calendar pages with turquoise header bands and binder rings, the front page fully visible and the two behind it peeking out above and to the left, a small pile of shiny gold coins at the foot of the stack, and a big glossy gold TRIPLE-chevron fast-forward arrow badge overlapping the lower right corner. The calendar pages are blank (no digits, no text). Chunky hand-painted cartoon game icon matching the attached reference images: bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, warm cream #FDEAC3 and soft turquoise accents, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 82 percent of a square canvas. Actual transparent background with clean alpha edges, no surrounding button/card/container, no scene, no lettering, no numbers, no faces, no watermark, no tiny decorative details. Friendly warm game art, readable at 84px against both warm wood and bright turquoise. Generate a single polished production icon.

## Skip All generation prompt

Use case: stylized-concept. Asset type: one Roblox bakery game store product icon, transparent PNG, square 1024x1024 or larger. Primary request: a "Skip All" playtime reward icon: a plump cream-and-turquoise stopwatch with a gold crown button and a gold rim, its hands pointing up, with a big glossy gold double-chevron fast-forward arrow badge overlapping its lower right corner and a few small gold coins tucked behind the stopwatch. Chunky hand-painted cartoon game icon matching the two attached reference images: bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, warm cream #FDEAC3 and soft turquoise accents, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 82 percent of a square canvas. Actual transparent background with clean alpha edges, no surrounding button/card/container, no scene, no lettering, no numbers, no faces, no watermark, no tiny decorative details. Friendly warm game art, readable at 84px against both warm wood and bright turquoise. Generate a single polished production icon.

# Next Day button artwork

Both icons were generated with the Codex CLI image generator on 2026-10-15, with `invite-friends.png` as the style reference. The sunrise also used `loading-cake.png`, and the arrow used `skip-daily.png`. They were trimmed to their content, padded to a square, saved at 512 by 512 with transparency, and uploaded through Roblox Studio. The authored `BakeryMenu.MainFrame.Header.Buttons.NextDay` draws them over its green face.

- `next-day-sunrise.png`: a glossy golden sun rising behind a cream cloud, uploaded as `rbxassetid://77968188446656` (`Sun`, rising above the button's left end).
- `next-day-arrow.png`: a cream double chevron, uploaded as `rbxassetid://109769025639835` (`Arrow`, at the right end).

## Sunrise generation prompt

Use case: stylized-concept. Asset type: one Roblox bakery game UI icon for the "Next Day" button, transparent PNG. Primary request: a cheerful sunrise: a plump glossy golden-yellow sun rising from behind a soft fluffy cream cloud, with eight short chunky rounded rays fanning out above it, a small white sparkle on the sun, warm orange-gold glow on the rim. It should instantly read as "a new morning / start the day". Chunky hand-painted cartoon game icon matching the two attached reference images: bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, warm cream #FDEAC3 cloud, golden sun #FFC94A to #F7A531, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 84 percent of a square canvas, the cloud across the lower part. Readable when scaled down to 56 px against a bright green button. Actual transparent background with clean alpha edges, no surrounding button/card/circle/shadow plate, no scene, no ground, no lettering, no numbers, no face on the sun, no watermark, no tiny decorative details. Generate a single polished production icon.

## Arrow generation prompt

Use case: stylized-concept. Asset type: one Roblox bakery game UI icon, transparent PNG. Primary request: a bold "go forward" double chevron arrow pointing to the right: two chunky rounded chevrons (like >>) side by side, the front one slightly larger, filled warm cream-white #FFF6E0 with a soft top gloss highlight and a light orange-gold inner rim #EEA54B. Chunky hand-painted cartoon game UI style matching the two attached reference images: bold dark cocoa-brown outer outline #5F3333 around each chevron, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 80 percent of a square canvas. Readable when scaled down to 32 px on a bright green button. Actual transparent background with clean alpha edges, no surrounding button/card/circle/shadow plate, no scene, no lettering, no numbers, no watermark, no other objects. Generate a single polished production icon.

# Worker, boost and limited product icons

Creator Dashboard icons for the four products that still showed Roblox's grey placeholders on 2026-10-27 (the passes shared `133448903949274`, the two developer products `88963008124478`). Each is a 512 by 512 transparent PNG, trimmed and centred with a 6 percent margin. They are not used in game; upload each one on its product's Creator Dashboard page.

- `hire-helper.png` (`pass_helper`, `2046249065`) and `auto-cleaner.png` (`pass_cleaner`, `2047982350`): the in-game Store tile art (`rbxassetid://76365950185800`, `rbxassetid://125288289282098`) taken from its 420 px Roblox thumbnail and upscaled, so the Dashboard matches the Store.
- `cash-boost-2x.png` (`boost_cash_2x`, `3720887751`): a gold coin embossed with a green "2x" over a small coin pile.
- `limited-golden-oven.png` (`limited_slot`, `3720767346`): the Golden Oven drop, a gold-brick oven with a clock chimney, a fire mouth and three magenta gems, drawn after a capture of the `GoldenOvenShowcase` model.

The last two were generated with the Codex CLI image generator on 2026-10-27, with the existing Dashboard product icons (and, for the oven, the in-game capture) attached as references.

## 2x Cash generation prompt

It is the Roblox developer-product icon for "2x Cash", a 15-minute double-coins boost in a cosy cartoon bakery game. Subject: a big shiny gold coin standing slightly tilted with a bold chunky green "2x" embossed on its face, a small pile of gold coins at its base, a few sparkles. The only text in the whole image is "2x", spelled exactly. Style: match the attached store icons exactly (the gold coin stacks there are the same family) - glossy hand-painted mobile game icon, thick dark brown outline, warm saturated colours, soft highlights, centred, fills about 80% of the square. No other text, no background scenery, no frame or badge behind it. 1024x1024 PNG, transparent background.

## Golden Oven generation prompt

It is the Roblox developer-product icon for "Golden Oven", a limited item in a cosy cartoon bakery game. Subject: a small arched brick bakery oven made entirely of shiny gold, with a round clock on the chimney, a glowing warm orange fire mouth, three magenta ruby gems set in the gold bricks (one on top, one on each side), a few gold sparkles and a soft golden glow around it. The attached capture shows the in-game model to copy the design from. Style: match the attached store and pass icons exactly - glossy hand-painted mobile game icon, thick dark brown outline around the whole object, warm saturated colours, soft highlights, centred, the object fills about 80% of the square, slight 3/4 view. No text, no letters, no numbers, no background scenery, no frame or badge behind it. 1024x1024 PNG, transparent background.

# HUD offer icons

Generated with the Codex CLI image generator on 2026-10-29, with `cash-boost-2x.png` and `starter-pack.png` as style references, trimmed and centred at 512 by 512 with a 6 percent margin. The client `CashBoostHandler` swaps the HUD's 2x Cash button to them while the offer applies (`Configs/Offers` `Hud.Icon`). Uploaded through `AssetService:CreateAssetAsync` as images owned by group `712136202`.

- `rescue-dish.png` (`rescue_dish`): a golden baguette rising out of grey smoke with a green circular restore badge, `rbxassetid://78412774375162`.
- `keep-guests.png` (`keep_guest`): a gold hourglass with turquoise sand and a pink heart badge with a white plus, `rbxassetid://134349148673729`.

## Prompt

Both are small HUD offer icons for a cosy cartoon bakery Roblox game. Style: match the two attached reference icons exactly (cash-boost-2x.png and starter-pack.png): glossy hand-painted mobile game icon, bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, warm cream #FDEAC3 and soft turquoise accents, broad clean forms, restrained glossy highlights and subtle volume, a few small sparkles. Front-facing, centered, full uncropped silhouette filling about 80 percent of a square 1024x1024 canvas. Actual transparent background with clean alpha edges, no surrounding button/card/circle/shadow plate, no scene, no lettering, no numbers, no faces, no watermark, no tiny details. Must read clearly at 60 px on a bright bakery wall.

1. "Rescue Dish": a plump freshly baked golden-brown French baguette loaf, glossy and perfect, rising out of a small puff of soft grey smoke at its base, with a big glossy green circular "undo / restore" arrow badge overlapping the lower right corner, and a couple of gold sparkles around the bread.
2. "Keep Guests": a chunky gold-framed hourglass with cream glass and turquoise sand, tilted slightly, with a big glossy pink-red heart badge with a small white plus overlapping its lower right corner, and a couple of gold sparkles.
