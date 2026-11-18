extends "./SelectTool.gd"


const SCREEN_STEP := 6.0
const SCREEN_POINT_LIMIT := 512

var _points := PackedVector2Array()


func _begin_shape(pos: Vector2) -> void:
	_points = PackedVector2Array([pos])
	_show_band_polygon(_points)


func _update_shape(pos: Vector2) -> void:
	_append_point(pos)
	_show_band_polygon(_points)


func _commit_shape(pos: Vector2) -> void:
	_append_point(pos)
	if _points.size() >= 3:
		_commit_screen(Rect2(), _points)
		return
	_commit_screen(_screen_rectangle(pos), PackedVector2Array())


func _is_click(release_pos: Vector2) -> bool:
	if not super._is_click(release_pos):
		return false
	for point in _points:
		var travel := (point - _screen_press).abs()
		if travel.x >= CLICK_SIZE or travel.y >= CLICK_SIZE:
			return false
	return true


func _reset_shape() -> void:
	_points = PackedVector2Array()


func _append_point(pos: Vector2) -> void:
	if _points.size() >= SCREEN_POINT_LIMIT:
		var thinned := PackedVector2Array()
		for index in range(0, _points.size(), 2):
			thinned.append(_points[index])
		_points = thinned
	if not _points.is_empty() and _points[_points.size() - 1].distance_to(pos) < SCREEN_STEP:
		return
	_points.append(pos)
