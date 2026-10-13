# Invite HUD artwork

`invite-friends.png` is the original transparent PNG generated with the built-in ImageGen tool on 2026-10-11. It contains two cream/turquoise speech bubbles with a gold plus and cocoa outlines. The source retains its alpha channel and is 1254 by 1254 pixels.

The uploaded image is `rbxassetid://72029296612385`, named `funset_ui_invite_friends`, owned by group `712136202`. `ReplicatedStorage/Shared/Configs/Friends.luau` is the runtime asset and layout owner. `InviteHandler/Control` places the icon immediately to the left of the existing Friend Boost text; the PNG contains no button background or caption.

Claude Opus 4.8 provided a visual consultation only. ImageGen generated the bitmap, and Codex implemented the control. The compact row uses a 28-pixel icon, a six-pixel icon/text gap, the real authored boost label capped at 20-pixel text, and one transparent 226 by 44-pixel hitbox. Pressing the icon or boost text runs the same native invitation flow; no separate card or Invite caption is drawn.

## Generation prompt

Use case: stylized-concept. Asset type: one small Roblox bakery game HUD Invite icon, transparent PNG. Primary request: a clear cheerful invitation symbol made from two overlapping plump rounded speech bubbles and a small gold plus badge. Back bubble warm cream #FDEAC3, front bubble saturated soft turquoise deeper than a bright turquoise bakery wall, gold plus badge at lower right. Chunky hand-painted cartoon game icon, like a colorful bakery shop cart or gift icon: bold dark cocoa-brown outer outline #5F3333, orange-gold rim accents #EEA54B, broad clean forms, restrained glossy highlights and subtle volume. Front-facing, centered, full uncropped silhouette filling about 82 percent of a square canvas. Plus sign readable when scaled to34px. Actual transparent background, clean alpha edges, no surrounding button/card/container, no scene, no lettering, no faces, no watermark, no tiny decorative details. Friendly warm game art; readable against both warm wood and bright turquoise. Generate a single polished production icon.
