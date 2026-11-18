extends "res://plugins/brush/StrokeTool.gd"


const SpraySampler := preload("./SpraySampler.gd")
const SpraySamplingJob := preload("./SpraySamplingJob.gd")

const INLINE_SAMPLE_LIMIT := 2200

class Intent extends RefCounted:
	var center := Vector3i.ZERO
	var frame: VoxelFrame
	var context: VoxelFrame.EditContext
	var material := PackedFloat32Array()
	var estimate := 0
	var spot_size := 1
	var search_size := 9
	var speed := 8

	func matches(other: Intent) -> bool:
		return center == other.center and frame == other.frame \
			and context == other.context and material == other.material \
			and estimate == other.estimate and spot_size == other.spot_size \
			and search_size == other.search_size and speed == other.speed

class BatchToken extends RefCounted:
	var center := VoxelPicking.NONE
	var frame: VoxelFrame
	var axes := 0
	var origin_twice := Vector3i.ZERO
	var selection := {}
	var slice_axis := -1
	var slice_index := 0
	var slice_count := 1

var _paint_settings: PaintToolSettings
var _rng := RandomNumberGenerator.new()
var _rng_epoch := 0
var _shape_cache := SpraySampler.ShapeCache.new()
var _selection_source := {}
var _selection_index: RefCounted = null
var _selection_equal_a := {}
var _selection_equal_b := {}
var last_index_builds := 0
var last_index_grid_reads := 0
var last_index_build_slots := 0
var last_selection_builds := 0
var last_work_estimate := 0
var last_capture_chunks := 0
var last_row_ops := 0
var last_footprint_visits := 0
var _batch_center := VoxelPicking.NONE
var _batch_cells: Array[Vector3i] = []
var _batch_material := VoxelFrame.material(Color.WHITE)
var _batch_axes := 0
var _batch_origin := Vector3i.ZERO
var _batch_selection := {}
var _batch_slice_axis := -1
var _batch_slice_index := 0
var _batch_slice_count := 1
var _batch_frame: VoxelFrame
var _batch_token: BatchToken
var _batch_fresh := false
var _batch_chunks := {}
var _batch_version := 0
var _preview_version := -1
var _preview_active := false
var _shown_spots := {}
var _shown_witness := {}
var _batch_payload

var _sample_job: SpraySamplingJob = null
var _sample_operation_id := 0
var _pending_intents: Array[Intent] = []
var _intent_running := false
var _running_intent: Intent = null
var _press_pending := false
var _pending_end := false
var _reroll_pending := false

var _hover_sample_job: SpraySamplingJob = null
var _retired_hover_jobs: Array[SpraySamplingJob] = []
var _hover_sample_operation_id := 0
var _hover_request := {}
var _hover_epoch := 0
var _hover_installed_epoch := 0


func _init() -> void:
	_paint_settings = preload("./PaintSettings.tres")
	_settings = _paint_settings


func _ready() -> void:
	super._ready()
	_rng.randomize()
	_rng_epoch += 1


func _enter_tree() -> void:
	_invalidate_batch()
	clear_selection_cache()
	super._enter_tree()
	if not State.selection_changed.is_connected(_on_selection_changed):
		State.selection_changed.connect(_on_selection_changed)
	if not State.document_changed.is_connected(_on_document_changed):
		State.document_changed.connect(_on_document_changed)


func _exit_tree() -> void:
	clear_selection_cache()
	if State.selection_changed.is_connected(_on_selection_changed):
		State.selection_changed.disconnect(_on_selection_changed)
	if State.document_changed.is_connected(_on_document_changed):
		State.document_changed.disconnect(_on_document_changed)
	_invalidate_batch()
	super._exit_tree()


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_teardown_hover_sample()
		_teardown_samples()
	super._notification(what)


func _process(delta: float) -> void:
	super._process(delta)
	_pump_hover_sample()
	if _reroll_pending and _edit == null and _sample_job == null and _pending_intents.is_empty():
		_reroll_pending = false
		_invalidate_batch()
		if _last_pick:
			update_visual(_last_pick)


func seed_spray(seed_value: int) -> void:
	_rng.seed = seed_value
	_rng_epoch += 1


func clear_shape_caches() -> void:
	_shape_cache.clear()


func clear_selection_cache() -> void:
	_selection_source = {}
	_selection_index = null
	_selection_equal_a = {}
	_selection_equal_b = {}


