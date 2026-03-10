// AchievementRenderer.zs
// EventHandler for rendering toast notifications and relaying SystemTime.
//
// Pattern: BoA Tracker.zs RenderOverlay -> SendNetworkEvent("time", SystemTime.Now())
// Queue management: Stupid Achievements worldTick() FIFO dequeue pattern
// Settings cache: VUOS ObjectiveRenderer cachedRenderSettings pattern
//
// This is an EventHandler (not StaticEventHandler) because:
// 1. RenderOverlay is needed for UI drawing
// 2. It serializes with savegames (notification queue survives save/load)
// 3. BoA uses a separate EventHandler for its RenderOverlay relay

class VUAS_AchievementRenderer : EventHandler
{
    // Notification task queue (FIFO - first in, first out)
    // Current task is always index 0. When finished, delete(0) and start next.
    // Pattern from Stupid Achievements: sa_Achiever.mTasks
    Array<VUAS_NotificationTask> taskQueue;

    // Cached render settings - allocated once in OnRegister, refreshed every frame
    // Avoids per-frame GC allocation (VUOS pattern)
    VUAS_RenderSettings cachedRenderSettings;

    // Cached handler reference (set in WorldLoaded, read in RenderOverlay/NetworkProcess)
    // Avoids StaticEventHandler.Find() every frame
    VUAS_AchievementHandler cachedHandler;

    // Virtual resolution base (matches VUOS for consistency)
    const VIRTUAL_W = 640;
    const VIRTUAL_H = 480;

    // ====================================================================
    // LIFECYCLE
    // ====================================================================
    override void OnRegister()
    {
        SetOrder(10);
        // Allocate the settings cache once
        cachedRenderSettings = new("VUAS_RenderSettings");
    }

    // ====================================================================
    // QUEUE MANAGEMENT - called from handler when achievement unlocks
    // ====================================================================

    // Add a notification to the queue. If nothing is currently displaying,
    // the new task starts immediately.
    void QueueNotification(VUAS_AchievementData ach)
    {
        let task = new("VUAS_NotificationTask");
        task.achievementTitle = ach.title;
        task.achievementDesc = ach.description;
        task.iconName = ach.icon;
        task.birthTime = -1; // -1 = not started yet
        task.lifetime = 0;   // Set from CVar when started
        task.animTime = 0;   // Set from CVar when started
        task.animType = 0;   // Set from CVar when started

        taskQueue.Push(task);

        // If this is the only task, start it now
        if (taskQueue.Size() == 1)
        {
            StartCurrentTask();
        }

        if (VUAS_AchievementHandler.IsDebugEnabled())
            Console.Printf("VUAS: Queued notification for '%s' (queue size: %d)",
                ach.title, taskQueue.Size());
    }

    // Start the current (index 0) task - sets birth time and reads CVar settings
    private void StartCurrentTask()
    {
        if (taskQueue.Size() == 0) return;

        let task = taskQueue[0];
        task.birthTime = level.time;

        // Read settings from CVars at start time (not per-frame)
        // Use players[0] instead of consoleplayer for multiplayer safety (play scope must be deterministic)
        let p = players[0];
        task.lifetime = VUAS_AchievementHandler.GetCVarInt('ach_toast_duration', p, 140);
        if (task.lifetime < 35) task.lifetime = 35;
        if (task.lifetime > 350) task.lifetime = 350;

        task.animType = VUAS_AchievementHandler.GetCVarInt('ach_toast_animation', p, 1);

        // Animation time = 1/4 of lifetime (same ratio as Stupid Achievements default)
        task.animTime = task.lifetime / 4;
        if (task.animTime < 5) task.animTime = 5;
    }

    // ====================================================================
    // WORLD LOADED - clear stale notifications on save load
    // The Renderer (EventHandler) serializes with saves, so the taskQueue
    // may contain old notifications that would replay on load.
    // ====================================================================
    override void WorldLoaded(WorldEvent e)
    {
        // Cache handler reference once per map (avoids StaticEventHandler.Find() every tic)
        cachedHandler = VUAS_AchievementHandler.GetHandler();

        // Re-create settings cache if lost (e.g. edge case deserialization).
        // Must happen in play scope (WorldLoaded), not UI scope (RenderOverlay).
        if (!cachedRenderSettings)
            cachedRenderSettings = new("VUAS_RenderSettings");

        if (e.IsSaveGame && taskQueue.Size() > 0)
        {
            if (VUAS_AchievementHandler.IsDebugEnabled())
                Console.Printf("VUAS: Clearing %d stale notification(s) from save", taskQueue.Size());
            taskQueue.Clear();
        }
    }

    // ====================================================================
    // WORLD TICK - manage queue lifecycle (play scope)
    // Pattern: Stupid Achievements worldTick() + VUOS WorldTick()
    // ====================================================================
    override void WorldTick()
    {
        // Process task queue
        if (taskQueue.Size() > 0)
        {
            let task = taskQueue[0];

            // Guard against save-loaded tasks with null data
            // (Stupid Achievements pattern: isLoadedFromSave check)
            if (task.birthTime < 0)
            {
                // Task was never started (shouldn't happen, but safety)
                StartCurrentTask();
            }
            else if (task.IsFinished(level.time))
            {
                // Current task finished - remove and start next
                taskQueue.Delete(0);

                if (taskQueue.Size() > 0)
                {
                    StartCurrentTask();
                }

                if (VUAS_AchievementHandler.IsDebugEnabled())
                    Console.Printf("VUAS: Task dequeued (remaining: %d)", taskQueue.Size());
            }
        }
    }

