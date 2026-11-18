extends "./DeformTool.gd"


const DeformLimb := preload("./DeformLimb.gd")

const LIMB_CELL_LIMIT := 8192
const ANGLE_EPSILON := 0.0002
const BASE_HALF := 0.3
const DEGENERATE_SCREEN := 0.05
const FIT_PASSES := 5


class PoseJob extends DeformJob:
	var poses: Array = []
	var work := 0
	var _written := {}

	func estimated_work() -> int:
		return maxi(1, work)

	func compute_changes() -> Dictionary:
		stage("Posing voxels", work)
		_written = {}
		destination_selection = {}
		removed_cells = {}
		var changes := {}
		var done := 0
		for pose in poses:
			_pose(pose, changes)
			done += (pose["cells"] as Dictionary).size()
			if not checkpoint(done):
				return {}
		for pose in poses:
			_release_replaced(pose, changes)
			done += (pose["cells"] as Dictionary).size()
			if not checkpoint(done):
				return {}
		for cell: Vector3i in _written:
			destination_selection[cell] = true
		return changes

	func _release_replaced(pose: Dictionary, changes: Dictionary) -> void:
		var cells: Dictionary = pose["cells"]
		if cells.is_empty() or absf(float(pose["angle"])) < ANGLE_EPSILON:
			return
		for cell: Vector3i in cells:
			var turned := DeformLimb.turn_point(pose, cell, float(cells[cell]))
			var destination := DeformLimb.round_cell(turned)
			if destination == cell or not _written.has(destination) or _written.has(cell):
				continue
			changes[cell] = VoxelFrame.material(Color.TRANSPARENT)
			removed_cells[cell] = true

	func _pose(pose: Dictionary, changes: Dictionary) -> void:
		var cells: Dictionary = pose["cells"]
		if cells.is_empty() or absf(float(pose["angle"])) < ANGLE_EPSILON:
			return
		var low := Vector3(INF, INF, INF)
		var high := Vector3(-INF, -INF, -INF)
		for cell: Vector3i in cells:
			var source := Vector3(cell)
			var turned := DeformLimb.turn_point(pose, cell, float(cells[cell]))
			low = low.min(source).min(turned)
			high = high.max(source).max(turned)
		var min_cell := Vector3i(floori(low.x) - 1, floori(low.y) - 1, floori(low.z) - 1)
		var max_cell := Vector3i(ceili(high.x) + 1, ceili(high.y) + 1, ceili(high.z) + 1)
		_inverse_map(pose, cells, min_cell, max_cell, changes)
		_splat(pose, cells, changes)

	func _inverse_map(pose: Dictionary, cells: Dictionary, min_cell: Vector3i, max_cell: Vector3i, changes: Dictionary) -> void:
		var completed := 0
		for z in range(min_cell.z, max_cell.z + 1):
			for y in range(min_cell.y, max_cell.y + 1):
				for x in range(min_cell.x, max_cell.x + 1):
					_inverse_cell(pose, Vector3i(x, y, z), cells, changes)
					completed += 1
					if completed % 512 == 0 and not checkpoint(completed):
						return

	func _inverse_cell(pose: Dictionary, destination: Vector3i, cells: Dictionary, changes: Dictionary) -> void:
		if _written.has(destination) or not allows(destination):
			return
		if edited_frame.has(destination) and not cells.has(destination):
			return
		var pivot: Vector3 = pose["pivot"]
		var axis: Vector3 = pose["axis"]
		var angle: float = pose["angle"]
		var offset := Vector3(destination) - pivot
		var rigid := pivot + Basis(axis, -angle) * offset
		var point := rigid
		for _pass in 2:
			var cell := DeformLimb.round_cell(point)
			var weight := float(cells.get(cell, 0.0))
			point = pivot + Basis(axis, -angle * weight) * offset
		var source := DeformLimb.round_cell(point)
		if not cells.has(source):
			source = DeformLimb.round_cell(rigid)
			if not cells.has(source):
				return
		_put(changes, destination, edited_frame.get_material(source), _along(pose, source))

	func _splat(pose: Dictionary, cells: Dictionary, changes: Dictionary) -> void:
		for cell: Vector3i in cells:
			var weight := float(cells[cell])
			if weight <= 0.0:
				continue
			var destination := DeformLimb.round_cell(DeformLimb.turn_point(pose, cell, weight))
			if destination == cell or _written.has(destination) or not allows(destination):
				continue
			if edited_frame.has(destination) and not cells.has(destination):
				continue
			_put(changes, destination, edited_frame.get_material(cell), _along(pose, cell))

	func _put(changes: Dictionary, cell: Vector3i, material: PackedFloat32Array, along: float) -> void:
		if _written.has(cell) and float(_written[cell]) >= along:
			return
		changes[cell] = material
		_written[cell] = along

	func _along(pose: Dictionary, cell: Vector3i) -> float:
		var pivot: Vector3 = pose["pivot"]
		var bone: Vector3 = pose["bone"]
		return (Vector3(cell) - pivot).dot(bone)


