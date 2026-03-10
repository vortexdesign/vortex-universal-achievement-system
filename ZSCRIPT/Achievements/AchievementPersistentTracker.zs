// AchievementPersistentTracker.zs
// EventHandler that mirrors in-progress counters from the StaticEventHandler.
//
// PURPOSE: StaticEventHandler data does NOT serialize with savegames.
// This regular EventHandler DOES serialize, so it acts as a save/load mirror
// for achievement progress counters. Contains NO logic -- just data arrays.
//
// SYNC PATTERN (from BoA Tracker.zs lines 983-1060):
//   WorldUnloaded: Handler copies counters TO this tracker
//   WorldLoaded(IsSaveGame): Handler copies counters FROM this tracker
//
// This ensures that when a player loads a savegame, their in-progress
// achievement counters are restored even though the StaticEventHandler
// data was lost.

class VUAS_PersistentTracker : EventHandler
{
    override void OnRegister()
    {
        SetOrder(10);
    }

    // Parallel arrays mirroring VUAS_AchievementData fields that need save/load
    // Index corresponds to achievements[] index in the handler
    Array<int> achievementCounts;       // currentCount per achievement
    Array<int> achievementInvalidated;  // invalidated flag per achievement (0/1)
}
