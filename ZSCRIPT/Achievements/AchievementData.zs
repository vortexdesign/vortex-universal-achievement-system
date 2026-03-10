// AchievementData.zs
// Data structures for Vortex's Universal Achievement System (VUAS)

// ============================================================================
// Tracking type constants - what triggers progress for an achievement
// ============================================================================
// Used in VUAS_AchievementData.trackingType to determine how the handler
// auto-increments progress. TRACK_MANUAL means the modder must call
// IncrementProgress() or Unlock() explicitly.
enum VUAS_TrackingType
{
    TRACK_MANUAL = 0,       // Modder calls IncrementProgress/Unlock explicitly
    TRACK_KILLS = 1,        // Auto-increment on WorldThingDied for targetClass
    TRACK_DAMAGE_DEALT = 2, // Auto-increment on WorldThingDamaged (player attacking)
    TRACK_DAMAGE_TAKEN = 3, // Auto-increment on WorldThingDamaged (player receiving)
    TRACK_SECRETS = 4,      // Auto-increment when secrets are found
    TRACK_ITEMS = 5,        // Auto-increment when items are collected
    TRACK_CUSTOM_EVENT = 6  // Increment via netevent with matching ID
}

// ============================================================================
// Achievement type constants
// NOTE: Cumulative behavior (progress persists across maps) is controlled by
// the isCumulative bool field on VUAS_AchievementData, not by an enum value.
// Any type can be cumulative or non-cumulative independently.
// ============================================================================
enum VUAS_AchievementType
{
    ACH_TYPE_THRESHOLD = 0,  // Unlock when currentCount >= targetCount
    ACH_TYPE_BINARY = 1      // Simple unlock (targetCount = 1)
}

// ============================================================================
// VUAS_AchievementData
// Single class to hold all achievement state. One instance per achievement.
// Mirrors VUOS_ObjectiveData pattern (class-based, stored in handler array).
// ============================================================================
class VUAS_AchievementData
{
    // ---- Identity ----
    String achievementID;       // Unique key (e.g. "kill_100_imps")
    String title;               // Display name shown to player
    String description;         // What the player needs to do
    String category;            // For menu filtering: "combat", "exploration", "challenge", "secret"
    int achievementType;        // ACH_TYPE_THRESHOLD or ACH_TYPE_BINARY

    // ---- Progress ----
    int targetCount;            // Threshold to unlock (1 for binary)
    int currentCount;           // Current progress toward targetCount
    // ---- State ----
    bool isUnlocked;            // Whether this achievement has been unlocked
    bool isHidden;              // Hidden until unlocked (secret achievements show as "???")
    int unlockTime;             // Unix timestamp via SystemTime.Now() relay (0 = not unlocked)
    String unlockMap;           // level.MapName when unlocked

    // ---- Tracking ----
    name targetClass;           // For auto-tracking (WorldThingDied, etc.)
    int trackingType;           // TRACK_MANUAL, TRACK_KILLS, etc.
    bool isCumulative;          // true = progress persists across maps; false = resets per map

    // ---- Skill Level Filtering (mirrors VUOS pattern) ----
    int minSkillLevel;          // Minimum skill level for this achievement (0-4, default 0 = all skills)
    int maxSkillLevel;          // Maximum skill level for this achievement (0-4, default 4 = all skills)

    // ---- Display ----
    String icon;                // Graphic name (default: "ACHVMT00"). Drawn full-color when unlocked, dimmed when locked (BoA pattern).

    // ---- Cheat Protection ----
    bool cheatProtected;        // If true, invalidated when cheats detected
    bool invalidated;           // Set true if cheats were used during progress

    // ================================================================
    // HELPER METHODS
    // ================================================================

    // Check if this achievement has reached its unlock threshold
    bool HasReachedTarget()
    {
        return currentCount >= targetCount;
    }

    // Get progress as a fraction (0.0 to 1.0) for progress bar display
    double GetProgressFraction()
    {
        if (targetCount <= 0) return 0.0;
        if (currentCount >= targetCount) return 1.0;
        return double(currentCount) / double(targetCount);
    }

    // Check if this achievement is valid for the current skill level (mirrors VUOS)
    bool IsValidForCurrentSkill(int skill = -1)
    {
        if (skill < 0) skill = G_SkillPropertyInt(SKILLP_ACSReturn);
        return (skill >= minSkillLevel && skill <= maxSkillLevel);
    }

}

// ============================================================================
// VUAS_RenderSettings
// Per-frame rendering settings cache. Populated once in RenderOverlay and
// passed to toast/menu/UI drawing methods to avoid redundant CVar lookups.
// Mirrors VUOS_RenderSettings pattern exactly.
//
// Lives in AchievementData.zs because it is a shared data structure used by
// multiple files (Notification, Renderer, Menu). Support classes that are
// only used by one file live in that file instead (e.g. VUAS_NotificationTask
// in AchievementRenderer.zs).
// ============================================================================
class VUAS_RenderSettings
{
    // Toast notification settings
    int toastPosition;          // 0=top-right, 1=top-left, 2=bottom-right, 3=bottom-left, 4=top-center, 5=bottom-center
    int toastStyle;             // 0=procedural, 1=textured
    double toastScale;          // Toast size multiplier
    double toastOpacity;        // Background opacity
    int toastDuration;          // Display time in tics
    int toastAnimation;         // 0=none, 1=slide, 2=fade
    int toastSlideEdge;         // 0=vertical (top/bottom), 1=horizontal (left/right)
    int toastOffsetX;           // X offset (positive = right, negative = left)
    int toastOffsetY;           // Y offset (positive = down, negative = up)
    bool toastEnabled;          // Show/hide toast popups
    bool soundEnabled;          // Play unlock sound

