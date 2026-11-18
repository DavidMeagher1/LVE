extends "res://plugins/brush/StrokeTool.gd"


func _init() -> void:
	_settings = preload("./PaintSettings.tres")


func _pick_adds() -> bool:
	return false


func _requires_hit() -> bool:
	return true


func _paints_existing() -> bool:
	return true


func pick_drag(request: PickRequest) -> PickResult:
	return VoxelPicking.start_pick(request.origin, request.direction, request.frame, request.forward, State.slice_enabled)
