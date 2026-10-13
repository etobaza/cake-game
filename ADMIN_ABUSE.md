# Admin abuse live event: plan

Status: implemented (TaskList 13.2-13.7); the cross-server path (13.8) still needs a check in the published game. See the ARCHITECTURE.md section "Admin abuse live event" for the implemented design. Spec from Martin (game designer, Discord, 2026-10-11), extended by the request of 2026-10-12.

## What the event is

An imitation of a developer "admin abuse":

- A giant avatar of a studio member appears over the bakeries.
- Their lines are broadcast to every server.
- Special guests with x5 income arrive.
- Cupcakes fall from the sky.

Several studio members can appear together and talk to each other in scripted dialogues.

## Cast

Avatars are built from these accounts at runtime, so outfit changes show up automatically. Display names are read at runtime (`Players:GetNameFromUserIdAsync`) and are not hardcoded.

| Id | UserId | Role |
| --- | --- | --- |
| `hyper` | 301599546 | Studio co-owner |
| `inc` | 1657140835 | Studio owner |
| `funset` | 11124027070 | Scripter |
| `martin` | 33640830 | Game designer |

## Roblox APIs and constraints (researched 2026-10-12)

- **Avatar model.** `Players:GetHumanoidDescriptionFromUserIdAsync(userId)`, then `Players:CreateHumanoidModelFromDescriptionAsync(description, Enum.HumanoidRigType.R15)`. Both yield; wrap them in `pcall`, cache the result per server and fall back gracefully when they fail. `Players:CreateHumanoidModelFromUserIdAsync(userId)` is a shortcut without a rig choice.
- **Giant size.** Use `Model:ScaleTo(factor)` on the built model. Model scaling also scales accessories, particles and Humanoid values such as HipHeight ([DevForum](https://devforum.roblox.com/t/npc-dummyrig-resizing-issue/2279914)). The alternative is HumanoidDescription scale properties, but those are clamped to avatar limits and unsuitable for a giant. Anchor the root, disable collisions or use a no-collide group, and keep it away from guest pathing.
- **Cross-server broadcast.** `MessagingService:PublishAsync(topic, message)` / `SubscribeAsync(topic, callback)`. The current official limits are:
  - message size: 1 kB;
  - publishing: 600 + 240 × players messages per server per minute;
  - receiving: 40 + 80 × servers messages per topic per minute;
  - subscriptions: 20 + 8 × players per server.

  Delivery is **best effort, not guaranteed**. Send compact ids (event id, script id, start time), never dialogue text. Every server resolves text from config, and a periodic state re-broadcast lets a server that missed a message catch up ([MessagingService reference](https://create.roblox.com/docs/reference/engine/classes/MessagingService), [usage guide](https://create.roblox.com/docs/cloud/guides/usage-messaging)).
- **Synchronisation.** Publish an absolute start time from `workspace:GetServerTimeNow()` plus a short lead (a few seconds). Every server plays each line at start + offset, and late joiners compute the current line from the same clock.
- **Speech.** Use `TextChatService:DisplayBubble(partOrCharacter, message)` for bubbles over the giant's head, called on the client. Put a mirrored line in chat with `TextChannel:DisplaySystemMessage(text, metadata)` on the `RBXSystem` channel (client), styled through `TextChatService.OnIncomingMessage`. Also show the line in a HUD banner with the speaker's headshot (`Players:GetUserThumbnailAsync`, HeadShot), so it is readable when the chat is hidden.
- **Testing.** Avatar loading works in Studio. The cross-server path can only be verified in the published game with two or more servers. Studio checks the single-server path (local start, dialogue timing, guests, rain, cleanup, late join).

## Planned implementation

The implementation follows AGENTS.md: one handler per system, Bus contracts and the existing admin access checks.

1. **`Configs/AdminAbuse`.** Contains:
   - the cast table above (`UserId`, role, giant scale, stand position relative to `Workspace.World`, idle/emote animation ids);
   - dialogue scripts as ordered `{ Speaker, Text, At }` lines, so several cast members can talk to each other;
   - event duration, x5 guest settings and cupcake rain settings.
2. **`CastRig` (server, private module).** Builds and caches each cast member's R15 model from their UserId. It scales the model with `ScaleTo`, anchors it, assigns the collision group and plays an idle animation. It has an owned cleanup path.
3. **`LiveEventHandler` (server).** Responsibilities:
   - subscribes to one MessagingService topic and publishes start/stop with compact payloads;
   - runs the timeline from the shared start time and re-broadcasts state periodically;
   - exposes `Start(scriptId)` / `Stop()` behind `AdminHandler:CanUse`, a Cmdr command and an admin panel button;
   - sends late joiners the running state.
4. **Bus.** `LiveEvent.State` (server → client: script id, start time, active flag). Clients derive the current line locally, so no per-line network traffic is needed.
5. **Client `LiveEventHandler`.** Shows bubbles, the system chat line and the HUD banner with headshot. It also shows a countdown/"event live" indicator and plays any camera or sound cue.
6. **Event guests.** A special customer type (or flag) whose payout is multiplied ×5 on the server, inside the existing CustomerHandler/EconomyHandler path. It is limited in count and shows the existing rare-guest notice.
7. **Cupcake rain.** The server spawns falling cupcake pickups around active bakeries. Collection is server-validated (distance, owner, rate). Pickups are capped and cleaned up when the event ends.
8. **Docs.** ARCHITECTURE.md section; TaskList entries.

## Decisions (2026-10-12)

Every value below is a default in `Configs/AdminAbuse`, meant to be tuned there.

- Giants: one shared line of giants outside the map, past the south end of the street, facing up the road; scale tuned in Studio (`Stage`).
- Dialogue: three drafted English scripts (`all_hands`, `owner_and_scripter`, `hyper_solo`); the speakers of a script are the giants on stage.
- Cupcakes: 2 coins each, at most 40 per player per event, 6 lying around a player at once (`Rain`).
- Golden guests: 35% of seated arrivals during the event, at most 1 per bakery, x5 coins (`Guests`, and `coinMultiplier` on the `event_guest` customer type).
- Access: the existing admins (`AdminHandler:CanUse` for the panel, the Cmdr `Admin` group for `/liveevent`). Manual starts and an optional UTC schedule (`Schedule.Enabled`).
- Duration: per script (`Duration`, 300 seconds by default).
- No "LIVE" tag on a cast member who is actually in the server, for now.