func _on_selection_changed() -> void:
	clear_selection_cache()


func _on_document_changed() -> void:
	clear_selection_cache()


func _same_selection(first: Dictionary, second: Dictionary) -> bool:
	if not first.is_read_only() or not second.is_read_only():
		return false
	if is_same(first, second):
		return true
	var cached_pair := (is_same(first, _selection_equal_a) and is_same(second, _selection_equal_b)) or (is_same(first, _selection_equal_b) and is_same(second, _selection_equal_a))
	if cached_pair:
		return true
	if first != second:
		return false
	_selection_equal_a = first
	_selection_equal_b = second
	return true


func _cached_selection_index(selection: Dictionary) -> RefCounted:
	if selection.is_empty() or not selection.is_read_only():
		clear_selection_cache()
		return null
	if not is_same(selection, State.selection.all_cells()):
		clear_selection_cache()
		return null
	if is_same(_selection_source, selection) and _selection_index != null:
		return _selection_index
	return null


func _remember_selection_index(selection: Dictionary, index: RefCounted) -> void:
	if not selection.is_read_only() or not is_same(selection, State.selection.all_cells()):
		clear_selection_cache()
		return
	if index == null:
		return
	_selection_source = selection
	_selection_index = index


func is_sample_settled() -> bool:
	return _hover_sample_job == null and _sample_job == null and _pending_intents.is_empty()


func preview_cells() -> Array[Vector3i]:
	return _batch_cells.duplicate()


func _pick_adds() -> bool:
	return false


func _requires_hit() -> bool:
	return true


func _paints_existing() -> bool:
	return true


func pick_drag(request: PickRequest) -> PickResult:
	return VoxelPicking.start_pick(request.origin, request.direction, request.frame, request.forward, State.slice_enabled)


func open_stroke() -> VoxelEditTransaction:
	var tx := super.open_stroke()
	if tx == null:
		return null
	_stroke_pattern = {Vector3i.ZERO: Color.TRANSPARENT}
	_stroke_offsets = [Vector3i.ZERO]
	_stroke_diameter = 1
	_stroke_shape = StampSettings.BrushShape.CUBE
	_stroke_pattern_size = 1
	return tx


func handle_input(event: InputEvent, pos: Vector2) -> bool:
	if event.is_action_pressed("ui_cancel") and _edit != null:
		_cancel_edit()
		return true
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _edit != null or _job or _intent_running or _sample_job != null:
				return true
			var ray := _ray(pos)
			var pick := _pick_start(ray[0], ray[1])
			if pick.hit == VoxelPicking.NONE:
				return false
			if open_stroke() == null:
				return false
			var stale := _batch_center != pick.hit or _batch_frame != _source_frame
			if not stale and _edit_context != null:
				stale = not _batch_matches(_edit_context)
			if stale:
				_invalidate_batch()
				_clear_cursor_preview()
			_plane = pick.plane
			_last_target = pick.target
			_stroke_active = true
			_press_pending = true
			update_visual(pick)
			_press_pending = false
			_apply_offered()
		else:
			if _stroke_active:
				_finish_click()
		return true
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if _stroke_active and not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			_finish_click()
			return true
		if _stroke_active and _plane != null and motion.button_mask & MOUSE_BUTTON_MASK_LEFT:
			var ray := _ray(pos)
			var pick := _pick_drag(ray[0], ray[1])
			update_visual(pick)
			if _batch_fresh:
				_apply_batch()
			return true
		if motion.button_mask == 0:
			var ray := _ray(pos)
			update_visual(_pick_start(ray[0], ray[1]))
			return true
		return false
	return false


func _finish_click() -> void:
	_end()
	if _pending_end:
		_reroll_pending = true
		return
	_invalidate_batch()
	if _last_pick:
		update_visual(_last_pick)


func _apply_pick(_target: Vector3i, _hit: Vector3i) -> void:
	pass


func _apply_stroke_to(_to: Vector3i) -> void:
	pass


func _cancel_edit() -> void:
	_pending_end = false
	_cancel_samples()
	_invalidate_batch()
	_clear_cursor_preview()
	super._cancel_edit()


func _on_settings_changed() -> void:
	_invalidate_batch()
	super._on_settings_changed()


func _on_history_changed() -> void:
	_cancel_samples()
	_invalidate_batch()
	_clear_cursor_preview()
	super._on_history_changed()


