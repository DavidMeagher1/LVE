class_name TerrainFrame
extends RefCounted


var origin := Vector3.ZERO
var normal := Vector3.UP
var tangent_u := Vector3.RIGHT
var tangent_v := Vector3.FORWARD
var axis := 1
var sign := 1
var follows_surface := false
var on_floor := false


static func from_face(hit: Vector3i, entry: Vector3i) -> TerrainFrame:
	var frame := TerrainFrame.new()
	var use_axis := TerrainGeometry.axis_of(entry)
	if use_axis < 0:
		use_axis = 1
	var use_sign := TerrainGeometry.sign_of(entry, use_axis)
	frame.axis = use_axis
	frame.sign = use_sign
	frame.normal = _axis_vector(use_axis, use_sign)
	frame.origin = Vector3(hit) + frame.normal * 0.5
	frame._build_cardinal_basis(use_axis)
	return frame


static func from_floor(floor_axis: int, floor_sign: int, floor_level: float, target: Vector3i) -> TerrainFrame:
	var frame := TerrainFrame.new()
	frame.axis = floor_axis
	frame.sign = floor_sign
	frame.normal = _axis_vector(floor_axis, floor_sign)
	frame.origin = Vector3(target)
	frame.origin[floor_axis] = floor_level + float(floor_sign)
	frame.on_floor = true
	frame._build_cardinal_basis(floor_axis)
	return frame


static func from_surface(frame: VoxelFrame, hit: Vector3i, entry: Vector3i, radius: int, fallback: TerrainFrame, job: VoxelFrame.EditJob = null, context: TerrainQueryContext = null) -> TerrainFrame:
	var points := TerrainGeometry.surface_points(frame, hit, entry, radius, job, context)
	if points.size() < 3:
		return fallback
	var surface := TerrainGeometry.surface_gradient(points, fallback.normal)
	if not surface["ok"]:
		return fallback
	var result := TerrainFrame.new()
	result.normal = surface["normal"]
	var centroid: Vector3 = surface["centroid"]
	result.origin = centroid + result.normal * result.normal.dot(fallback.origin - centroid)
	result.axis = TerrainGeometry.dominant_axis(result.normal)
	result.sign = 1 if result.normal[result.axis] >= 0.0 else -1
	result.follows_surface = true
	result._build_normal_basis()
	return result


func plane_point(cell: Vector3i) -> Vector3:
	var point := Vector3(cell)
	return point - normal * normal.dot(point - origin)


static func cardinal(frame: TerrainFrame) -> TerrainFrame:
	if frame == null:
		return null
	var result := TerrainFrame.new()
	result.axis = TerrainGeometry.dominant_axis(frame.normal)
	result.sign = 1 if frame.normal[result.axis] >= 0.0 else -1
	result.normal = _axis_vector(result.axis, result.sign)
	result.origin = frame.origin
	result.follows_surface = frame.follows_surface
	result.on_floor = frame.on_floor
	result._build_cardinal_basis(result.axis)
	return result


func recenter_to(surface: Vector3i, half_height: float) -> TerrainFrame:
	if surface == VoxelPicking.NONE or half_height <= 0.0:
		return self
	var center := Vector3(surface) + normal * 0.5
	var offset := clampf((center - origin).dot(normal), -half_height, half_height)
	if absf(offset) <= 1e-6:
		return self
	var result := TerrainFrame.new()
	result.normal = normal
	result.tangent_u = tangent_u
	result.tangent_v = tangent_v
	result.axis = axis
	result.sign = sign
	result.follows_surface = follows_surface
	result.on_floor = on_floor
	result.origin = origin + normal * offset
	return result


func reflected(context: VoxelFrame.EditContext, mask: int) -> TerrainFrame:
	if mask == 0:
		return self
	var result := TerrainFrame.new()
	result.origin = _reflect_point(origin, context.origin_twice, mask)
	result.normal = _reflect_vector(normal, mask)
	result.tangent_u = _reflect_vector(tangent_u, mask)
	result.tangent_v = _reflect_vector(tangent_v, mask)
	result.axis = axis
	result.sign = -sign if mask & (1 << axis) else sign
	result.follows_surface = follows_surface
	result.on_floor = on_floor
	return result


static func mirror_point(point: Vector3, context: VoxelFrame.EditContext, mask: int) -> Vector3:
	return _reflect_point(point, context.origin_twice, mask)


func to_plane() -> Plane:
	return Plane(normal, origin)


func _build_cardinal_basis(use_axis: int) -> void:
	var first := Vector3.ZERO
	var second := Vector3.ZERO
	match use_axis:
		0:
			first = Vector3.UP
			second = Vector3.BACK
		1:
			first = Vector3.RIGHT
			second = Vector3.BACK
		_:
			first = Vector3.RIGHT
			second = Vector3.UP
	tangent_u = first
	tangent_v = second


func _build_normal_basis() -> void:
	var seed := Vector3.UP if absf(normal.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
	tangent_u = normal.cross(seed).normalized()
	tangent_v = normal.cross(tangent_u).normalized()


static func _axis_vector(axis: int, sign: int) -> Vector3:
	var vector := Vector3.ZERO
	vector[axis] = float(sign)
	return vector


static func _reflect_point(point: Vector3, origin_twice: Vector3i, mask: int) -> Vector3:
	var result := point
	for axis in 3:
		if mask & (1 << axis):
			result[axis] = float(origin_twice[axis]) - result[axis]
	return result


static func _reflect_vector(vector: Vector3, mask: int) -> Vector3:
	var result := vector
	for axis in 3:
		if mask & (1 << axis):
			result[axis] = -result[axis]
	return result
