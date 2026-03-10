# Vortex's Universal Achievement System (VUAS) v0.1.0

A clean universal achievement system for GZDoom/UZDoom by Vortex.
Inspired by Blade of Agony, Stupid Achievements, GZ_Goalz, and GZAchievementsPOC.

- Pure ZScript or ZScript + ACS via the included bridge (`ACHIEVEMENTS_BRIDGE_ACS.txt`)
- Sibling to [Vortex's Universal Objective System (VUOS)](https://github.com/vortexdesign/vortex-universal-objective-system) — same design language, zero shared code, fully standalone
- Full options menu under **Options > Universal Achievements**

## License

- MIT (see LICENSE file)
- Credit appreciated (see CREDITS.txt)

## Getting Started (Players)

1. Load the VUAS PK3 file alongside any GZDoom/UZDoom mod
2. Achievement toasts will pop up as you play (if the mod defines achievements otherwise there's a few default ones)
3. Browse unlocked achievements via **Options > Universal Achievements > Browse Achievements**
4. Customize toast appearance, colors, sounds, and position in the settings menu

## Getting Started (Modders)

1. Add VUAS to your project's load order
2. Create a subclass of `VUAS_AchievementSetup` and override `DefineAchievements()`
3. Register your subclass in ZMAPINFO (replace `VUAS_AchievementSetup` with your class name)
4. Achievements persist across maps and game sessions automatically via CVars

## Features

### Achievement Types
- **ACH_TYPE_BINARY (1)** — Simple unlock (targetCount = 1)
- **ACH_TYPE_THRESHOLD (0)** — Unlock when currentCount >= targetCount

### Auto-Tracking Types
- **TRACK_MANUAL (0)** — Modder calls `IncrementProgress()` or `Unlock()` explicitly
- **TRACK_KILLS (1)** — Auto-tracked via `WorldThingDied` (optional targetClass filter, replacement-aware)
- **TRACK_DAMAGE_DEALT (2)** — Auto-tracked via `WorldThingDamaged` (player attacking, replacement-aware)
- **TRACK_DAMAGE_TAKEN (3)** — Auto-tracked via `WorldThingDamaged` (player receiving, replacement-aware)
- **TRACK_SECRETS (4)** — Auto-tracked when secrets are found (polls `player.secretcount`)
- **TRACK_ITEMS (5)** — Auto-tracked when items are collected (polls `player.itemcount`)
- **TRACK_CUSTOM_EVENT (6)** — Triggered via netevent with matching achievement ID

### Cumulative vs Per-Map Progress
Achievements can be cumulative (progress persists across maps, the default) or per-map (progress resets on each new map). Any achievement type can be either.

### Hidden / Secret Achievements
Hidden achievements show as "???" in the browse menu until unlocked. Players can toggle hidden achievement visibility in settings.

### Skill-Level Filtering
Each achievement has min/max skill level fields (0-4). Achievements outside the current skill range are automatically excluded from auto-tracking.

### Enemy Mod Compatibility
Class-targeted achievements (kill/damage tracking with a `targetClass`) automatically work with enemy replacement mods. When a mod uses the `replaces` keyword (e.g. `class CyberImp : Actor replaces DoomImp`), VUAS detects this via the engine's replacement chain (`Actor.GetReplacee`) and class inheritance (`is` operator). An achievement targeting `'DoomImp'` will match CyberImp if it replaces or extends DoomImp. Players can load VUAS alongside enemy mods and 3rd party maps without any configuration.

### Cheat Detection
When cheats are detected (noclip, god mode, buddha), all cheat-protected in-progress achievements are invalidated for the rest of the session. Already-unlocked achievements are preserved.

### Persistent Storage
Achievement completion state persists across maps and game sessions via `nosave` CVars in the player's INI file. Data is optionally encoded with Base64+ROT for light obfuscation. In-progress counters survive save/load via a dual-handler pattern (StaticEventHandler + EventHandler mirror).

### Event Callbacks
Override these in your `VUAS_AchievementSetup` subclass:
```c
virtual void OnAchievementUnlocked(VUAS_AchievementData ach) {}
virtual void OnProgressUpdated(VUAS_AchievementData ach, int oldCount, int newCount) {}
virtual void OnCheatDetected(int playerNum) {}
```

## Toast Notifications

- Procedural or textured rendering style (with fallback)
- 6 positions: top-right, top-left, bottom-right, bottom-left, top-center, bottom-center
- Fine-tune X/Y offset adjustment
- 3 animation types: none, slide (vertical or horizontal), fade
- SmoothStep easing for smooth animations
- Dual border layers (outer accent + inner) with customizable colors
- Configurable scale, opacity, and duration
- FIFO notification queue for multiple unlocks
- Icon support with BoA-style dim effect for locked state

## Achievement Menu

- Browse all achievements grouped by category
- Filter: All, Unlocked Only, Locked Only
- Hidden achievements shown as "???" (toggleable)
- Unlock timestamps displayed on completed achievements
- Progress counters on in-progress achievements
- 7 customizable colors via options menu
- Opened via `openmenu VUASAchievementBrowse` or keybind

## Sound System

- 4 selectable unlock sounds
- Per-player playback on all active players
- Configurable enable/disable

## Multiplayer / Co-op Notes

VUAS is primarily a single-player system, but its architecture avoids multiplayer desync by design. If your mod supports co-op, here's what you need to know:

**Shared state** — Achievements are stored on the `StaticEventHandler` instance (server-side). All players share the same achievement list, progress, and completion state.

**Per-player rendering** — Toast notifications and the browse menu render per-client using `consoleplayer`. Each player sees their own CVar settings (position, colors, scale, etc.).

**Sound** — Unlock sounds play on all active players via `PlaySoundAllPlayers()`. No player misses a notification.

**For modders** — Avoid using `consoleplayer` in play-scope code (use `GetFirstPlayer()` or iterate `playeringame[]` instead). All static API methods (`Unlock`, `IncrementProgress`, `UpdateProgress`, etc.) are multiplayer-safe.

## Keybinds

Rebindable under **Options > Customize Controls > Achievements**:

| Key | Action |
|-----|--------|
| (unbound) | Open Achievement Menu |

## API Reference

### Adding Achievements
```c
// Standard achievement (binary if targetCount=1, threshold otherwise)
static void AddAchievement(
    String id,                      // Unique key (e.g. "kill_100_imps")
    String title,                   // Display name
    String desc,                    // Description text
    String category,                // For menu grouping: "combat", "exploration", etc.
    int targetCount,                // Threshold to unlock (1 for binary)
    int trackingType = TRACK_MANUAL,// Auto-tracking type
    name targetClass = '',          // Actor class filter for kill/damage tracking
    String icon = "ACHVMT00",       // Graphic name (dimmed when locked, full-color when unlocked)
    bool isHidden = false,          // Hidden until unlocked
    bool isCumulative = true,       // Progress persists across maps
    bool cheatProtected = true,     // Invalidated when cheats detected
    int minSkill = 0,               // Minimum skill level (0-4)
    int maxSkill = 4                // Maximum skill level (0-4)
)
```

### Progress & Completion
```c
static void Unlock(String id)                       // Force unlock
static void IncrementProgress(String id, int amount) // Add to progress
static void UpdateProgress(String id, int newValue)  // Set exact progress
static void SetHidden(String id, bool hidden)         // Show or hide achievement
static void ClearAchievement(String id)              // Clear to locked
static void ClearAll()                               // Clear all achievements
static void UnlockAll()                              // Unlock all (debug)
```

### Queries
```c
static VUAS_AchievementData FindByID(String id)     // Get achievement data
static bool IsUnlocked(String id)                    // Check completion
static int GetProgress(String id)                    // Get current count
static int GetTargetCount(String id)                 // Get target count
static int GetUnlockedCount()                        // Total unlocked
static int GetTotalCount()                           // Total defined
```

## Console Commands
```
ach_help                          - Show all commands
ach_list                          - List all achievements with status
ach_debug                         - Toggle debug output
ach_clear_all                     - Clear all achievements
ach_unlock_all                    - Unlock all achievements
netevent ach_info <index>         - Show detail for achievement #
netevent ach_unlock <index>       - Force unlock achievement #
netevent ach_clear <index>        - Clear achievement #
netevent ach_progress <index> <n> - Add progress to achievement #
```

## ACS Bridge Scripts
```
AchUnlock(achID)                  - Unlock an achievement
AchIncrementProgress(achID, n)    - Increment progress by n
AchUpdateProgress(achID, n)       - Set progress to exact value
AchIsUnlocked(achID)              - Check if unlocked (returns 0/1)
AchGetProgress(achID)             - Get current progress count
AchGetTargetCount(achID)          - Get target count
AchClear(achID)                   - Clear a single achievement
AchSetHidden(achID, hidden)       - Set hidden state (1=hide, 0=reveal)
AchGetUnlockedCount()             - Get total unlocked count
AchGetTotalCount()                - Get total achievement count
```

## Architecture
```
VUAS_AchievementData (Plain class)
  - achievementID, title, description, category
  - achievementType, targetCount, currentCount
  - isUnlocked, isHidden, unlockTime, unlockMap
  - targetClass, trackingType, isCumulative
  - minSkillLevel, maxSkillLevel
  - icon
  - cheatProtected, invalidated

VUAS_AchievementHandler (StaticEventHandler)
  - achievements[] registry, static API
  - Auto-tracking hooks (kills, damage, secrets, items, custom events)
  - Persistence (Base64+ROT encode/decode, 4-CVar split)
  - Cheat detection, sound playback
  - Dual-handler sync with PersistentTracker

VUAS_AchievementSetup (StaticEventHandler)
  - Modder subclass: override DefineAchievements()
  - Centralized restore sequence on WorldLoaded
  - Event callbacks (OnAchievementUnlocked, OnProgressUpdated, etc.)

VUAS_PersistentTracker (EventHandler)
  - Save/load mirror for in-progress counters
  - Parallel arrays serialized with savegames

VUAS_AchievementRenderer (EventHandler)
  - RenderOverlay dispatch, SystemTime relay
  - Notification FIFO queue management

VUAS_AchievementNotification (UI class)
  - Toast popup drawing with animations
  - 6 positions, slide/fade/none, SmoothStep easing

VUAS_AchievementBrowseMenu (OptionMenu subclass)
  - Category grouping, filters, hidden toggle
  - CVar-driven colors, timestamps, progress display

VUAS_AchievementCommands (StaticEventHandler)
  - Console command processing via netevent
```

## Examples

### Example 1: Basic Kill Tracking
```c
class MyAchievements : VUAS_AchievementSetup
{
    override void DefineAchievements()
    {
        // Binary: unlocks on first kill of any monster
        VUAS_AchievementHandler.AddAchievement(
            "first_blood", "First Blood",
            "Kill your first enemy", "combat",
            1, TRACK_KILLS
        );

        // Threshold: kill 100 of any monster (cumulative across maps)
        VUAS_AchievementHandler.AddAchievement(
            "kill_100", "Century",
            "Kill 100 enemies", "combat",
            100, TRACK_KILLS
        );

        // Targeted: only counts DoomImp kills
        VUAS_AchievementHandler.AddAchievement(
            "kill_imps", "Imp Slayer",
            "Kill 50 Imps", "combat",
            50, TRACK_KILLS, 'DoomImp'
        );
    }
}
```

### Example 2: Skill-Filtered Achievement
```c
// Only available on Ultra-Violence (skill 3) and Nightmare (skill 4)
VUAS_AchievementHandler.AddAchievement(
    "uv_warrior", "Ultraviolent",
    "Kill 25 enemies on UV or Nightmare", "challenge",
    25, TRACK_KILLS,
    '',         // targetClass (any monster)
    "ACHVMT00", // icon
    false,      // isHidden
    true,       // isCumulative
    true,       // cheatProtected
    3,          // minSkill (Ultra-Violence)
    4           // maxSkill (Nightmare)
);
```

### Example 3: Hidden Achievement with Callback
```c
override void DefineAchievements()
{
    VUAS_AchievementHandler.AddAchievement(
        "hidden_gem", "Hidden Gem",
        "Discover the hidden achievement", "secret",
        1, TRACK_MANUAL,
        '', true  // isHidden = true
    );
}

override void OnAchievementUnlocked(VUAS_AchievementData ach)
{
    if (ach.achievementID == "hidden_gem")
        Console.Printf("You found the hidden gem!");
}
```

### Example 4: Custom Event Tracking
```c
// In DefineAchievements:
VUAS_AchievementHandler.AddAchievement(
    "use_turrets", "Turret Master",
    "Use turrets 5 times", "combat",
    5, TRACK_CUSTOM_EVENT
);

// From ZScript (anywhere in play scope):
EventHandler.SendNetworkEvent("vuas_event:use_turrets", 1);

// Or from ACS:
ScriptCall("VUAS_AchievementHandler", "IncrementProgress", "use_turrets", 1);
```

### Example 5: ACS Linedef Trigger
```c
// Button in map editor that unlocks an achievement:
//   Linedef Action: ACS_Execute (80)
//   Script: "AchUnlock"
//   Arg1: "find_secret_weapon"

// Check completion for conditional logic:
script "CheckAndOpen" (void)
{
    int unlocked = ACS_ExecuteWithResult("AchIsUnlocked", "find_secret_weapon");
    if (unlocked)
    {
        Door_Open(1, 64);
    }
}
```

### Example 6: VUOS Integration (Conditional Unlock)
```c
// Requires both VUAS and VUOS loaded.
// Override OnObjectiveCompleted in your VUOS_ObjectiveSetup subclass
// to trigger VUAS achievements based on objective completion conditions.

class MyObjectives : VUOS_ObjectiveSetup
{
    override void OnObjectiveCompleted(VUOS_ObjectiveData obj)
    {
        // Unlock "Avoid Imps" if the player completed the map objective
        // without killing any imps (tracked by your own variable)
        if (obj.objectiveID == "clear_map01" && myImpKillCount == 0)
            VUAS_AchievementHandler.Unlock("avoid_imps");
    }
}

// In your VUAS_AchievementSetup subclass:
VUAS_AchievementHandler.AddAchievement(
    "avoid_imps", "Pacifist (Imps)",
    "Complete a map without killing any Imps", "challenge",
    1, TRACK_MANUAL
);
```

### Example 7: Custom Event (Melee Attack)
```c
// Fire a netevent from your weapon's ZScript when a melee attack lands.
// VUAS picks it up via TRACK_CUSTOM_EVENT with matching achievement ID.

// In your Fist/melee weapon's Fire or Attack state:
EventHandler.SendNetworkEvent("vuas_event:first_melee", 1);

// In your VUAS_AchievementSetup subclass:
VUAS_AchievementHandler.AddAchievement(
    "first_melee", "Up Close and Personal",
    "Land your first melee attack", "combat",
    1, TRACK_CUSTOM_EVENT
);
```

---

## Changelog

### v0.1.0 (March 2026)

**Core System**
- Achievement data model with binary and threshold types
- StaticEventHandler-based handler with session-lifetime persistence
- Dual-handler pattern for save/load of in-progress counters (BoA pattern)
- Static API for all achievement operations (add, unlock, progress, query, clear)
- Centralized restore sequence preventing ordering bugs on save/load

**Auto-Tracking**
- 7 tracking types: manual, kills, damage dealt, damage taken, secrets, items, custom events
- Class-targeted tracking for kills and damage (optional targetClass filter, replacement-aware)
- Skill-level filtering with min/max range per achievement
- Cumulative or per-map progress modes

**Persistence**
- nosave CVar persistence across game sessions via player INI file
- Base64+ROT encoding for light obfuscation (toggleable)
- 4-CVar split for achievement data + 4 for unlock map names (60 achievement capacity)
- Auto-detect encoding on deserialize (prevents corruption if encoding toggled)

**Notifications**
- Toast popup system with FIFO queue for multiple unlocks
- 6 positions with X/Y offset adjustment
- 3 animation types: slide (vertical/horizontal), fade, none
- SmoothStep easing, dual border layers, icon support
- Procedural or textured rendering style
- 4 selectable unlock sounds
- Stale notification cleanup on save load

**Achievement Menu**
- OptionMenu subclass with category grouping
- Filter by all/unlocked/locked
- Hidden achievement toggle (shows as "???")
- Unlock timestamps and progress counters
- 7 customizable colors (26 named color options each)

**Cheat Detection**
- Detects noclip, god mode, and buddha mode
- Invalidates cheat-protected in-progress achievements
- Sticky detection (stays active for rest of session)
- Toggleable via CVar

**Settings & Customization**
- Full options menu under Options > Universal Achievements
- 32 CVars for toast, sound, colors, menu, and system settings
- Non-destructive MENUDEF (AddOptionMenu for mod compatibility)

**Console Commands**
- ach_list, ach_help, ach_debug, ach_clear_all, ach_unlock_all
- Index-based netevent commands for individual achievement operations
- Host-only gating for destructive/debug commands in multiplayer

**ACS Bridge**
- 10 ScriptCall wrapper scripts mirroring VUOS bridge pattern
- Full API: unlock, progress, query, clear, counts

**Compatibility**
- Runs alongside VUOS with no conflicts (Order 10 vs Order 0)
- All keybinds rebindable under Options > Customize Controls > Achievements