    // Color settings (Font.CR_ indices 0-25)
    int colorUnlocked;          // [UNLOCKED] tag and toast header color
    int colorLocked;            // [LOCKED] tag color
    int colorTitle;             // Achievement title color
    int colorDescription;       // Description text color
    int colorBorder;            // Toast outer border accent color
    int colorBorderInner;       // Toast inner border color
    int colorProgress;          // Progress bar/counter text color

    // Menu settings
    bool showHidden;            // Show hidden achievements in menu (as ???)

    // System settings
    bool debugEnabled;          // Debug output to console

    // Refresh all CVar values in-place (called once per frame from RenderOverlay).
    // Avoids per-frame allocation -- the single VUAS_RenderSettings instance is
    // created once on the renderer and reused every frame.
    void Refresh()
    {
        let p = players[consoleplayer];

        // Toast
        toastEnabled    = VUAS_AchievementHandler.GetCVarBool('ach_toast_enabled', p, true);
        toastPosition   = VUAS_AchievementHandler.GetCVarInt('ach_toast_position', p, 2);
        toastStyle      = VUAS_AchievementHandler.GetCVarInt('ach_toast_style', p, 0);
        toastScale      = VUAS_AchievementHandler.GetCVarFloat('ach_toast_scale', p, 1.0);
        if (toastScale < 0.5) toastScale = 0.5;
        if (toastScale > 2.0) toastScale = 2.0;
        toastOpacity    = VUAS_AchievementHandler.GetCVarFloat('ach_toast_opacity', p, 0.9);
        if (toastOpacity < 0.1) toastOpacity = 0.1;
        if (toastOpacity > 1.0) toastOpacity = 1.0;
        toastDuration   = VUAS_AchievementHandler.GetCVarInt('ach_toast_duration', p, 140);
        if (toastDuration < 35) toastDuration = 35;
        if (toastDuration > 350) toastDuration = 350;
        toastAnimation  = VUAS_AchievementHandler.GetCVarInt('ach_toast_animation', p, 1);
        toastSlideEdge  = VUAS_AchievementHandler.GetCVarInt('ach_toast_slide_edge', p, 0);
        toastOffsetX    = VUAS_AchievementHandler.GetCVarInt('ach_toast_offset_x', p, 0);
        toastOffsetY    = VUAS_AchievementHandler.GetCVarInt('ach_toast_offset_y', p, 0);
        soundEnabled    = VUAS_AchievementHandler.GetCVarBool('ach_sound_enabled', p, true);

        // Colors (Font.CR_ indices)
        colorUnlocked    = VUAS_AchievementHandler.GetCVarInt('ach_color_unlocked', p, 3);      // Green
        colorLocked      = VUAS_AchievementHandler.GetCVarInt('ach_color_locked', p, 20);        // DarkGray
        colorTitle       = VUAS_AchievementHandler.GetCVarInt('ach_color_title', p, 10);         // Yellow
        colorDescription = VUAS_AchievementHandler.GetCVarInt('ach_color_description', p, 2);    // Gray
        colorBorder      = VUAS_AchievementHandler.GetCVarInt('ach_color_border', p, 5);         // Gold
        colorBorderInner = VUAS_AchievementHandler.GetCVarInt('ach_color_border_inner', p, 20);  // Dark Gray
        colorProgress    = VUAS_AchievementHandler.GetCVarInt('ach_color_progress', p, 10);      // Yellow

        // Menu
        showHidden      = VUAS_AchievementHandler.GetCVarBool('ach_show_hidden', p, false);

        // System
        debugEnabled    = VUAS_AchievementHandler.GetCVarBool('vuas_debug', p, false);
    }

    // Convert a Font.CR_ index to a \c escape code string for use in formatted text
    // Maps index 0-25 to \cA through \cZ (VUOS pattern)
    static String GetColorCode(int fontColorIndex)
    {
        if (fontColorIndex < 0) fontColorIndex = 0;
        if (fontColorIndex > 25) fontColorIndex = 25;
        return "\c" .. String.Format("%c", 65 + fontColorIndex);
    }

    // Convert a Font.CR_ index to an RGB hex color for Screen.Dim (toast border, etc.)
    // Matches GZDoom's built-in font color palette
    static int GetColorHex(int fontColorIndex)
    {
        switch (fontColorIndex)
        {
        case 0:  return 0xD03030;   // Brick
        case 1:  return 0xD2BE8A;   // Tan
        case 2:  return 0x808080;   // Gray
        case 3:  return 0x50D050;   // Green
        case 4:  return 0x8B6914;   // Brown
        case 5:  return 0xD4A017;   // Gold
        case 6:  return 0xFF3030;   // Red
        case 7:  return 0x5050FF;   // Blue
        case 8:  return 0xFF8000;   // Orange
        case 9:  return 0xF0F0F0;   // White
        case 10: return 0xFFFF00;   // Yellow
        case 11: return 0xD0D0D0;   // Untranslated
        case 12: return 0x202020;   // Black
        case 13: return 0x90C0FF;   // Light Blue
        case 14: return 0xFFF0C0;   // Cream
        case 15: return 0x808000;   // Olive
        case 16: return 0x308030;   // Dark Green
        case 17: return 0x800000;   // Dark Red
        case 18: return 0x604020;   // Dark Brown
        case 19: return 0x9030D0;   // Purple
        case 20: return 0x505050;   // Dark Gray
        case 21: return 0x50E0E0;   // Cyan
        case 22: return 0xA0D0E0;   // Ice
        case 23: return 0xFF6030;   // Fire
        case 24: return 0x3060FF;   // Sapphire
        case 25: return 0x40A0A0;   // Teal
        default: return 0xD4A017;   // Fallback Gold
        }
    }
}