func update_visual(pick: PickResult) -> void:
	if pick.plane == null:
		pick.plane = _plane
	_last_pick = pick
	_batch_fresh = false
	if pick.target == VoxelPicking.NONE or pick.hit == VoxelPicking.NONE:
		visible = false
		_show_spots([])
		return
	position = Vector3.ZERO
	visible = true
	if _stroke_active:
		_batch_fresh = _ensure_batch_if_cheap(pick.hit, _source_frame, _edit_context, _stroke_material)
		_show_spots(_batch_cells)
		return
	var frame := State.get_current_voxel_frame()
	var material := State.current_material
	var context := State.drawing_context()
	_ensure_hover_batch(pick.hit, frame, context, material)
	if _batch_environment_matches(frame, context, material):
		_show_spots(_batch_cells)
	else:
		_show_spots([])


func _end() -> void:
	_end_requested = false
	_pending_end = true
	_stroke_active = false
	_close_if_idle()


func _close_if_idle() -> void:
	if not _pending_end:
		return
	if _sample_job != null or not _pending_intents.is_empty():
		return
	_pending_end = false
	_end_requested = true
	if _job == null:
		_finish_stroke()


func _invalidate_batch() -> void:
	_cancel_hover_sample()
	_reroll_pending = false
	_batch_center = VoxelPicking.NONE
	_batch_cells = []
	_batch_material = VoxelFrame.material(Color.WHITE)
	_batch_frame = null
	_batch_token = null
	_batch_fresh = false
	_batch_chunks = {}
	_batch_payload = null
	_batch_version += 1
	_preview_version = -1
	_hover_installed_epoch = _hover_epoch


func _ensure_batch(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, material: PackedFloat32Array) -> bool:
	if frame == null or context == null:
		return false
	if _batch_key_matches(center, frame, context, material) and _batch_holds(frame):
		return false
	var context_changed := not _batch_environment_matches(frame, context, material)
	if context_changed:
		_clear_cursor_preview()
	_batch_center = center
	_batch_frame = frame
	_batch_material = material.duplicate()
	_batch_axes = context.axes
	_batch_origin = context.origin_twice
	_batch_selection = context.selection
	_batch_slice_axis = context.slice_axis
	_batch_slice_index = context.slice_index
	_batch_slice_count = context.slice_count
	_batch_token = _make_batch_token(frame, center, context)
	_batch_cells = _sample(center, frame, context)
	_snapshot_batch_chunks(frame)
	_batch_payload = null
	_batch_version += 1
	return true


func _ensure_batch_if_cheap(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, material: PackedFloat32Array) -> bool:
	if frame == null or context == null:
		return false
	if _batch_key_matches(center, frame, context, material) and _batch_holds(frame):
		return false
	var selection_index := _cached_selection_index(context.selection)
	var estimate := SpraySampler.work_estimate(frame, center, _paint_settings.spray_size, _paint_settings.spot_diameter, context.selection, _paint_settings.speed, selection_index)
	last_work_estimate = estimate
	if estimate <= INLINE_SAMPLE_LIMIT:
		return _ensure_batch(center, frame, context, material)
	if not _press_pending:
		_accept_intent(center, frame, context, material, estimate)
	return false


func _accept_intent(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, material: PackedFloat32Array, estimate: int) -> void:
	var intent := Intent.new()
	intent.center = center
	intent.frame = frame
	intent.context = context
	intent.material = material.duplicate()
	intent.estimate = estimate
	intent.spot_size = _paint_settings.spot_diameter
	intent.search_size = _paint_settings.spray_size
	intent.speed = _paint_settings.speed
	var newest: Intent = _pending_intents.back() if not _pending_intents.is_empty() else _running_intent
	if newest != null and newest.matches(intent):
		return
	_pending_intents.append(intent)
	_run_intents()


