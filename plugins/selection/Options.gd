extends HBoxContainer

## The selection option bar.
##
## It edits the selection mode and the selection options. It also clears the
## selection. The visible options follow the active selection tool.

var _settings := preload("./SelectionSettings.tres")

func _enter_tree() -> void:
	if not _settings.changed.is_connected(_sync):
		_settings.changed.connect(_sync)
	if not State.activity_changed.is_connected(_sync):
		State.activity_changed.connect(_sync)
	if not State.edit_state_changed.is_connected(_sync):
		State.edit_state_changed.connect(_sync)
	# A stored mode can change while the options are hidden. Show it again on
	# the next entry; `_ready` runs only once.
	_sync()


func _exit_tree() -> void:
	if _settings.changed.is_connected(_sync):
		_settings.changed.disconnect(_sync)
	if State.activity_changed.is_connected(_sync):
		State.activity_changed.disconnect(_sync)
	if State.edit_state_changed.is_connected(_sync):
		State.edit_state_changed.disconnect(_sync)


func _ready() -> void:
	_sync()


func _sync() -> void:
	$Clear.disabled = State.edit_busy()
	var mode_buttons := [$Replace, $Add, $Subtract]
	mode_buttons[_settings.mode].button_pressed = true
	$Connected.set_pressed_no_signal(_settings.connected)
	$Connected.visible = _settings.tool == _settings.Tools.WAND
	$Sep.visible = $Connected.visible
	$Empty.set_pressed_no_signal(_settings.include_empty)
	# The wand picks a voxel. It has no empty cell option.
	var show_empty := _settings.tool != _settings.Tools.WAND
	for control in [$EmptySep, $Empty]:
		control.visible = show_empty
	$Depth.set_pressed_no_signal(_settings.depth_test)
	# The depth test reads the screen shape. The wand picks a voxel.
	$Depth.visible = show_empty


func _on_depth_toggled(toggled_on: bool) -> void:
	_settings.depth_test = toggled_on


func _on_empty_toggled(toggled_on: bool) -> void:
	_settings.include_empty = toggled_on


func _on_connected_toggled(toggled_on: bool) -> void:
	_settings.connected = toggled_on


func _on_clear_pressed() -> void:
	# A running selection job restores its result after this call. Refuse the
	# clear instead of letting the job overwrite it.
	if State.edit_busy():
		return
	State.clear_selection()


func _on_replace_toggled(toggled_on: bool) -> void:
	if toggled_on:
		_settings.mode = _settings.SelectMode.REPLACE


func _on_add_toggled(toggled_on: bool) -> void:
	if toggled_on:
		_settings.mode = _settings.SelectMode.ADD


func _on_subtract_toggled(toggled_on: bool) -> void:
	if toggled_on:
		_settings.mode = _settings.SelectMode.SUBTRACT
