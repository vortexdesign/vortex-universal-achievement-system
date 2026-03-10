// AchievementNotification.zs
// Static UI class for drawing toast notifications.
//
// Pattern: Stupid Achievements sa_NoAnimationTask.draw() for layout math
//          VUOS ObjectiveRenderer.RenderCompletionMessage() for Screen.DrawText + virtual coords
//          BoA achievements.zs for icon drawing with DTA_FillColor dim effect
//
// All methods are ui static - called from VUAS_AchievementRenderer.RenderOverlay()
// Drawing uses virtual coordinates (640x480 base, scaled via DTA_VirtualWidth/Height) for resolution independence.

class VUAS_AchievementNotification ui
{
    // Layout constants (in virtual coordinate space)
    const TOAST_PADDING = 10;       // Internal padding around text
    const TOAST_MARGIN = 12;        // Margin from screen edges
    const TOAST_ICON_SIZE = 32;     // Icon size (square)
    const TOAST_ICON_GAP = 8;       // Gap between icon and text
    const TOAST_BORDER = 2;         // Border thickness
    const TOAST_MIN_WIDTH = 180;    // Minimum toast width
    const TOAST_TEXT_GAP = 2;       // Gap between title and description

    // Colors (background is fixed; both borders use CVars)
    const COLOR_BG = 0x000000;          // Background fill

