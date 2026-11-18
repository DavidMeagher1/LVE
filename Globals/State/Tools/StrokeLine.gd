class_name StrokeLine
extends RefCounted


class Cursor extends RefCounted:
	var _cell := Vector3i.ZERO
	var _step := Vector3i.ZERO
	var _span := Vector3i.ZERO
	var _remaining := 0
	var _dominant := 0
	var _error := [0.0, 0.0, 0.0]

	func _init(a: Vector3i, b: Vector3i) -> void:
		_cell = a
		var delta := b - a
		_span = Vector3i(absi(delta.x), absi(delta.y), absi(delta.z))
		_step = Vector3i(StrokeLine._signi(delta.x), StrokeLine._signi(delta.y), StrokeLine._signi(delta.z))
		_dominant = StrokeLine._dominant(_span)
		_remaining = _span[_dominant]

	func origin() -> Vector3i:
		return _cell

	func remaining() -> int:
		return _remaining

	func progress() -> float:
		if _span[_dominant] <= 0:
			return 1.0
		return 1.0 - float(_remaining) / float(_span[_dominant])

	func next_cell() -> Variant:
		if _remaining <= 0:
			return null
		_cell[_dominant] += _step[_dominant]
		for axis in 3:
			if axis == _dominant or _span[axis] == 0:
				continue
			_error[axis] += float(_span[axis]) / float(_span[_dominant])
			if _error[axis] >= 0.5:
				_cell[axis] += _step[axis]
				_error[axis] -= 1.0
		_remaining -= 1
		return _cell


static func cells(a: Vector3i, b: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var cursor := Cursor.new(a, b)
	out.append(cursor.origin())
	var cell: Variant = cursor.next_cell()
	while cell != null:
		out.append(cell)
		cell = cursor.next_cell()
	return out


static func _dominant(ad: Vector3i) -> int:
	if ad.y >= ad.x and ad.y >= ad.z:
		return 1
	if ad.z >= ad.x:
		return 2
	return 0


static func _signi(v: int) -> int:
	return -1 if v < 0 else (1 if v > 0 else 0)
