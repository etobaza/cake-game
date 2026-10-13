# Admin abuse live event: engine limits

Research behind the live event (researched 2026-10-12). The implemented design is in the ARCHITECTURE.md section "Admin abuse live event"; the cast, scripts and tuning live in `Configs/AdminAbuse`. The cross-server path still needs a check in the published game with two or more servers.

## Roblox APIs and constraints

- **Avatar model.** `Players:GetHumanoidDescriptionFromUserIdAsync(userId)`, then `Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)`. Both yield; wrap them in `pcall`, cache the result per server and fall back gracefully when they fail. `Players:CreateHumanoidModelFromUserIdAsync(userId)` is a shortcut without a rig choice.
- **Giant size.** Use `Model:ScaleTo(factor)` on the built model. Model scaling also scales accessories, particles and Humanoid values such as HipHeight ([DevForum](https://devforum.roblox.com/t/npc-dummyrig-resizing-issue/2279914)). The alternative is HumanoidDescription scale properties, but those are clamped to avatar limits and unsuitable for a giant. Anchor the root, disable collisions or use a no-collide group, and keep it away from guest pathing.
- **Cross-server broadcast.** `MessagingService:PublishAsync(topic, message)` / `SubscribeAsync(topic, callback)`. The official limits at the time of research:
  - message size: 1 kB;
  - publishing: 600 + 240 × players messages per server per minute;
  - receiving: 40 + 80 × servers messages per topic per minute;
  - subscriptions: 20 + 8 × players per server.

  Delivery is **best effort, not guaranteed**. Send compact ids (event id, script id, start time), never dialogue text. Every server resolves text from config, and a periodic state re-broadcast lets a server that missed a message catch up ([MessagingService reference](https://create.roblox.com/docs/reference/engine/classes/MessagingService), [usage guide](https://create.roblox.com/docs/cloud/guides/usage-messaging)).
- **Synchronisation.** Publish an absolute start time from `workspace:GetServerTimeNow()` plus a short lead (a few seconds). Every server plays each line at start + offset, and late joiners compute the current line from the same clock.
- **Speech.** `TextChatService:DisplayBubble(partOrCharacter, message)` draws bubbles over the giant's head (client). A mirrored chat line uses `TextChannel:DisplaySystemMessage(text, metadata)` on the `RBXSystem` channel (client), styled through `TextChatService.OnIncomingMessage`. A HUD banner with the speaker's headshot (`Players:GetUserThumbnailAsync`, HeadShot) keeps the line readable when the chat is hidden.
- **Testing.** Avatar loading works in Studio. Studio checks the single-server path (local start, dialogue timing, guests, rain, cleanup, late join); the cross-server path needs the published game.
