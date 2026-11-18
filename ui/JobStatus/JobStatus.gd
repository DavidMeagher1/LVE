class_name JobStatus
extends HBoxContainer


const CANCEL_TOOLTIP := "Cancel operation"
const CANCELLING_TOOLTIP := "Cancelling…"
const MIN_CONTENT_WIDTH := 24.0
const MAX_CONTENT_WIDTH := 320.0
const CONTENT_SLACK := 4.0
const MIN_ROW_HEIGHT := 20.0

var delay_ms := 200

var _operation: State.Operation = null
var _pressed_id := 0
var _ready_done := false

@onready var _job: Control = $Job
@onready var _label: Label = $Job/ActivityLabel
@onready var _progress: ProgressBar = $Job/ActivityProgress
@onready var _cancel: Button = $Cancel
@onready var _delay: Timer = $Delay


func _ready() -> void:
	_cancel.tooltip_text = CANCEL_TOOLTIP
	_cancel.accessibility_name = CANCEL_TOOLTIP
	_cancel.button_down.connect(_on_cancel_button_down)
	_cancel.pressed.connect(_on_cancel_pressed)
	_delay.timeout.connect(_refresh_from_state)
	_ready_done = true
	_refresh_from_state()


func _notification(what: int) -> void:
	if what == NOTIFICATION_POST_ENTER_TREE:
		if not State.activity_changed.is_connected(_refresh_from_state):
			State.activity_changed.connect(_refresh_from_state)
		if _ready_done:
			_refresh_from_state()
	elif what == NOTIFICATION_EXIT_TREE:
		if State.activity_changed.is_connected(_refresh_from_state):
			State.activity_changed.disconnect(_refresh_from_state)


func _refresh_from_state() -> void:
	if not _ready_done:
		return
	_operation = State.get_activity()
	if _operation == null:
		_delay.stop()
		visible = false
		return
	var elapsed := State.activity_elapsed_ms()
	if elapsed >= delay_ms:
		_delay.stop()
		visible = true
	else:
		visible = false
		if _delay.is_stopped():
			_delay.start(maxf(0.001, (delay_ms - elapsed) / 1000.0))
	_refresh()


func _refresh() -> void:
	var operation := _operation
	if operation == null:
		return
	_progress.indeterminate = operation.total <= 0
	var text := operation.label
	if operation.cancel_requested:
		text = CANCELLING_TOOLTIP
	elif operation.total > 0:
		var percent := clampf(operation.completed * 100.0 / operation.total, 0.0, 100.0)
		_progress.value = percent
		text = "%s · %d%%" % [operation.label, floori(percent)]
	else:
		text = "%s…" % operation.label
	_label.text = text
	tooltip_text = text
	accessibility_name = text
	_refresh_cancel()
	_update_width()


func _update_width() -> void:
	if _operation == null:
		return
	var content := MAX_CONTENT_WIDTH
	var font := _label.get_theme_font("font")
	if font != null:
		var font_size := _label.get_theme_font_size("font_size")
		var wanted := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x + CONTENT_SLACK
		content = clampf(wanted, MIN_CONTENT_WIDTH, MAX_CONTENT_WIDTH)
	_job.custom_minimum_size = Vector2(MIN_CONTENT_WIDTH, MIN_ROW_HEIGHT)
	_job.custom_maximum_size.x = content
	var cancel_width := _cancel.get_combined_minimum_size().x if _cancel.visible else 0.0
	custom_maximum_size.x = content + cancel_width


func _refresh_cancel() -> void:
	var operation := _operation
	var pending := operation != null and operation.cancel_requested
	var shown := operation != null and (operation.can_cancel() or pending)
	_cancel.visible = shown
	_cancel.disabled = pending
	var tooltip := CANCELLING_TOOLTIP if pending else CANCEL_TOOLTIP
	_cancel.tooltip_text = tooltip
	_cancel.accessibility_name = tooltip


func _on_cancel_button_down() -> void:
	_pressed_id = _operation.id if _operation != null else 0


func _on_cancel_pressed() -> void:
	var target := _pressed_id
	_pressed_id = 0
	if _operation == null:
		return
	if target != 0 and _operation.id != target:
		return
	State.cancel_operation(_operation.id)
