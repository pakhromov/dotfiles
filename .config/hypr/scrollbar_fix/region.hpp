#pragma once

#include <cmath>

namespace ScrollbarFix {
struct Rule {
    int scrollbarWidth = 0;
    int gapTop = 0;
    int gapBottom = 0;
    int gapsFullscreen = 0;
};

// Coordinates are window-local logical pixels. Right and bottom are exclusive,
// as they are for the window's own rectangle. Oversized gaps leave no strip.
inline bool contains(const Rule& rule, double x, double y, double width, double height, bool fullscreen = false) {
    const int top = fullscreen ? rule.gapsFullscreen : rule.gapTop;
    const int bottom = fullscreen ? rule.gapsFullscreen : rule.gapBottom;
    return rule.scrollbarWidth > 0 && top >= 0 && bottom >= 0 &&
           std::isfinite(x) && std::isfinite(y) && std::isfinite(width) && std::isfinite(height) &&
           width > 0 && height > 0 && x >= 0 && x < width && y >= 0 && y < height &&
           x >= width - rule.scrollbarWidth && y >= top && y < height - bottom;
}
}