    // ====================================================================
    // DRAW TOAST - Main entry point called from renderer
    // ====================================================================
    static void DrawToast(
        VUAS_NotificationTask task,
        int levelTime,
        double fracTic,
        VUAS_RenderSettings rs,
        int virtualW,
        int virtualH)
    {
        if (!task) return;

        Font fnt = SmallFont;
        int elapsed = task.GetElapsed(levelTime);

        // --- Calculate text dimensions ---
        String titleText = StringTable.Localize(task.achievementTitle, false);
        String descText = StringTable.Localize(task.achievementDesc, false);
        String header = "Achievement Unlocked";

        int headerWidth = fnt.StringWidth(header);
        int titleWidth = fnt.StringWidth(titleText);
        int descWidth = fnt.StringWidth(descText);
        int lineH = fnt.GetHeight();

        // Text block width = widest of header/title/description
        int textBlockWidth = headerWidth;
        if (titleWidth > textBlockWidth) textBlockWidth = titleWidth;
        if (descWidth > textBlockWidth) textBlockWidth = descWidth;

        // --- Calculate toast box dimensions ---
        // Layout: [border][padding][icon][gap][text][padding][border]
        bool hasIcon = (task.iconName.Length() > 0);
        TextureID iconTex;
        if (hasIcon)
        {
            iconTex = TexMan.CheckForTexture(task.iconName, TexMan.Type_Any);
            if (!iconTex.IsValid()) hasIcon = false;
        }

        int iconSpace = hasIcon ? (TOAST_ICON_SIZE + TOAST_ICON_GAP) : 0;
        int contentWidth = iconSpace + textBlockWidth;
        if (contentWidth < TOAST_MIN_WIDTH) contentWidth = TOAST_MIN_WIDTH;

        int boxWidth = int((TOAST_BORDER + TOAST_PADDING + contentWidth + TOAST_PADDING + TOAST_BORDER) * rs.toastScale);
        int boxHeight = int((TOAST_BORDER + TOAST_PADDING + lineH + TOAST_TEXT_GAP + lineH + TOAST_TEXT_GAP + lineH + TOAST_PADDING + TOAST_BORDER) * rs.toastScale);

        // --- Calculate position based on CVar ---
        int baseX, baseY;
        [baseX, baseY] = GetBasePosition(rs.toastPosition, boxWidth, boxHeight, virtualW, virtualH);

        // --- Apply user X/Y offset (VUOS pattern) ---
        baseX += rs.toastOffsetX;
        baseY += rs.toastOffsetY;

        // --- Apply animation offset ---
        double alpha = rs.toastOpacity;
        int drawX = baseX;
        int drawY = baseY;

        if (task.animType == 1) // slide
        {
            // Slide axis determined by ach_toast_slide_edge CVar:
            // 0 = vertical (slide from top/bottom edge based on position)
            // 1 = horizontal (slide from left/right edge based on position)
            if (rs.toastSlideEdge == 1) // horizontal
            {
                int offscreenX = GetSlideHorizontalStart(rs.toastPosition, boxWidth, virtualW);

                if (task.IsAnimatingIn(elapsed))
                {
                    double frac = task.GetFractionIn(elapsed, fracTic);
                    frac = SmoothStep(frac);
                    drawX = Lerp(offscreenX, baseX, frac);
                }
                else if (task.IsAnimatingOut(elapsed))
                {
                    double frac = task.GetFractionOut(elapsed, fracTic);
                    frac = SmoothStep(frac);
                    drawX = Lerp(baseX, offscreenX, frac);
                }
            }
            else // vertical (default)
            {
                int offscreenY = GetSlideVerticalStart(rs.toastPosition, boxHeight, virtualH);

                if (task.IsAnimatingIn(elapsed))
                {
                    double frac = task.GetFractionIn(elapsed, fracTic);
                    frac = SmoothStep(frac);
                    drawY = Lerp(offscreenY, baseY, frac);
                }
                else if (task.IsAnimatingOut(elapsed))
                {
                    double frac = task.GetFractionOut(elapsed, fracTic);
                    frac = SmoothStep(frac);
                    drawY = Lerp(baseY, offscreenY, frac);
                }
            }
        }
        else if (task.animType == 2) // fade
        {
            if (task.IsAnimatingIn(elapsed))
            {
                double frac = task.GetFractionIn(elapsed, fracTic);
                alpha = rs.toastOpacity * frac;
            }
            else if (task.IsAnimatingOut(elapsed))
            {
                double frac = task.GetFractionOut(elapsed, fracTic);
                alpha = rs.toastOpacity * (1.0 - frac);
            }
        }
        // animType 0 = no animation, use base position and full alpha

        // --- Draw the toast ---
        DrawToastBox(drawX, drawY, boxWidth, boxHeight, alpha, rs, virtualW, virtualH);

        // --- Draw content (icon + text) ---
        int scaledBorder = int(TOAST_BORDER * rs.toastScale);
        int scaledPadding = int(TOAST_PADDING * rs.toastScale);
        int scaledIconSize = int(TOAST_ICON_SIZE * rs.toastScale);
        int scaledIconGap = int(TOAST_ICON_GAP * rs.toastScale);
        int scaledTextGap = int(TOAST_TEXT_GAP * rs.toastScale);

        int contentX = drawX + scaledBorder + scaledPadding;
        int contentY = drawY + scaledBorder + scaledPadding;

        // Draw icon
        if (hasIcon)
        {
            Screen.DrawTexture(iconTex, false,
                contentX, contentY,
                DTA_VirtualWidth, virtualW,
                DTA_VirtualHeight, virtualH,
                DTA_KeepRatio, true,
                DTA_DestWidth, scaledIconSize,
                DTA_DestHeight, scaledIconSize,
                DTA_Alpha, alpha);

            contentX += scaledIconSize + scaledIconGap;
        }

        // Draw header ("Achievement Unlocked") - uses unlocked color
        Screen.DrawText(fnt, rs.colorUnlocked, contentX, contentY, header,
            DTA_VirtualWidth, virtualW,
            DTA_VirtualHeight, virtualH,
            DTA_KeepRatio, true,
            DTA_Alpha, alpha);

        // Draw title - uses title color
        Screen.DrawText(fnt, rs.colorTitle, contentX, contentY + lineH + scaledTextGap, titleText,
            DTA_VirtualWidth, virtualW,
            DTA_VirtualHeight, virtualH,
            DTA_KeepRatio, true,
            DTA_Alpha, alpha);

        // Draw description - uses description color
        Screen.DrawText(fnt, rs.colorDescription, contentX, contentY + (lineH + scaledTextGap) * 2, descText,
            DTA_VirtualWidth, virtualW,
            DTA_VirtualHeight, virtualH,
            DTA_KeepRatio, true,
            DTA_Alpha, alpha);
    }

