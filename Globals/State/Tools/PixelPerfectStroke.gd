class_name PixelPerfectStroke
extends RefCounted


var _last_drawn := VoxelPicking.NONE
var _waiting := VoxelPicking.NONE


func reset() -> void:
	_last_drawn = VoxelPicking.NONE
	_waiting = VoxelPicking.NONE


func feed(p: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	if _last_drawn == VoxelPicking.NONE:
		_last_drawn = p
		_waiting = p
		return out
	if p == _waiting or p == _last_drawn:
		return out
	if _neighbor(_last_drawn, p):
		_waiting = p
		return out
	for c in StrokeLine.cells(_waiting, p):
		out.append(c)
	_last_drawn = p
	_waiting = p
	return out


func flush() -> Array[Vector3i]:
	if _waiting == VoxelPicking.NONE or _waiting == _last_drawn:
		return []
	var out: Array[Vector3i] = [_waiting]
	_last_drawn = _waiting
	_waiting = VoxelPicking.NONE
	return out


func _neighbor(a: Vector3i, b: Vector3i) -> bool:
	return maxi(absi(a.x - b.x), maxi(absi(a.y - b.y), absi(a.z - b.z))) <= 1