var _joint_found := false
var _pivot := Vector3.ZERO
var _bone_dir := Vector3.ZERO
var _reach := 1.0
var _band := 0.0
var _limb := {}
var _poses: Array = []
var _bone: MeshInstance3D
var _stroke_connected := false
var _stroke_snap := false


var _hover_key := ""
var _hover_joint := {}
var _hover_moves := false


func _action_name() -> String:
	return "Pose"


func _operation_label() -> String:
	return "Posing voxels"


func _ready() -> void:
	super._ready()
	_bone = get_node_or_null("Bone") as MeshInstance3D
	if _bone == null:
		return
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color.WHITE
	material.no_depth_test = true
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_bone.material_override = material
	_bone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bone.visible = false


func _clear_state() -> void:
	super._clear_state()
	_joint_found = false
	_limb = {}
	_poses = []
	_pivot = Vector3.ZERO
	_bone_dir = Vector3.ZERO
	_reach = 1.0
	_band = 0.0
	_hover_key = ""
	_hover_joint = {}
	_hover_moves = false
	if _bone != null:
		_bone.visible = false


func _capture_gesture(pick: PickResult) -> bool:
	_stroke_connected = _settings.connected
	_stroke_snap = _settings.snap
	var joint := DeformLimb.joint_pivot(_source_frame, _anchor, _stroke_size, _stroke_context, _stroke_connected, _view_forward, _stroke_face, _stroke_touch)
	_joint_found = bool(joint["found"])
	if not _joint_found:
		return false
	_pivot = joint["pivot"]
	_bone_dir = joint["bone_dir"]
	_reach = float(joint["reach"])
	_band = DeformLimb.joint_band(_stroke_size, _stroke_falloff)
	var brush_reach := float(clampi(_stroke_size, 1, 32)) * 0.5
	_limb = DeformLimb.capture_limb(_source_frame, _anchor, _pivot, _bone_dir, _band, brush_reach, LIMB_CELL_LIMIT, _stroke_context, _stroke_connected)
	if _limb.is_empty():
		return false
	_poses = _build_poses()
	return true


func _pose_footprint(pick: PickResult) -> void:
	if _edit != null:
		_hide_footprint()
		return
	super._pose_footprint(pick)


func _allows(cell: Vector3i) -> bool:
	return _write_context == null or _write_context.allows(cell)


func _reflect(cell: Vector3i, mask: int) -> Vector3i:
	return _stroke_context.reflect(cell, mask) if _stroke_context != null else cell


func _mirror(point: Vector3, mask: int) -> Vector3:
	return DeformLimb.mirror_point(point, _stroke_context, mask)


func _build_poses() -> Array:
	var poses := []
	for mask in DeformLimb.masks_for(_stroke_context):
		var cells := {}
		for cell: Vector3i in _limb:
			cells[_reflect(cell, mask)] = _limb[cell]
		var pivot := _mirror(_pivot, mask)
		var bone := _mirror(_pivot + _bone_dir, mask) - pivot
		poses.append({
			"mask": mask,
			"pivot": pivot,
			"bone": bone.normalized(),
			"cells": cells,
			"angle": 0.0,
		})
	return poses


