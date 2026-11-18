extends "res://plugins/brush/StrokeTool.gd"


var _brush_settings: BrushToolSettings


func _init() -> void:
	_brush_settings = preload("./BrushSettings.tres")
	_settings = _brush_settings


func _pick_adds() -> bool:
	return _brush_settings.mode != _brush_settings.BrushMode.ERASER


func _erases() -> bool:
	return _brush_settings.mode == _brush_settings.BrushMode.ERASER