func _run_intents() -> void:
	if _intent_running:
		return
	_intent_running = true
	while not _pending_intents.is_empty():
		var tx := _edit
		if tx == null:
			_pending_intents.clear()
			break
		var intent: Intent = _pending_intents.pop_front()
		if intent.frame == null or intent.context == null:
			continue
		_running_intent = intent
		var job := _build_sample_job(intent.frame, intent.center, intent.context, intent.material, intent.estimate, intent.spot_size, intent.search_size, intent.speed)
		_sample_job = job
		_sample_operation_id = State.begin_operation("Sampling spray", job.local_estimate, true, self, _cancel_edit)
		await State.run_edit_job(job, _sample_operation_id, "Spray sample")
		var current := _sample_job == job
		_sample_job = null
		State.finish_operation(_sample_operation_id)
		_sample_operation_id = 0
		if not current or _edit != tx:
			break
		if not job.checkpoint(0):
			break
		var witness := job.witness
		if not _witness_holds(witness, intent.frame):
			if not _cells_hold(intent.frame, job.cells):
				continue
			witness = {}
		_commit_sample_state(job)
		_remember_selection_index(job.selection, job.built_selection_index)
		last_index_builds = job.index_builds
		last_index_grid_reads = job.index_grid_reads
		last_index_build_slots = job.index_build_slots
		last_selection_builds = job.selection_builds
		last_row_ops = job.row_ops
		last_footprint_visits = job.footprint_visits
		if not job.cells.is_empty():
			_adopt_batch(intent.frame, intent.center, intent.context, intent.material, job.cells, witness, job.preview_payload)
			_queue_centers(job.cells)
		_running_intent = null
	_intent_running = false
	_close_if_idle()
	_release_context_subscriptions()


func _cancel_samples() -> void:
	_pending_intents.clear()
	_running_intent = null
	if _sample_job:
		_sample_job.cancel()


func _teardown_samples() -> void:
	_cancel_samples()
	if _sample_job:
		_sample_job.wait_for_worker()
		_sample_job = null
	State.finish_operation(_sample_operation_id)
	_sample_operation_id = 0


func _ensure_hover_batch(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, material: PackedFloat32Array) -> void:
	if frame == null or context == null:
		return
	if _batch_key_matches(center, frame, context, material) and _batch_holds(frame):
		return
	var selection_index := _cached_selection_index(context.selection)
	var estimate := SpraySampler.work_estimate(frame, center, _paint_settings.spray_size, _paint_settings.spot_diameter, context.selection, _paint_settings.speed, selection_index)
	last_work_estimate = estimate
	if estimate <= INLINE_SAMPLE_LIMIT:
		_hover_epoch += 1
		_hover_installed_epoch = _hover_epoch
		_hover_request = {}
		_ensure_batch(center, frame, context, material)
		return
	var context_changed := not _batch_environment_matches(frame, context, material)
	if context_changed:
		_clear_cursor_preview()
	_hover_epoch += 1
	_hover_request = {
		"center": center, "frame": frame, "context": context,
		"material": material.duplicate(), "estimate": estimate, "epoch": _hover_epoch,
	}
	_start_hover_sample()


func _start_hover_sample() -> void:
	if _hover_sample_job != null or _hover_request.is_empty():
		return
	if _edit != null or _stroke_active:
		_hover_request = {}
		return
	var request := _hover_request
	_hover_request = {}
	var context: VoxelFrame.EditContext = request["context"]
	var job := _build_sample_job(request["frame"], request["center"], context, request["material"], request["estimate"])
	job.request_epoch = request["epoch"]
	_hover_sample_job = job
	_hover_sample_operation_id = State.begin_operation("Sampling spray", job.local_estimate, false, self)
	job.worker_task_id = WorkerThreadPool.add_task(job.run, false, "Spray sample")


func _pump_hover_sample() -> void:
	_reap_hover_jobs()
	var job: SpraySamplingJob = _hover_sample_job
	if job != null and WorkerThreadPool.is_task_completed(job.worker_task_id):
		WorkerThreadPool.wait_for_task_completion(job.worker_task_id)
		job.worker_task_id = -1
		_hover_sample_job = null
		State.finish_operation(_hover_sample_operation_id)
		_hover_sample_operation_id = 0
		if job.checkpoint(0) and _edit == null and not _stroke_active:
			_install_hover(job)
	_start_hover_sample()


