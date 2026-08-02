package ansuz

// --- Default Theme ---
// The complete default palette in one place. Every widget takes its colors as
// proc parameters defaulted to these constants, so the theme can be overridden
// per call, or globally by building your own Widget_Color/Color sets on top of
// a different palette.
//
// Naming convention used across all widget parameters:
//   color      — a single plain Color (label text, icon lines)
//   colors     — a Widget_Color five-state palette (interactive widgets)
//   text_color — glyph color on composite widgets
//   bg_color   — flat background fill on containers

// Core neutrals
THEME_TEXT     :: Color{230, 230, 232, 255}
THEME_TEXT_DIM :: Color{160, 162, 168, 255}
THEME_BORDER   :: Color{80, 84, 92, 255}

// Accent — used for slider fill, checked state, focus borders, selection,
// and popup item hover so interactive feedback reads as one family.
THEME_ACCENT       :: Color{86, 148, 226, 255}
THEME_ACCENT_HOVER :: Color{112, 170, 240, 255}
THEME_SELECTION    :: Color{86, 148, 226, 110}

// Popup overlays (dropdown lists, menus)
THEME_POPUP_BG :: Color{40, 43, 50, 248}
THEME_SHADOW   :: Color{0, 0, 0, 80}

// Buttons
THEME_BG_BUTTON        :: Color{60, 63, 70, 255}
THEME_BG_BUTTON_HOVER  :: Color{75, 79, 88, 255}
THEME_BG_BUTTON_ACTIVE :: Color{45, 48, 55, 255}

// Sliders
THEME_SLIDER_TRACK        :: Color{50, 53, 60, 255}
THEME_SLIDER_FILL         :: THEME_ACCENT
THEME_SLIDER_FILL_HOVER   :: THEME_ACCENT_HOVER
THEME_SLIDER_THUMB        :: Color{200, 203, 210, 255}
THEME_SLIDER_THUMB_ACTIVE :: THEME_ACCENT

// Checkboxes
THEME_CHECKBOX_BG         :: Color{50, 53, 60, 255}
THEME_CHECKBOX_BG_HOVER   :: Color{65, 68, 78, 255}
THEME_CHECKBOX_CHECKED    :: THEME_ACCENT
THEME_CHECKBOX_CHECK_MARK :: Color{255, 255, 255, 255}

// Dropdowns
THEME_DROPDOWN_BG         :: Color{55, 58, 65, 255}
THEME_DROPDOWN_BG_HOVER   :: Color{70, 73, 83, 255}
THEME_DROPDOWN_BG_OPEN    :: Color{50, 53, 58, 255}
THEME_DROPDOWN_ITEM_HOVER :: THEME_ACCENT
THEME_DROPDOWN_ARROW      :: Color{180, 180, 185, 255}
THEME_DROPDOWN_POPUP      :: THEME_POPUP_BG

// Menus
THEME_MENU_POPUP      :: THEME_POPUP_BG
THEME_MENU_ITEM_HOVER :: THEME_ACCENT

// Text inputs
THEME_TEXTINPUT_BG           :: Color{35, 38, 45, 255}
THEME_TEXTINPUT_FOCUS_BORDER :: THEME_ACCENT
THEME_TEXTINPUT_CURSOR       :: Color{200, 210, 230, 255}

// Scrollbars
THEME_SCROLLBAR_BG           :: Color{50, 53, 60, 100}
THEME_SCROLLBAR_THUMB        :: Color{120, 123, 130, 180}
THEME_SCROLLBAR_THUMB_HOVER  :: Color{150, 153, 160, 220}
THEME_SCROLLBAR_THUMB_ACTIVE :: Color{180, 183, 190, 255}

// Collapsible headers
THEME_COLLAPSIBLE_BG          :: Color{40, 43, 48, 255}
THEME_COLLAPSIBLE_BG_HOVER    :: Color{49, 55, 60, 255}
THEME_COLLAPSIBLE_BG_PRESS    :: Color{45, 48, 55, 255}
THEME_COLLAPSIBLE_BG_EXPANDED :: Color{49, 55, 60, 255}

// Tree rows
THEME_TREE_ROW_HOVER    :: Color{60, 63, 70, 255}
THEME_TREE_ROW_PRESS    :: Color{45, 48, 55, 255}
THEME_TREE_ROW_SELECTED :: Color{55, 80, 120, 255}
THEME_TREE_GUIDE        :: Color{80, 84, 92, 255}

// Fade applied to text and detail colors of disabled widgets.
DISABLED_FADE :: f32(0.55)

// Fade a color toward transparency for disabled widget rendering.
// Alpha-based so it works over any background without knowing it.
disabled_color :: proc(c: Color, fade: f32 = DISABLED_FADE) -> Color {
	return Color{c.r, c.g, c.b, u8(f32(c.a) * (1 - fade))}
}