    // ====================================================================
    // RENDER OVERLAY - draw current toast + relay SystemTime
    // Pattern: BoA Tracker.zs line 1037-1041 for SystemTime relay
    //          VUOS ObjectiveRenderer for settings refresh + dispatch
    // ====================================================================
    override void RenderOverlay(RenderEvent e)
    {
        // Relay SystemTime to play scope (BoA pattern).
        // KNOWN TRADE-OFF: This fires every rendered frame (not every tic), which means
        // clients at different framerates send this event at different rates. This is the
        // same pattern BoA uses (Tracker.zs line 1040). The practical impact is low because
        // the handler only stores the latest value (no accumulation) and SystemTime has
        // 1-second resolution, but it does produce redundant network events in multiplayer.
        EventHandler.SendNetworkEvent("vuas_time", SystemTime.Now());

        // Early out if nothing to draw
        if (taskQueue.Size() == 0) return;

        // Skip if player not valid
        PlayerInfo player = players[consoleplayer];
        if (!player || !player.mo) return;

        // Skip if settings cache not ready (should never happen - created in OnRegister/WorldLoaded)
        if (!cachedRenderSettings) return;

        // Skip if toasts disabled
        let rs = cachedRenderSettings;
        rs.Refresh();

        if (!rs.toastEnabled) return;

        // Skip drawing if screenblocks > 11 (fullscreen HUD hidden)
        if (screenblocks > 11) return;

        // Get virtual dimensions (VUOS pattern: StatusBar.GetHUDScale)
        int virtualW = VIRTUAL_W;
        int virtualH = VIRTUAL_H;
        if (StatusBar)
        {
            Vector2 hudScale = StatusBar.GetHUDScale();
            if (hudScale.X > 0 && hudScale.Y > 0)
            {
                virtualW = int(Screen.GetWidth() / hudScale.X);
                virtualH = int(Screen.GetHeight() / hudScale.Y);
            }
        }

        // Draw current toast notification
        let task = taskQueue[0];
        if (task.birthTime >= 0 && !task.IsFinished(level.time))
        {
            VUAS_AchievementNotification.DrawToast(task, level.time, e.fracTic, rs, virtualW, virtualH);
        }
    }

    // ====================================================================
    // NETWORK PROCESS - handle notification queue events from handler
    // ====================================================================
    override void NetworkProcess(ConsoleEvent e)
    {
        // Achievement unlocked notification (fired from handler)
        if (e.Name == "vuas_achievement_unlocked" && e.Args[0] >= 0)
        {
            let handler = cachedHandler;
            if (!handler) handler = VUAS_AchievementHandler.GetHandler();
            if (!handler) return;

            int achIndex = e.Args[0];
            if (achIndex < handler.achievements.Size())
            {
                QueueNotification(handler.achievements[achIndex]);
            }
        }

        // Test toast (fired from MENUDEF "Show Test Toast" button)
        // Queues a fake notification to preview current toast settings.
        if (e.Name == "vuas_test_toast")
        {
            let task = new("VUAS_NotificationTask");
            task.achievementTitle = "Test Achievement";
            task.achievementDesc = "This is a test notification";
            task.iconName = "ACHVMT00";
            task.birthTime = -1;
            task.lifetime = 0;
            task.animTime = 0;
            task.animType = 0;
            taskQueue.Push(task);
            if (taskQueue.Size() == 1)
                StartCurrentTask();
        }
    }
}

// ============================================================================
// VUAS_NotificationTask
// Holds data for one queued toast notification.
// Lives in AchievementRenderer.zs because it is only used by the renderer.
// Pattern: Stupid Achievements sa_Task (birth time + lifetime + animation)
// ============================================================================
class VUAS_NotificationTask
{
    // Achievement display data (copied at queue time, not a reference)
    String achievementTitle;
    String achievementDesc;
    String iconName;

    // Timing
    int birthTime;      // level.time when this task started displaying (-1 = not started)
    int lifetime;       // Total display duration in tics (from CVar)
    int animTime;       // Animation duration in tics (slide/fade in + out)
    int animType;       // 0=none, 1=slide, 2=fade (matches ach_toast_animation CVar)

    // Check if this task has finished displaying
    bool IsFinished(int levelTime)
    {
        if (birthTime < 0) return false;
        return levelTime > birthTime + lifetime;
    }

    // Get elapsed time since birth
    int GetElapsed(int levelTime)
    {
        if (birthTime < 0) return 0;
        return levelTime - birthTime;
    }

    // Get animation fraction for slide-in (0.0 to 1.0)
    double GetFractionIn(int elapsed, double fracTic)
    {
        if (animTime <= 0) return 1.0;
        double t = (elapsed + fracTic) / animTime;
        if (t < 0) return 0.0;
        if (t > 1.0) return 1.0;
        return t;
    }

    // Get animation fraction for slide-out (0.0 to 1.0)
    double GetFractionOut(int elapsed, double fracTic)
    {
        if (animTime <= 0) return 0.0;
        double t = (elapsed + fracTic - (lifetime - animTime)) / animTime;
        if (t < 0) return 0.0;
        if (t > 1.0) return 1.0;
        return t;
    }

    // Is this task in the slide-in phase?
    bool IsAnimatingIn(int elapsed)
    {
        return elapsed < animTime;
    }

    // Is this task in the slide-out phase?
    bool IsAnimatingOut(int elapsed)
    {
        return elapsed > (lifetime - animTime);
    }
}
