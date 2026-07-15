# Autoload "ThemeBootstrap". Applies the project-wide Theme (see
# ui/app_theme.gd) to the root window so every scene picks it up
# automatically - no per-scene theme wiring needed. Runs before the main
# scene's _ready() since all autoloads initialize first.
extends Node

func _ready() -> void:
	get_tree().root.theme = AppTheme.build()