func _install_hover(job: SpraySamplingJob) -> void:
	if job.request_epoch <= _hover_installed_epoch:
		return
	var frame := State.get_current_voxel_frame()
	if frame == null or frame != job.source_frame:
		return
	var context := State.drawing_context()
	if context.axes != job.axes or context.origin_twice != job.origin_twice or not _same_selection(context.selection, job.selection) \
			or context.slice_axis != job.slice_axis or context.slice_index != job.slice_index or context.slice_count != job.slice_count:
		return
	if job.material != State.current_material:
		return
	if not _witness_holds(job.witness, frame) and not _cells_hold(frame, job.cells):
		_invalidate_batch()
		return
	var witness := job.witness
	if not _witness_holds(witness, frame):
		witness = {}
	_adopt_batch(frame, job.center, context, job.material, job.cells, witness, job.preview_payload)
	_commit_sample_state(job)
	_remember_selection_index(job.selection, job.built_selection_index)
	last_index_builds = job.index_builds
	last_index_grid_reads = job.index_grid_reads
	last_index_build_slots = job.index_build_slots
	last_selection_builds = job.selection_builds
	last_row_ops = job.row_ops
	last_footprint_visits = job.footprint_visits
	_hover_installed_epoch = job.request_epoch


func _cells_hold(frame: VoxelFrame, cells: Array[Vector3i]) -> bool:
	for cell in cells:
		if not frame.has(cell):
			return false
	return true


func _make_batch_token(frame: VoxelFrame, center: Vector3i, context: VoxelFrame.EditContext) -> BatchToken:
	var token := BatchToken.new()
	token.center = center
	token.frame = frame
	token.axes = context.axes
	token.origin_twice = context.origin_twice
	token.selection = context.selection
	token.slice_axis = context.slice_axis
	token.slice_index = context.slice_index
	token.slice_count = context.slice_count
	return token


func _adopt_batch(frame: VoxelFrame, center: Vector3i, context: VoxelFrame.EditContext, material: PackedFloat32Array, cells: Array[Vector3i], witness := {}, payload = null) -> void:
	_batch_center = center
	_batch_frame = frame
	_batch_material = material.duplicate()
	_batch_axes = context.axes
	_batch_origin = context.origin_twice
	_batch_selection = context.selection
	_batch_slice_axis = context.slice_axis
	_batch_slice_index = context.slice_index
	_batch_slice_count = context.slice_count
	_batch_token = _make_batch_token(frame, center, context)
	_batch_cells = cells
	_batch_payload = payload
	if witness.is_empty():
		_snapshot_batch_chunks(frame)
	else:
		_batch_chunks = witness
	_batch_version += 1
	_show_spots(cells)


func _witness_holds(witness: Dictionary, frame: VoxelFrame) -> bool:
	for location in witness:
		var entry: Array = witness[location]
		var chunk: VoxelFrame.Chunk = frame.chunks.get(location)
		if chunk == null or chunk != entry[0] or chunk.voxel_revision != entry[1]:
			return false
	return true


func _cancel_hover_sample() -> void:
	_hover_request = {}
	if _hover_sample_job:
		_hover_sample_job.cancel()
		_retired_hover_jobs.append(_hover_sample_job)
		_hover_sample_job = null
	State.finish_operation(_hover_sample_operation_id)
	_hover_sample_operation_id = 0


func _teardown_hover_sample() -> void:
	_cancel_hover_sample()
	for job in _retired_hover_jobs:
		job.wait_for_worker()
	_retired_hover_jobs.clear()


func _reap_hover_jobs() -> void:
	for job in _retired_hover_jobs.duplicate():
		if not WorkerThreadPool.is_task_completed(job.worker_task_id):
			continue
		job.wait_for_worker()
		_retired_hover_jobs.erase(job)


func _batch_matches(context: VoxelFrame.EditContext) -> bool:
	return context.axes == _batch_axes and context.origin_twice == _batch_origin and context.slice_axis == _batch_slice_axis and context.slice_index == _batch_slice_index and context.slice_count == _batch_slice_count and _same_selection(context.selection, _batch_selection)


func _batch_key_matches(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, material: PackedFloat32Array) -> bool:
	return center == _batch_center and _batch_environment_matches(frame, context, material)


func _batch_environment_matches(frame: VoxelFrame, context: VoxelFrame.EditContext, material: PackedFloat32Array) -> bool:
	return frame == _batch_frame and material == _batch_material and _batch_matches(context)


func _batch_holds(frame: VoxelFrame) -> bool:
	for location in _batch_chunks:
		var entry: Array = _batch_chunks[location]
		var chunk: VoxelFrame.Chunk = frame.chunks.get(location)
		if chunk == null or chunk != entry[0] or chunk.voxel_revision != entry[1]:
			return _revalidate_batch(frame)
	return true


