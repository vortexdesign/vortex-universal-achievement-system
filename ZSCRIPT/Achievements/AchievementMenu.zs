// AchievementMenu.zs
// Custom OptionMenu for browsing achievements.
//
// Pattern: Stupid Achievements sa_AchievementList : OptionMenu
// - Override Init() to dynamically populate items from achievement registry
// - Custom OptionMenuItem subclass (OptionMenuItemCommand) for achievement rows
// - Item handles all rendering (text + icon) in its own Draw() override
// - Built-in keyboard nav, mouse support, and scroll from OptionMenu base
//
// Opened via: openmenu "VUASAchievementBrowse" (KEYCONF alias or console)

// ============================================================================
// VUAS_AchievementBrowseMenu : OptionMenu
// Main browsable achievement list. Dynamically populated on open.
// ============================================================================
class VUAS_AchievementBrowseMenu : OptionMenu
{
    // Lowercase ASCII code of the key that toggles this menu.
    // Resolved in Init() by converting the bound scancode to ASCII via QWERTY map.
    int toggleAsciiCode;

    // Convert a keyboard scancode (used by Bindings) to a lowercase ASCII code
    // (used by OnUIEvent.KeyChar). QWERTY layout mapping.
    private static int ScancodeToAscii(int sc)
    {
        // Number row: scancodes 2-11
        if (sc >= 2 && sc <= 10) return sc + 47; // 2+47=49='1' ... 10+47=57='9'
        if (sc == 11) return 48; // '0'

        // Top letter row: scancodes 16-25 = qwertyuiop
        String row1 = "qwertyuiop";
        if (sc >= 16 && sc <= 25) return row1.ByteAt(sc - 16);

        // Home row: scancodes 30-38 = asdfghjkl
        String row2 = "asdfghjkl";
        if (sc >= 30 && sc <= 38) return row2.ByteAt(sc - 30);

        // Bottom row: scancodes 44-50 = zxcvbnm
        String row3 = "zxcvbnm";
        if (sc >= 44 && sc <= 50) return row3.ByteAt(sc - 44);

        if (sc == 57) return 32; // space
        return -1;
    }

    // Toggle support: pressing the same key that opened the menu closes it.
    // Bindings uses keyboard scancodes (e.g. 50=M) but OnUIEvent.KeyChar gives
    // ASCII codes (e.g. 77='M'). Init() bridges the gap by converting the bound
    // scancode to ASCII once, so OnUIEvent just does a simple int comparison.
    override bool OnUIEvent(UIEvent ev)
    {
        if (ev.Type == UIEvent.Type_KeyDown && toggleAsciiCode >= 0)
        {
            int keyCode = ev.KeyChar;
            if (keyCode >= 65 && keyCode <= 90)
                keyCode += 32;

            if (keyCode == toggleAsciiCode)
            {
                Close();
                return true;
            }
        }
        return Super.OnUIEvent(ev);
    }

