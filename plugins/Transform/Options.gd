extends HBoxContainer


var _settings := preload("./TransformSettings.tres")

func _ready() -> void:
	_settings.changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	$ViewAxis.set_pressed_no_signal(_settings.view_axis)
	$Snap.visible = _settings.tool == _settings.Tools.ROTATE
	$Snap.set_pressed_no_signal(_settings.snap)
	$Uniform.visible = _settings.tool == _settings.Tools.SCALE
	$Uniform.set_pressed_no_signal(_settings.uniform)
	$Commit.disabled = not _settings.transforming
	$Cancel.disabled = not _settings.transforming


func _on_view_axis_toggled(toggled_on: bool) -> void:
	_settings.view_axis = toggled_on


func _on_snap_toggled(toggled_on: bool) -> void:
	_settings.snap = toggled_on


func _on_uniform_toggled(toggled_on: bool) -> void:
	_settings.uniform = toggled_on


func _on_commit_pressed() -> void:
	_settings.commit()


func _on_cancel_pressed() -> void:
	_settings.cancel()