func _revalidate_batch(frame: VoxelFrame) -> bool:
	for cell in _batch_cells:
		if not frame.has(cell):
			return false
	_snapshot_batch_chunks(frame)
	return true


func _snapshot_batch_chunks(frame: VoxelFrame) -> void:
	_batch_chunks = {}
	for cell in _batch_cells:
		var location := VoxelFrame.chunk_position(cell)
		if _batch_chunks.has(location):
			continue
		var chunk: VoxelFrame.Chunk = frame.chunks.get(location)
		if chunk != null:
			_batch_chunks[location] = [chunk, chunk.voxel_revision]


func _apply_batch() -> void:
	if _batch_cells.is_empty():
		return
	_queue_centers(_batch_cells)


func _apply_offered() -> void:
	_cancel_hover_sample()
	var shown := _installed_cells()
	if not shown.is_empty() and _shown_owned_by_press(_installed_token()) and _offered_cells_valid(shown):
		if is_same(shown, _shown_spots) and not _batch_cells.is_empty():
			_queue_centers(_batch_cells)
			return
		var cells: Array[Vector3i] = []
		cells.assign(shown.keys())
		_queue_centers(cells)
		return
	var pick := _last_pick
	if pick != null and pick.hit != VoxelPicking.NONE and _source_frame != null and _edit_context != null:
		var selection_index := _cached_selection_index(_edit_context.selection)
		var estimate := SpraySampler.work_estimate(_source_frame, pick.hit, _paint_settings.spray_size, _paint_settings.spot_diameter, _edit_context.selection, _paint_settings.speed, selection_index)
		last_work_estimate = estimate
		if estimate > INLINE_SAMPLE_LIMIT:
			_accept_intent(pick.hit, _source_frame, _edit_context, _stroke_material, estimate)
			return
		_ensure_batch(pick.hit, _source_frame, _edit_context, _stroke_material)
	_apply_batch()


func _installed_cells() -> Dictionary:
	if not has_node("Cursor"):
		return {}
	return $Cursor.installed_cells()


func _installed_token() -> Variant:
	if not has_node("Cursor"):
		return null
	return $Cursor.installed_token()


func _shown_owned_by_press(token: Variant) -> bool:
	if not (token is BatchToken):
		return false
	var owner := token as BatchToken
	var pick := _last_pick
	if pick == null or pick.hit == VoxelPicking.NONE:
		return false
	if owner.center != pick.hit or owner.frame != _source_frame or _edit_context == null:
		return false
	return owner.axes == _edit_context.axes and owner.origin_twice == _edit_context.origin_twice and owner.slice_axis == _edit_context.slice_axis and owner.slice_index == _edit_context.slice_index and owner.slice_count == _edit_context.slice_count and _same_selection(owner.selection, _edit_context.selection)


func _offered_cells_valid(shown: Dictionary) -> bool:
	var frame := _source_frame if _stroke_active and _source_frame != null else State.get_current_voxel_frame()
	var context := _edit_context if _stroke_active and _edit_context != null else State.drawing_context()
	if frame == null or context == null:
		return false
	if is_same(shown, _shown_spots):
		if _witness_holds(_shown_witness, frame):
			return true
		if not _revalidate_batch(frame):
			return false
		_shown_witness = _batch_chunks
		return true
	for cell in shown:
		if not frame.has(cell):
			return false
		if not context.selection.is_empty() and not context.selection.has(cell):
			return false
	return true


func _clear_cursor_preview() -> void:
	if has_node("Cursor"):
		$Cursor.show_selection(null)
	_preview_active = false
	_preview_version = -1
	_shown_spots = {}
	_shown_witness = {}


