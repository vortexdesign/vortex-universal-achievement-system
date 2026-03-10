// AchievementSetup.zs
// Base class for modders to subclass and define their achievements.
//
// USAGE:
// 1. Create your own class extending VUAS_AchievementSetup
// 2. Override DefineAchievements() to register achievements using the static API
// 3. Override callback methods for custom behavior on unlock/progress
// 4. Register your subclass in ZMAPINFO (replace VUAS_AchievementSetup with your class name)
//    Callbacks will work automatically because Setup registers itself on the handler.
//
// EXAMPLE:
//   class MyAchievements : VUAS_AchievementSetup
//   {
//       override void DefineAchievements()
//       {
//           // Basic kill tracking (any monster)
//           VUAS_AchievementHandler.AddAchievement("kill_100", "Century",
//               "Kill 100 enemies", "combat", 100, TRACK_KILLS);
//
//           // Targeted class tracking
//           VUAS_AchievementHandler.AddAchievement("kill_imps", "Imp Slayer",
//               "Kill 50 Imps", "combat", 50, TRACK_KILLS, 'DoomImp');
//
//           // Secret finding
//           VUAS_AchievementHandler.AddAchievement("find_secret", "Explorer",
//               "Find a secret area", "exploration", 1, TRACK_SECRETS);
//
//           // UV+ only achievement (minSkill=3, maxSkill=4)
//           VUAS_AchievementHandler.AddAchievement("uv_clear", "Hardcore",
//               "Clear a map on UV+", "challenge", 1, TRACK_MANUAL,
//               '', "ACHVMT00", false, true, true, 3, 4);
//       }
//
//       override void OnAchievementUnlocked(VUAS_AchievementData ach)
//       {
//           Console.Printf("You unlocked: %s!", ach.title);
//       }
//   }

class VUAS_AchievementSetup : StaticEventHandler
{
    // Flag to prevent re-definition on every map load
    // Achievements only need to be defined once per game session
    bool hasDefinedAchievements;

    override void OnRegister()
    {
        SetOrder(10);
    }

    // ====================================================================
    // WORLD LOADED - calls DefineAchievements once per session
    // ====================================================================
    override void WorldLoaded(WorldEvent e)
    {
        // Only define achievements once per game session
        // (StaticEventHandler persists across map transitions)
        if (!hasDefinedAchievements)
        {
            DefineAchievements();
            hasDefinedAchievements = true;

            // Restore completion state from nosave CVars AFTER achievements are defined.
            // This must happen here (not in Handler.WorldLoaded or OnRegister) because
            // those can fire before DefineAchievements, leaving an empty array.
            let handler = VUAS_AchievementHandler.GetHandler();
            if (handler)
            {
                // Register ourselves so GetSetup() works with subclasses.
                // Find() requires the exact class name, so a modder's "MyAchievements"
                // subclass wouldn't be found by Find("VUAS_AchievementSetup").
                handler.cachedSetup = self;

                handler.DeserializeAll();

                // On save load: also restore in-progress counters from PersistentTracker
                if (e.IsSaveGame)
                    handler.RestoreFromTracker();
            }

            if (VUAS_AchievementHandler.IsDebugEnabled())
                Console.Printf("VUAS: Achievements defined (%d total), state restored from CVars",
                    VUAS_AchievementHandler.GetTotalCount());
        }
        else if (e.IsSaveGame)
        {
            // On subsequent save loads (same session), achievements already defined
            // but we still need to restore state
            let handler = VUAS_AchievementHandler.GetHandler();
            if (handler)
            {
                // Re-cache self: StaticEventHandler fields are transient on save/load,
                // so cachedSetup may be null after loading a save.
                handler.cachedSetup = self;

                handler.DeserializeAll();
                handler.RestoreFromTracker();
            }
        }
    }

