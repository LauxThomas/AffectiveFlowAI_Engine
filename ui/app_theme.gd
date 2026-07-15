# Project-wide visual identity, applied without any custom art assets -
# see the visual identity reference linked from docs/TECHNICAL_BRIEF.md.
# Colors are pulled straight from what already exists in the codebase:
# AffectiveTypes.STATE_COLOR for the three cognitive states, and the gold
# already used for coins/lane edges/obstacle warning stripes as the one
# accent. This gets the game most of the way to "looks considered" without
# needing a 2D artist - actual sprite art, icons, and custom fonts are
# still a real design-pass gap this can't close.
extends RefCounted
class_name AppTheme

const INK := Color("121319")
const INK_2 := Color("1b1d26")
const INK_3 := Color("2a2d3a")
const PAPER := Color("eceef1")
const GOLD := Color("f0c419")
const GOLD_INK := Color("4a3900")

static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = 18

	_style_panel(theme)
	_style_button(theme)
	_style_primary_button(theme)
	_style_progress_bar(theme)
	_style_misc(theme)

	return theme

static func _style_panel(theme: Theme) -> void:
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(INK_2, 0.96)
	panel_style.border_color = INK_3
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.set_content_margin_all(14.0)
	theme.set_stylebox("panel", "PanelContainer", panel_style)

static func _style_button(theme: Theme) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = INK_3
	normal.border_color = Color(PAPER, 0.16)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(10.0)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.border_color = GOLD

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = INK

	var disabled := normal.duplicate() as StyleBoxFlat
	disabled.bg_color = Color(INK_3, 0.5)
	disabled.border_color = Color(PAPER, 0.08)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("focus", "Button", hover)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_color("font_color", "Button", PAPER)
	theme.set_color("font_hover_color", "Button", GOLD)
	theme.set_color("font_pressed_color", "Button", GOLD)
	theme.set_color("font_disabled_color", "Button", Color(PAPER, 0.4))

static func _style_primary_button(theme: Theme) -> void:
	theme.set_type_variation("PrimaryButton", "Button")

	var normal := StyleBoxFlat.new()
	normal.bg_color = GOLD
	normal.set_corner_radius_all(4)
	normal.set_content_margin_all(10.0)

	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = GOLD.lightened(0.15)

	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = GOLD.darkened(0.15)

	theme.set_stylebox("normal", "PrimaryButton", normal)
	theme.set_stylebox("hover", "PrimaryButton", hover)
	theme.set_stylebox("pressed", "PrimaryButton", pressed)
	theme.set_stylebox("focus", "PrimaryButton", hover)
	theme.set_color("font_color", "PrimaryButton", GOLD_INK)
	theme.set_color("font_hover_color", "PrimaryButton", GOLD_INK)
	theme.set_color("font_pressed_color", "PrimaryButton", GOLD_INK)

static func _style_progress_bar(theme: Theme) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = INK
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = GOLD
	fill.set_corner_radius_all(3)
	theme.set_stylebox("background", "ProgressBar", bg)
	theme.set_stylebox("fill", "ProgressBar", fill)

static func _style_misc(theme: Theme) -> void:
	theme.set_color("font_color", "Label", PAPER)
	theme.set_color("font_color", "CheckBox", PAPER)
	theme.set_color("font_color", "RichTextLabel", PAPER)
	theme.set_color("default_color", "RichTextLabel", PAPER)
	theme.set_color("font_color", "LineEdit", PAPER)
	theme.set_color("font_color", "SpinBox", PAPER)
	theme.set_color("separator", "HSeparator", Color(PAPER, 0.12))
	theme.set_constant("separation", "HSeparator", 12)

	var line_edit_normal := StyleBoxFlat.new()
	line_edit_normal.bg_color = INK
	line_edit_normal.border_color = Color(PAPER, 0.18)
	line_edit_normal.set_border_width_all(1)
	line_edit_normal.set_corner_radius_all(3)
	line_edit_normal.set_content_margin_all(8.0)
	theme.set_stylebox("normal", "LineEdit", line_edit_normal)