func _make_job(_target: Vector3i) -> DeformJob:
	if _limb.is_empty() or _poses.is_empty():
		return null
	var pressed := Vector3(_anchor)
	var travel := _drag_point - pressed
	if travel.length() < 0.001:
		return null
	var axis := -_view_forward
	var entries := []
	var work := 0
	var magnitude := 0.0
	var primary := NAN
	for pose in _poses:
		var mask: int = pose["mask"]
		var cells: Dictionary = pose["cells"]
		var pivot: Vector3 = pose["pivot"]
		var bone := _mirror(pressed, mask) - pivot
		var arm := _mirror(_drag_point, mask) - pivot
		var screen_bone := DeformLimb.screen_vector(bone, _view_right, _view_up)
		var screen_arm := DeformLimb.screen_vector(arm, _view_right, _view_up)
		var angle := 0.0
		if screen_bone.length() < DEGENERATE_SCREEN or screen_arm.length() < DEGENERATE_SCREEN:
			var lever := maxf(DeformLimb.screen_length(bone, _view_right, _view_up), maxf(float(_stroke_size) * 0.5, 0.5))
			angle = DeformLimb.screen_vector(travel, _view_right, _view_up).length() / lever
		else:
			angle = screen_bone.angle_to(screen_arm)
		if is_nan(primary):
			primary = angle
		else:
			angle = primary * DeformLimb.mask_handedness(mask)
		work += cells.size()
		entries.append({
			"mask": mask,
			"pivot": pivot,
			"bone": bone.normalized(),
			"cells": cells,
			"angle": angle,
			"axis": DeformLimb.mirror_direction(axis, mask),
		})
		magnitude = maxf(magnitude, absf(float(entries[entries.size() - 1]["angle"])))
	if _stroke_snap:
		magnitude = snappedf(magnitude, PI * 0.5)
	if magnitude < ANGLE_EPSILON:
		return null
	var fitted := _fit_angle(entries, magnitude)
	if fitted < ANGLE_EPSILON:
		return null
	for entry in entries:
		entry["angle"] = signf(float(entry["angle"])) * fitted
	var job := PoseJob.new()
	job.poses = entries
	for entry in entries:
		work = maxi(work, _swept_volume(entry))
	job.work = work
	return job


func _swept_volume(entry: Dictionary) -> int:
	var cells: Dictionary = entry["cells"]
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for cell: Vector3i in cells:
		var turned := DeformLimb.turn_point(entry, cell, float(cells[cell]))
		low = low.min(Vector3(cell)).min(turned)
		high = high.max(Vector3(cell)).max(turned)
	return roundi((high.x - low.x + 3.0) * (high.y - low.y + 3.0) * (high.z - low.z + 3.0))


func _fit_angle(entries: Array, magnitude: float) -> float:
	if _fits(entries, magnitude):
		return magnitude
	var low := 0.0
	var high := magnitude
	for _pass in FIT_PASSES:
		var middle := (low + high) * 0.5
		if _fits(entries, middle):
			low = middle
		else:
			high = middle
	return low


func _fits(entries: Array, magnitude: float) -> bool:
	for entry in entries:
		var cells: Dictionary = entry["cells"]
		var angle := signf(float(entry["angle"])) * magnitude
		for cell: Vector3i in cells:
			var turned := DeformLimb.turn_point(entry, cell, float(cells[cell]), angle)
			var destination := DeformLimb.round_cell(turned)
			if not _allows(destination):
				return false
			if destination == cell:
				continue
			if _baseline != null and _baseline.has(destination) and not cells.has(destination):
				return false
	return true