    // ====================================================================
    // DEFINE ACHIEVEMENTS - Override this in your subclass
    // Called once per game session on the first WorldLoaded.
    // ====================================================================
    virtual void DefineAchievements()
    {
        // Default implementation: sample achievements for testing and modder reference.
        // Modders should override this method with their own achievements.
        // Each example below demonstrates a different feature of the system.

        // --- Combat achievements ---

        // Binary achievement: single kill triggers unlock (TRACK_KILLS, no targetClass = any monster)
        VUAS_AchievementHandler.AddAchievement(
            "first_blood", "First Blood",
            "Kill your first enemy", "combat",
            1, TRACK_KILLS, '', "ACHVMT00"
        );

        // Threshold achievement: cumulative kill count across maps (default isCumulative=true)
        VUAS_AchievementHandler.AddAchievement(
            "kill_50", "Warrior",
            "Kill 50 enemies", "combat",
            50, TRACK_KILLS, '', "ACHVMT01"
        );

        // Targeted tracking: only counts kills of a specific actor class
        VUAS_AchievementHandler.AddAchievement(
            "kill_100_imps", "Imp Slayer",
            "Kill 100 Imps", "combat",
            100, TRACK_KILLS, 'DoomImp', "ACHVMT02"
        );

         // Targeted tracking: only counts kills of a specific actor class
        VUAS_AchievementHandler.AddAchievement(
            "kill_100_zombiemen", "Zombie Slayer",
            "Kill 100 Zombie Men", "combat",
            100, TRACK_KILLS, 'ZombieMan', "ACHVMT03"
        );

        // --- Exploration achievements ---

        // Secret tracking: auto-increments when player finds secrets (TRACK_SECRETS)
        VUAS_AchievementHandler.AddAchievement(
            "secret_finder", "Secret Finder",
            "Find a secret area", "exploration",
            1, TRACK_SECRETS, '', "ACHVMT04"
        );

        // Multi-secret threshold: find 10 secrets total across all maps
        VUAS_AchievementHandler.AddAchievement(
            "secret_hunter", "Secret Hunter",
            "Find 10 secret areas", "exploration",
            10, TRACK_SECRETS, '', "ACHVMT05"
        );

        // --- Challenge achievements ---

        // Skill-filtered: only available on Ultra-Violence (skill 3) and Nightmare (skill 4)
        VUAS_AchievementHandler.AddAchievement(
            "uv_warrior", "Ultraviolent",
            "Kill 25 enemies on UV or Nightmare", "challenge",
            25, TRACK_KILLS,
            '',         // targetClass (any monster)
            "ACHVMT06", // icon
            false,      // isHidden
            true,       // isCumulative
            true,       // cheatProtected
            3,          // minSkill (Ultra-Violence)
            4           // maxSkill (Nightmare)
        );

        // Hidden achievement: shows as "???" in menu until unlocked (manual trigger)
        VUAS_AchievementHandler.AddAchievement(
            "hidden_gem", "Hidden Gem",
            "Discover the hidden achievement", "challenge",
            1, TRACK_MANUAL,
            '',         // targetClass
            "ACHVMT00", // icon
            true        // isHidden
        );
    }

    // ====================================================================
    // ADVANCED EXAMPLES (not active - reference patterns for modders)
    // ====================================================================
    //
    // --- VUOS Integration: unlock achievement when an objective completes ---
    // Requires both VUAS and VUOS loaded. Override OnObjectiveCompleted in
    // your VUOS_ObjectiveSetup subclass to trigger VUAS achievements.
    //
    //   class MyObjectives : VUOS_ObjectiveSetup
    //   {
    //       override void OnObjectiveCompleted(VUOS_ObjectiveData obj)
    //       {
    //           // Unlock "Avoid Imps" if player completed the map objective
    //           // without killing any imps (check your own tracking variable)
    //           if (obj.objectiveID == "clear_map01" && myImpKillCount == 0)
    //               VUAS_AchievementHandler.Unlock("avoid_imps");
    //       }
    //   }
    //
    //   // In your VUAS_AchievementSetup subclass:
    //   VUAS_AchievementHandler.AddAchievement(
    //       "avoid_imps", "Pacifist (Imps)",
    //       "Complete a map without killing any Imps", "challenge",
    //       1, TRACK_MANUAL
    //   );
    //
    // --- Custom Event: track first melee attack ---
    // Fire a netevent from your weapon's ZScript when a melee attack lands.
    // VUAS picks it up via TRACK_CUSTOM_EVENT with matching achievement ID.
    //
    //   // In your Fist/melee weapon's Fire or Attack state:
    //   EventHandler.SendNetworkEvent("vuas_event:first_melee", 1);
    //
    //   // In your VUAS_AchievementSetup subclass:
    //   VUAS_AchievementHandler.AddAchievement(
    //       "first_melee", "Up Close and Personal",
    //       "Land your first melee attack", "combat",
    //       1, TRACK_CUSTOM_EVENT
    //   );

    // ====================================================================
    // CALLBACKS - Override these in your subclass for custom behavior
    // ====================================================================

    // Called when any achievement is unlocked
    virtual void OnAchievementUnlocked(VUAS_AchievementData ach)
    {
        // Example: Console.Printf("Achievement unlocked: %s", ach.title);
    }

    // Called when achievement progress is updated
    virtual void OnProgressUpdated(VUAS_AchievementData ach, int oldCount, int newCount)
    {
        // Example: Console.Printf("%s: %d / %d", ach.title, newCount, ach.targetCount);
    }

    // Called when cheats are detected for a player
    virtual void OnCheatDetected(int playerNum)
    {
        // Example: Console.Printf("Cheats detected - some achievements invalidated");
    }
}
