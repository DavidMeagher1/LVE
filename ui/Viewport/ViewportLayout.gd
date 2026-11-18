extends Control


@onready var _panel: PanelContainer = $PanelContainer
@onready var _bar: HBoxContainer = %ControlBar
@onready var _environment_layer: MarginContainer = %EnvironmentLayer


func _ready() -> void:
	_bar.resized.connect(_sync_spacing)
	_sync_spacing()


func camera() -> EditorCameraRig:
	return %CameraRig


func set_rendering_active(active: bool) -> void:
	var viewport: SubViewport = %Viewport
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED


func _sync_spacing() -> void:
	var bar_height := _bar.get_combined_minimum_size().y
	_panel.offset_bottom = -bar_height - get_theme_constant("separation", "VBoxContainer")
	_environment_layer.offset_top = -bar_height
	_environment_layer.offset_bottom = -bar_height