func _hover_state(pick: PickResult) -> Dictionary:
	var frame := State.get_current_voxel_frame()
	if frame == null:
		return {}
	var context := State.drawing_context()
	var key := _hover_key_for(pick, frame, context)
	if key == _hover_key:
		return {"joint": _hover_joint, "moves": _hover_moves}
	var joint := DeformLimb.joint_pivot(frame, pick.hit, _settings.size, context, _settings.connected, _cursor_forward(), _hover_face, _hover_touch)
	var moves := false
	if bool(joint["found"]):
		var band := DeformLimb.joint_band(_settings.size, _settings.falloff)
		var brush_reach := float(clampi(_settings.size, 1, 32)) * 0.5
		var limb := DeformLimb.capture_limb(frame, pick.hit, joint["pivot"], joint["bone_dir"], band, brush_reach, 1, context, _settings.connected)
		moves = not limb.is_empty()
	_hover_key = key
	_hover_joint = joint
	_hover_moves = moves
	return {"joint": _hover_joint, "moves": _hover_moves}


func _hover_key_for(pick: PickResult, frame: VoxelFrame, context: VoxelFrame.EditContext) -> String:
	return str([
		frame.get_instance_id(), pick.hit,
		_settings.size, _settings.falloff, _settings.connected, _cursor_forward(), _hover_face,
		Vector2i(roundi(_hover_touch.x * 4.0), roundi(_hover_touch.y * 4.0)),
		State.selection.revision,
		context.slice_axis, context.slice_index, context.slice_count,
		context.bounded_axes, context.bounds_min, context.bounds_max,
	])


func _pose_bone(pick: PickResult) -> void:
	if _bone == null:
		return
	if pick == null or pick.hit == VoxelPicking.NONE or not is_inside_tree():
		_hide_bone()
		return
	var pivot := _pivot
	var tip := Vector3(pick.hit)
	if _edit == null:
		var state := _hover_state(pick)
		if state.is_empty() or not bool(state["joint"]["found"]) or not bool(state["moves"]):
			_hide_bone()
			return
		pivot = state["joint"]["pivot"]
	elif not _joint_found:
		_hide_bone()
		return
	else:
		tip = _drag_point
	var vertices := PackedVector3Array()
	vertices.append(pivot)
	vertices.append(tip)
	_append_joint_square(vertices, pivot)
	if _edit == null:
		_append_face_widget(vertices, pick)
	_bone.global_transform = Transform3D(Basis.IDENTITY, Vector3.ZERO)
	_bone.mesh = VoxelLineMesh.build(vertices)
	visible = true
	_bone.visible = true


func _append_joint_square(vertices: PackedVector3Array, pivot: Vector3) -> void:
	var forward := _cursor_forward()
	var up := Vector3.UP
	if absf(forward.dot(Vector3.UP)) > 0.99:
		up = Vector3.RIGHT
	var right := forward.cross(up).normalized()
	up = right.cross(forward).normalized()
	var corners := [
		pivot + (-right - up) * BASE_HALF,
		pivot + (right - up) * BASE_HALF,
		pivot + (right + up) * BASE_HALF,
		pivot + (-right + up) * BASE_HALF,
	]
	for index in 4:
		vertices.append(corners[index])
		vertices.append(corners[(index + 1) % 4])


func _append_face_widget(vertices: PackedVector3Array, pick: PickResult) -> void:
	var axis := _face_axis(pick)
	if axis < 0 or pick.hit == VoxelPicking.NONE:
		return
	var center := Vector3(pick.hit)
	center[axis] += (0.5 if pick.entry[axis] > 0 else -0.5) + 0.02 * float(pick.entry[axis])
	var half_u := Vector3.ZERO
	half_u[(axis + 1) % 3] = 0.5
	var half_v := Vector3.ZERO
	half_v[(axis + 2) % 3] = 0.5
	var corners := [
		center - half_u - half_v,
		center + half_u - half_v,
		center + half_u + half_v,
		center - half_u + half_v,
	]
	for index in 4:
		vertices.append(corners[index])
		vertices.append(corners[(index + 1) % 4])
	vertices.append(center - half_u)
	vertices.append(center + half_u)
	vertices.append(center - half_v)
	vertices.append(center + half_v)


func _hide_bone() -> void:
	if _bone != null:
		_bone.visible = false