func _build_sample_job(frame: VoxelFrame, center: Vector3i, context: VoxelFrame.EditContext, material: PackedFloat32Array, estimate: int, spot_size := -1, search_size := -1, speed := -1) -> SpraySamplingJob:
	var use_spot: int = _paint_settings.spot_diameter if spot_size < 0 else spot_size
	var use_search: int = _paint_settings.spray_size if search_size < 0 else search_size
	var use_speed: int = _paint_settings.speed if speed < 0 else speed
	var job := SpraySamplingJob.new()
	var locations := SpraySampler.capture_chunks(center, use_search, use_spot, context.axes, context.origin_twice)
	job.frame = frame.copy_chunks(locations)
	job.capture_chunk_count = job.frame.chunks.size()
	last_capture_chunks = job.capture_chunk_count
	job.source_frame = frame
	job.center = center
	job.axes = context.axes
	job.origin_twice = context.origin_twice
	job.selection = context.selection
	job.slice_axis = context.slice_axis
	job.slice_index = context.slice_index
	job.slice_count = context.slice_count
	job.material = material.duplicate()
	job.spot_size = use_spot
	job.search_size = use_search
	job.speed = use_speed
	job.sample_state = _rng.state
	job.rng_epoch = _rng_epoch
	job.shape_cache = _shape_cache
	job.local_estimate = estimate
	job.selection_index = _cached_selection_index(context.selection)
	return job


func _commit_sample_state(job: SpraySamplingJob) -> void:
	if job.rng_epoch != _rng_epoch:
		return
	_rng.state = job.result_state
	_rng_epoch += 1


func _sample(center: Vector3i, frame: VoxelFrame, context: VoxelFrame.EditContext, rng: RandomNumberGenerator = null, material = null, spot_size := -1, search_size := -1, speed := -1) -> Array[Vector3i]:
	var use_rng: RandomNumberGenerator = _rng if rng == null else rng
	var use_material: PackedFloat32Array = _batch_material if material == null else material
	var use_spot: int = _paint_settings.spot_diameter if spot_size < 0 else spot_size
	var use_search: int = _paint_settings.spray_size if search_size < 0 else search_size
	var use_speed: int = _paint_settings.speed if speed < 0 else speed
	var report := {}
	var selection_index := _cached_selection_index(context.selection)
	var cells := SpraySampler.sample(center, frame, context, use_spot, use_search, use_speed, use_rng, use_material, _shape_cache, null, report, selection_index)
	cells = SpraySampler.in_slice(cells, context.slice_axis, context.slice_index, context.slice_count)
	last_index_builds = report.get("index_builds", 0)
	last_index_grid_reads = report.get("index_grid_reads", 0)
	last_index_build_slots = report.get("index_build_slots", 0)
	last_selection_builds = report.get("selection_builds", 0)
	last_row_ops = report.get("row_ops", 0)
	last_footprint_visits = report.get("footprint_visits", 0)
	_remember_selection_index(context.selection, report.get("selection_index"))
	if rng == null:
		_rng_epoch += 1
	return cells


func _candidates(center: Vector3i, local: Array[Vector3i], search_size := -1) -> Array[Vector3i]:
	var size: int = _paint_settings.spray_size if search_size < 0 else search_size
	return SpraySampler.candidate_cells(center, local, size)


func _footprints(spots: Array[Vector3i], local: Array[Vector3i], spot_size := -1, material = null, job: VoxelFrame.EditJob = null) -> Dictionary:
	var use_spot: int = _paint_settings.spot_diameter if spot_size < 0 else spot_size
	var use_material: PackedFloat32Array = _batch_material if material == null else material
	return SpraySampler.footprints(spots, local, use_spot, use_material, _shape_cache, job)


func _spot_offsets(diameter: int) -> Array[Vector3i]:
	return SpraySampler.offsets(_shape_cache, diameter)


func _show_spots(cells: Array[Vector3i]) -> void:
	if cells.is_empty():
		_preview_active = false
		_preview_version = -1
		_shown_spots = {}
		_shown_witness = {}
		$Cursor.show_voxels({}, VoxelFrame.material_color(_batch_material), false, 0, false)
		return
	$Cursor.set_brush_material(_batch_material)
	if _preview_active and _preview_version == _batch_version:
		return
	var color := VoxelFrame.material_color(_batch_material)
	if _batch_payload != null:
		_preview_active = true
		_preview_version = _batch_version
		_shown_spots = _batch_payload.spots
		_shown_witness = _batch_chunks
		_batch_payload.token = _batch_token
		$Cursor.submit_prepared(_batch_payload)
		return
	var spots := {}
	for cell in cells:
		spots[cell] = color
	spots.make_read_only()
	_preview_active = true
	_preview_version = _batch_version
	_shown_spots = spots
	_shown_witness = _batch_chunks
	$Cursor.show_voxels(spots, color, false, 0, false, _batch_token)


func _build_job() -> BrushJob:
	var job := super._build_job()
	job.previous_center = Vector3i.MAX
	job.centers_are_final = true
	return job
