// AchievementCommands.zs
// Console command dispatcher for VUAS.
// Handles ach_* netevent commands via NetworkProcess.
// Mirrors VUOS ObjectiveCommands.zs pattern.
//
// USAGE: Commands are KEYCONF aliases that fire netevents.
//   ach_list       -> netevent ach_list       (no args)
//   ach_debug      -> netevent ach_debug      (no args)
//   ach_clear_all  -> netevent ach_clear_all  (no args)
//   ach_unlock_all -> netevent ach_unlock_all (no args)
//   ach_help       -> netevent ach_help       (no args)
//
// For commands that target a specific achievement, use the index from ach_list:
//   netevent ach_unlock <index>               (integer arg)
//   netevent ach_clear <index>                (integer arg)
//   netevent ach_progress <index> <amount>    (two integer args)
//   netevent ach_info <index>                 (integer arg)

class VUAS_AchievementCommands : StaticEventHandler
{
    override void OnRegister()
    {
        SetOrder(10);
    }

    override void NetworkProcess(ConsoleEvent e)
    {
        // Gate destructive/debug commands to host only (player 0) for multiplayer safety.
        // Read-only commands (ach_help, ach_list, ach_info) are allowed for all players.
        bool isHostOnly = (e.Name ~== "ach_clear_all" || e.Name ~== "ach_unlock_all"
            || e.Name ~== "ach_unlock" || e.Name ~== "ach_clear"
            || e.Name ~== "ach_progress" || e.Name ~== "ach_debug");
        if (isHostOnly && e.Player != 0)
        {
            Console.Printf("VUAS: This command is restricted to the host.");
            return;
        }

        // ach_help - Show available commands
        if (e.Name ~== "ach_help")
        {
            Console.Printf("\c[Gold]=== VUAS Achievement Commands ===\c-");
            Console.Printf("ach_list                          - List all achievements");
            Console.Printf("ach_help                          - Show this help text");
            Console.Printf("netevent ach_info <index>         - Show detail for achievement #");
            Console.Printf("\c[DarkGray]--- Host-only commands (multiplayer) ---\c-");
            Console.Printf("ach_debug                         - Toggle debug output");
            Console.Printf("ach_clear_all                     - Clear all achievements");
            Console.Printf("ach_unlock_all                    - Unlock all achievements");
            Console.Printf("netevent ach_unlock <index>       - Force unlock achievement #");
            Console.Printf("netevent ach_clear <index>        - Clear achievement #");
            Console.Printf("netevent ach_progress <index> <amount> - Add progress to achievement #");
            Console.Printf("Use ach_list to see achievement indices.");
            return;
        }

        // ach_list - Print all achievements with status
        if (e.Name ~== "ach_list")
        {
            let handler = VUAS_AchievementHandler.GetHandler();
            if (!handler || handler.achievements.Size() == 0)
            {
                Console.Printf("VUAS: No achievements defined");
                return;
            }

            // Count unlocked using the handler we already have (avoids redundant GetHandler calls)
            int totalCount = handler.achievements.Size();
            int unlockedCount = 0;
            for (int u = 0; u < totalCount; u++)
            {
                if (handler.achievements[u].isUnlocked)
                    unlockedCount++;
            }

            Console.Printf("\c[Gold]--- VUAS Achievement List ---\c-");
            Console.Printf("Total: %d | Unlocked: %d", totalCount, unlockedCount);
            Console.Printf("");

            for (int i = 0; i < handler.achievements.Size(); i++)
            {
                let ach = handler.achievements[i];
                String status;

                if (ach.isUnlocked)
                    status = "\c[Green][UNLOCKED]\c-";
                else if (ach.invalidated)
                    status = "\c[Red][INVALID]\c-";
                else if (ach.currentCount > 0)
                    status = String.Format("\c[Yellow][%d/%d]\c-", ach.currentCount, ach.targetCount);
                else
                    status = "\c[DarkGray][LOCKED]\c-";

                String hidden = ach.isHidden ? " \c[Purple][HIDDEN]\c-" : "";

                String skillStr = "";
                if (ach.minSkillLevel > 0 || ach.maxSkillLevel < 4)
                    skillStr = String.Format(" \c[Cyan][Skill %d-%d]\c-", ach.minSkillLevel, ach.maxSkillLevel);

                Console.Printf("  [%d] %s %s - %s (%s)%s%s",
                    i, status, ach.title, ach.description,
                    ach.category, hidden, skillStr);
            }
            return;
        }

        // ach_debug - Toggle debug output
        if (e.Name ~== "ach_debug")
        {
            CVar dbg = CVar.FindCVar('vuas_debug');
            if (dbg)
            {
                dbg.SetBool(!dbg.GetBool());
                Console.Printf("VUAS: Debug output %s", dbg.GetBool() ? "ENABLED" : "DISABLED");
            }
            return;
        }

        // ach_clear_all - Clear all achievements
        if (e.Name ~== "ach_clear_all")
        {
            VUAS_AchievementHandler.ClearAll();
            return;
        }

        // ach_unlock_all - Unlock all achievements
        if (e.Name ~== "ach_unlock_all")
        {
            VUAS_AchievementHandler.UnlockAll();
            return;
        }

        // ach_info <index> - Show detailed info about an achievement
        if (e.Name ~== "ach_info")
        {
            let handler = VUAS_AchievementHandler.GetHandler();
            if (!handler) return;

            int idx = e.Args[0];
            if (idx < 0 || idx >= handler.achievements.Size())
            {
                Console.Printf("VUAS: Invalid index %d. Use ach_list to see valid indices.", idx);
                return;
            }

            let ach = handler.achievements[idx];
            Console.Printf("\c[Gold]--- Achievement [%d]: %s ---\c-", idx, ach.achievementID);
            Console.Printf("  Title: %s", ach.title);
            Console.Printf("  Description: %s", ach.description);
            Console.Printf("  Category: %s", ach.category);
            // Human-readable type and tracking names
            String typeName;
            switch (ach.achievementType)
            {
            case ACH_TYPE_BINARY:     typeName = "Binary";     break;
            case ACH_TYPE_THRESHOLD:  typeName = "Threshold";  break;
            default:                  typeName = String.Format("Unknown(%d)", ach.achievementType); break;
            }
            String trackName;
            switch (ach.trackingType)
            {
            case TRACK_MANUAL:        trackName = "Manual";       break;
            case TRACK_KILLS:         trackName = "Kills";        break;
            case TRACK_DAMAGE_DEALT:  trackName = "Damage Dealt"; break;
            case TRACK_DAMAGE_TAKEN:  trackName = "Damage Taken"; break;
            case TRACK_SECRETS:       trackName = "Secrets";      break;
            case TRACK_ITEMS:         trackName = "Items";        break;
            case TRACK_CUSTOM_EVENT:  trackName = "Custom Event"; break;
            default:                  trackName = String.Format("Unknown(%d)", ach.trackingType); break;
            }
            Console.Printf("  Type: %s | Tracking: %s", typeName, trackName);
            Console.Printf("  Progress: %d / %d (%.0f%%)", ach.currentCount, ach.targetCount, ach.GetProgressFraction() * 100);
            Console.Printf("  Unlocked: %s | Hidden: %s | Cheat Protected: %s",
                ach.isUnlocked ? "yes" : "no",
                ach.isHidden ? "yes" : "no",
                ach.cheatProtected ? "yes" : "no");
            if (ach.invalidated) Console.Printf("  \c[Red]INVALIDATED by cheats\c-");
            if (ach.isUnlocked) Console.Printf("  Unlock Time: %d | Map: %s", ach.unlockTime, ach.unlockMap);
            Console.Printf("  Skill Range: %d-%d%s", ach.minSkillLevel, ach.maxSkillLevel,
                (ach.minSkillLevel == 0 && ach.maxSkillLevel == 4) ? " (all)" : "");
            return;
        }

        // ach_unlock <index> - Force unlock an achievement by index
        if (e.Name ~== "ach_unlock")
        {
            let handler = VUAS_AchievementHandler.GetHandler();
            if (!handler) return;

            int idx = e.Args[0];
            if (idx < 0 || idx >= handler.achievements.Size())
            {
                Console.Printf("VUAS: Invalid index %d. Use ach_list to see valid indices.", idx);
                return;
            }

            let ach = handler.achievements[idx];
            // Bypass cheat protection for debug
            ach.invalidated = false;
            // Uses string-based Unlock() because UnlockByIndex is private on the handler.
            // Acceptable for a debug command (one extra FindIndexByID).
            VUAS_AchievementHandler.Unlock(ach.achievementID);
            return;
        }

        // ach_clear <index> - Clear an achievement by index
        if (e.Name ~== "ach_clear")
        {
            let handler = VUAS_AchievementHandler.GetHandler();
            if (!handler) return;

            int idx = e.Args[0];
            if (idx < 0 || idx >= handler.achievements.Size())
            {
                Console.Printf("VUAS: Invalid index %d. Use ach_list to see valid indices.", idx);
                return;
            }

            // Inline clear using index directly (avoids string-based ClearAchievement search)
            let ach = handler.achievements[idx];
            ach.isUnlocked = false;
            ach.currentCount = 0;
            ach.unlockTime = 0;
            ach.unlockMap = "";
            ach.invalidated = false;
            handler.SaveSingleCVar(idx);
            Console.Printf("VUAS: Achievement [%d] '%s' reset", idx, ach.achievementID);
            return;
        }

        // ach_progress <index> <amount> - Add progress to an achievement
        if (e.Name ~== "ach_progress")
        {
            let handler = VUAS_AchievementHandler.GetHandler();
            if (!handler) return;

            int idx = e.Args[0];
            int amount = e.Args[1];
            if (amount <= 0) amount = 1;

            if (idx < 0 || idx >= handler.achievements.Size())
            {
                Console.Printf("VUAS: Invalid index %d. Use ach_list to see valid indices.", idx);
                return;
            }

            let ach = handler.achievements[idx];
            // Bypass cheat protection for debug
            ach.invalidated = false;
            // Use index-based method directly (avoids redundant FindByID in IncrementProgress)
            handler.IncrementProgressByIndex(idx, amount);
            Console.Printf("VUAS: Added %d progress to [%d] '%s' (%d/%d)",
                amount, idx, ach.achievementID, ach.currentCount, ach.targetCount);
            return;
        }
    }
}