    // ====================================================================
    // DRAW TOAST BOX - background + border
    // Style 0 (procedural): Screen.Dim layers for outer border, inner border, fill
    // Style 1 (textured): Draws ach_bkg.png stretched to toast dimensions
    // ====================================================================
    static void DrawToastBox(
        int x, int y, int w, int h,
        double alpha,
        VUAS_RenderSettings rs,
        int virtualW, int virtualH)
    {
        if (rs.toastStyle == 1)
        {
            // Textured style: draw ach_bkg.png expanded to include extra padding
            // The texture itself acts as the background, so we expand the draw area
            // outward to give the content the same visual spacing as procedural style
            TextureID bgTex = TexMan.CheckForTexture("ach_bkg", TexMan.Type_Any);
            if (bgTex.IsValid())
            {
                int expandV = int(TOAST_BORDER * rs.toastScale);
                int expandH = int(TOAST_BORDER * 2.5 * rs.toastScale);
                Screen.DrawTexture(bgTex, false, x - expandH, y - expandV,
                    DTA_VirtualWidth, virtualW,
                    DTA_VirtualHeight, virtualH,
                    DTA_KeepRatio, true,
                    DTA_DestWidth, w + expandH * 2,
                    DTA_DestHeight, h + expandV * 2,
                    DTA_Alpha, alpha);
                return;
            }
            // Fall through to procedural if texture not found
        }

        // Procedural style (default)
        int scaledBorder = int(TOAST_BORDER * rs.toastScale);

        // Convert virtual coords to screen coords for Screen.Dim
        // Screen.Dim uses actual screen pixels, not virtual coords
        double scaleX = double(Screen.GetWidth()) / virtualW;
        double scaleY = double(Screen.GetHeight()) / virtualH;

        int screenX = int(x * scaleX);
        int screenY = int(y * scaleY);
        int screenW = int(w * scaleX);
        int screenH = int(h * scaleY);
        int screenBorder = int(scaledBorder * scaleX);

        // Draw accent border (outer) - uses border color from settings
        int accentColor = VUAS_RenderSettings.GetColorHex(rs.colorBorder);
        Screen.Dim(accentColor, alpha * 0.8, screenX, screenY, screenW, screenH);

        // Draw inner border - uses inner border color from settings
        int innerColor = VUAS_RenderSettings.GetColorHex(rs.colorBorderInner);
        Screen.Dim(innerColor, alpha * 0.9,
            screenX + screenBorder, screenY + screenBorder,
            screenW - screenBorder * 2, screenH - screenBorder * 2);

        // Draw background fill
        Screen.Dim(COLOR_BG, alpha,
            screenX + screenBorder * 2, screenY + screenBorder * 2,
            screenW - screenBorder * 4, screenH - screenBorder * 4);
    }

    // ====================================================================
    // POSITION HELPERS
    // ====================================================================

    // Get the base (final resting) position for the toast
    // 0=top-right, 1=top-left, 2=bottom-right, 3=bottom-left, 4=top-center, 5=bottom-center
    static int, int GetBasePosition(int position, int boxW, int boxH, int virtualW, int virtualH)
    {
        int x, y;

        switch (position)
        {
        case 0: // top-right
            x = virtualW - boxW - TOAST_MARGIN;
            y = TOAST_MARGIN;
            break;
        case 1: // top-left
            x = TOAST_MARGIN;
            y = TOAST_MARGIN;
            break;
        case 2: // bottom-right
            x = virtualW - boxW - TOAST_MARGIN;
            y = virtualH - boxH - TOAST_MARGIN;
            break;
        case 3: // bottom-left
            x = TOAST_MARGIN;
            y = virtualH - boxH - TOAST_MARGIN;
            break;
        case 4: // top-center
            x = (virtualW - boxW) / 2;
            y = TOAST_MARGIN;
            break;
        case 5: // bottom-center
            x = (virtualW - boxW) / 2;
            y = virtualH - boxH - TOAST_MARGIN;
            break;
        default: // fallback = bottom-right
            x = virtualW - boxW - TOAST_MARGIN;
            y = virtualH - boxH - TOAST_MARGIN;
            break;
        }

        return x, y;
    }

    // Get the offscreen X position for horizontal slide animation
    static int GetSlideHorizontalStart(int position, int boxW, int virtualW)
    {
        // Slide in from the nearest horizontal edge
        switch (position)
        {
        case 0: case 2: // right-side positions: slide in from right
            return virtualW + 10;
        case 1: case 3: // left-side positions: slide in from left
            return -boxW - 10;
        case 4: case 5: // center positions: slide in from right
            return virtualW + 10;
        default:
            return virtualW + 10;
        }
    }

    // Get the offscreen Y position for vertical slide animation
    static int GetSlideVerticalStart(int position, int boxH, int virtualH)
    {
        // Slide in from the nearest vertical edge
        switch (position)
        {
        case 0: case 1: case 4: // top positions: slide down from above
            return -boxH - 10;
        case 2: case 3: case 5: // bottom positions: slide up from below
            return virtualH + 10;
        default:
            return -boxH - 10;
        }
    }

    // ====================================================================
    // MATH HELPERS
    // ====================================================================

    // Linear interpolation between two integer values
    static int Lerp(int a, int b, double t)
    {
        return int(round(a * (1.0 - t) + b * t));
    }

    // Smooth step for nicer animation easing (cubic Hermite)
    static double SmoothStep(double t)
    {
        if (t <= 0) return 0;
        if (t >= 1.0) return 1.0;
        return t * t * (3.0 - 2.0 * t);
    }
}