    override void Init(Menu parent, OptionMenuDescriptor desc)
    {
        Super.Init(parent, desc);

        // Find the scancode bound to our toggle command, convert to ASCII.
        // GetKeysForCommand returns up to 2 scancodes (primary + secondary bind).
        toggleAsciiCode = -1;
        int k1, k2;
        [k1, k2] = Bindings.GetKeysForCommand("ach_open_menu");
        if (k1 > 0)
            toggleAsciiCode = ScancodeToAscii(k1);

        // Clear any existing items (menu re-opens should refresh)
        mDesc.mItems.Clear();

        let handler = VUAS_AchievementHandler.GetHandler();
        if (!handler || handler.achievements.Size() == 0)
        {
            mDesc.mItems.Push(new("OptionMenuItemStaticText").Init("No achievements defined.", 0));
            return;
        }

        // Read settings
        bool showHidden = VUAS_AchievementHandler.GetCVarBool('ach_show_hidden', players[consoleplayer], false);
        int menuFilter = VUAS_AchievementHandler.GetCVarInt('ach_menu_filter', players[consoleplayer], 0);

        // Count totals for header
        int totalCount = handler.achievements.Size();
        int unlockedCount = 0;
        for (int i = 0; i < totalCount; i++)
        {
            if (handler.achievements[i].isUnlocked)
                unlockedCount++;
        }

        // Header with summary
        String filterLabel = "";
        if (menuFilter == 1) filterLabel = " (Unlocked Only)";
        else if (menuFilter == 2) filterLabel = " (Locked Only)";
        String header = String.Format("Achievements: %d / %d%s", unlockedCount, totalCount, filterLabel);
        mDesc.mItems.Push(new("OptionMenuItemStaticText").Init(header, 0));
        mDesc.mItems.Push(new("OptionMenuItemStaticText").Init("", 0));

        // Collect unique categories
        Array<String> categories;
        for (int i = 0; i < totalCount; i++)
        {
            let ach = handler.achievements[i];
            bool found = false;
            for (int c = 0; c < categories.Size(); c++)
            {
                if (categories[c] ~== ach.category)
                {
                    found = true;
                    break;
                }
            }
            if (!found)
                categories.Push(ach.category);
        }

        // Display achievements grouped by category
        for (int c = 0; c < categories.Size(); c++)
        {
            String cat = categories[c];

            // Category header
            String catHeader = "";
            for (int ch = 0; ch < cat.Length(); ch++)
            {
                int byte = cat.ByteAt(ch);
                // Uppercase first letter
                if (ch == 0 && byte >= 97 && byte <= 122)
                    catHeader.AppendFormat("%c", byte - 32);
                else
                    catHeader.AppendFormat("%c", byte);
            }

            mDesc.mItems.Push(new("OptionMenuItemStaticText").Init("", 0));
            mDesc.mItems.Push(new("OptionMenuItemStaticText").Init(String.Format("--- %s ---", catHeader), 1));

            // Add achievements in this category
            for (int i = 0; i < totalCount; i++)
            {
                let ach = handler.achievements[i];
                if (!(ach.category ~== cat)) continue;

                // Hidden achievement handling
                if (ach.isHidden && !ach.isUnlocked && !showHidden)
                    continue;

                // Filter: 0=All, 1=Unlocked Only, 2=Locked Only
                if (menuFilter == 1 && !ach.isUnlocked) continue;
                if (menuFilter == 2 && ach.isUnlocked) continue;

                let item = new("VUAS_AchievementMenuItem");
                item.InitAchievement(ach, i);
                mDesc.mItems.Push(item);
            }
        }

        // Footer
        mDesc.mItems.Push(new("OptionMenuItemStaticText").Init("", 0));

        mDesc.mScrollPos = 0;
        mDesc.mSelectedItem = mDesc.mItems.Size() > 0 ? 0 : -1;
        mDesc.CalcIndent();
    }
}

// ============================================================================
// VUAS_AchievementMenuItem : OptionMenuItemCommand
// Custom menu item displaying a single achievement row with icon.
// Extends OptionMenuItemCommand (not StaticText) so Draw() fully supports
// Screen.DrawTexture for icon rendering. Pattern from Stupid Achievements
// sa_AchievementItem (StupidAchievements.zs line 908).
//
// Text rendered via inherited drawLabel() (correct menu font + scaling).
// Icon drawn manually with BoA dim pattern (DTA_AlphaChannel + DTA_FillColor).
// Display text stored in mLabel; mCentered=true for centered layout.
// Icon positioned to the left of centered text using NewSmallFont width
// (the actual option menu font that drawLabel uses internally).
// ============================================================================
class VUAS_AchievementMenuItem : OptionMenuItemCommand
{
    int achIndex;
    bool achUnlocked;
    bool achHidden;
    TextureID achIconTex;   // Cached icon texture (looked up once in Init)

