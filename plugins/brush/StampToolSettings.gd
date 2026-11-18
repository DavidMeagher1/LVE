class_name StampToolSettings
extends Resource


const VoxelBrushSize := preload("res://Globals/State/Tools/VoxelBrushSize.gd")

enum BrushShape {
	CUBE,
	SPHERE,
	STAMP
}

@export_range(1, 64, 1) var diameter := 1:
	set(value):
		value = VoxelBrushSize.clamp_size(value)
		if value == diameter:
			return
		diameter = value
		_cached_pattern = {}
		_cached_offsets = []
		emit_changed()

@export var shape: BrushShape = BrushShape.CUBE:
	set(value):
		if value == shape:
			return
		shape = value
		_cached_pattern = {}
		_cached_offsets = []
		emit_changed()

@export var pixel_perfect:bool = false :
	set(value):
		if value == pixel_perfect:
			return
		pixel_perfect = value
		emit_changed()

var stamp_pattern := {}
var stamp_material_pattern := {}
var stamp_offsets: Array = []
var _cached_pattern := {}
var _cached_offsets := []


func use_stamp(copied_pattern: Dictionary, copied_material_pattern: Dictionary = {}) -> void:
	stamp_pattern = copied_pattern
	stamp_pattern.make_read_only()
	stamp_offsets = copied_pattern.keys()
	stamp_material_pattern = copied_material_pattern.duplicate(true)
	stamp_material_pattern.make_read_only()
	shape = BrushShape.STAMP
	emit_changed()


func clear_stamp() -> void:
	if stamp_pattern.is_empty() and stamp_material_pattern.is_empty():
		return
	stamp_pattern = {}
	stamp_offsets = []
	stamp_material_pattern = {}
	emit_changed()


func estimated_size() -> int:
	return stamp_pattern.size() if shape == BrushShape.STAMP else diameter ** 3


func pattern() -> Dictionary:
	if shape == BrushShape.STAMP:
		return stamp_pattern
	if _cached_pattern.is_empty() and estimated_size() <= 4096:
		_cached_pattern = _build_pattern(diameter, shape)
		_cached_pattern.make_read_only()
	return _cached_pattern


func pattern_offsets() -> Array:
	if shape == BrushShape.STAMP:
		return stamp_offsets
	if _cached_offsets.is_empty() and estimated_size() <= 4096:
		_cached_offsets = pattern().keys()
	return _cached_offsets


func cache_pattern(brush_diameter: int, brush_shape: int, cells: Dictionary, offsets: Array = []) -> void:
	if diameter == brush_diameter and shape == brush_shape and shape != BrushShape.STAMP:
		_cached_pattern = cells
		_cached_pattern.make_read_only()
		_cached_offsets = offsets


func _build_pattern(_brush_diameter: int, _brush_shape: int) -> Dictionary:
	return {}


func create_pattern_job():
	return null