    void InitAchievement(VUAS_AchievementData ach, int index)
    {
        String achTitle = StringTable.Localize(ach.title, false);
        String achDesc = StringTable.Localize(ach.description, false);
        achIndex = index;
        achUnlocked = ach.isUnlocked;
        achHidden = ach.isHidden;

        // Cache icon texture (avoid repeated TexMan lookups in Draw)
        achIconTex = TexMan.CheckForTexture(ach.icon, TexMan.Type_Any);

        // Read color settings from CVars
        let p = players[consoleplayer];
        String ccUnlocked = VUAS_RenderSettings.GetColorCode(
            VUAS_AchievementHandler.GetCVarInt('ach_color_unlocked', p, 3));
        String ccLocked = VUAS_RenderSettings.GetColorCode(
            VUAS_AchievementHandler.GetCVarInt('ach_color_locked', p, 20));
        String ccTitle = VUAS_RenderSettings.GetColorCode(
            VUAS_AchievementHandler.GetCVarInt('ach_color_title', p, 10));
        String ccDesc = VUAS_RenderSettings.GetColorCode(
            VUAS_AchievementHandler.GetCVarInt('ach_color_description', p, 2));
        String ccProgress = VUAS_RenderSettings.GetColorCode(
            VUAS_AchievementHandler.GetCVarInt('ach_color_progress', p, 10));

        // Build the display text
        String displayText;
        if (achHidden && !achUnlocked)
        {
            displayText = String.Format("%s??? - Hidden Achievement\c-", ccLocked);
        }
        else if (achUnlocked)
        {
            String timeStr = "";
            if (ach.unlockTime > 0)
                timeStr = String.Format(" (%s)", SystemTime.Format("%d %b %Y", ach.unlockTime));

            displayText = String.Format("%s[UNLOCKED]\c- %s%s\c- - %s%s\c-%s",
                ccUnlocked, ccTitle, achTitle, ccDesc, achDesc, timeStr);
        }
        else
        {
            String progressStr = "";
            if (ach.targetCount > 1)
                progressStr = String.Format(" %s[%d/%d]\c-", ccProgress, ach.currentCount, ach.targetCount);

            displayText = String.Format("%s[LOCKED]\c- %s%s\c- - %s%s\c-%s",
                ccLocked, ccTitle, achTitle, ccDesc, achDesc, progressStr);
        }

        // Store display text as mLabel so drawLabel() renders it.
        // Empty command = no action on select.
        Super.Init(displayText, "");
        mCentered = true;  // Centered layout (inherited OptionMenu default)
    }

    // Non-selectable (display-only, matches previous StaticText behavior)
    override bool Selectable() { return false; }

    override int Draw(OptionMenuDescriptor desc, int y, int indent, bool selected)
    {
        // ---- Layout: centered text with icon to its left ----
        int lineHeight = SmallFont.GetHeight() * CleanYfac_1;
        int iconSize = lineHeight * 2;

        // ---- Text (centered via drawLabel with mCentered=true) ----
        drawLabel(indent, y, Font.CR_UNTRANSLATED);

        // ---- Icon positioning ----
        // drawLabel uses NewSmallFont (the option menu font), not SmallFont.
        // Using the same font for width calculation gives consistent gap.
        Font optFont = NewSmallFont;
        int textWidth = optFont.StringWidth(mLabel) * CleanXfac_1;
        int textX = (Screen.GetWidth() - textWidth) / 2;
        int iconX = textX - iconSize - 12;

        // Skip icon for hidden locked achievements (consistent with ??? display)
        if (!(achHidden && !achUnlocked) && achIconTex.IsValid())
        {
            if (achUnlocked)
            {
                // Full color for unlocked
                Screen.DrawTexture(achIconTex, true, iconX, y,
                    DTA_DestWidth, iconSize,
                    DTA_DestHeight, iconSize);
            }
            else
            {
                // Gray dim for locked (BoA pattern: DTA_AlphaChannel + DTA_FillColor)
                Screen.DrawTexture(achIconTex, true, iconX, y,
                    DTA_DestWidth, iconSize,
                    DTA_DestHeight, iconSize,
                    DTA_AlphaChannel, true,
                    DTA_FillColor, 0xBBBBCC);
            }
        }

        return -1;
    }
}
