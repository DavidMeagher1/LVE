extends VoxelRenderer


var calls: Array[Dictionary] = []
var worker_frames := {}
var cache_frames := {}
var available_frames := {}
var install_frames := {}
var launch_frames := {}
var launch_keys := {}
var consume_frames := {}
var starved_calls := 0
var max_call_us := 0
var total_call_us := 0
var max_ready := 0
var launched_keys := {}
var pool_trips: Array[int] = []
var _call_frame := 0
var _call_started_us := 0
var _call_consumed := false
var _call_launched := false
var _ready_at_entry: Array = []
var _mark_frame := 0
var _trip_task_id := -1
var _trip_start_frame := 0
var _trip_sink := 0


func mark() -> void:
	_mark_frame = Engine.get_process_frames()


func _now() -> int:
	return Engine.get_process_frames() - _mark_frame


func reset_probe() -> void:
	calls = []
	worker_frames = {}
	cache_frames = {}
	available_frames = {}
	install_frames = {}
	launch_frames = {}
	launch_keys = {}
	consume_frames = {}
	pool_trips = []
	starved_calls = 0
	max_call_us = 0
	total_call_us = 0
	max_ready = 0
	launched_keys = {}
	mark()


func _update_surfaces() -> void:
	_call_frame = _now()
	_call_started_us = Time.get_ticks_usec()
	_call_consumed = false
	_call_launched = false
	_ready_at_entry = []
	_tick_pool_trip()
	for key in launched_keys:
		if not available_frames.has(key) and _surface_cache.has(key):
			available_frames[key] = _call_frame
	for key in _surface_jobs:
		var job: VoxelMeshBuilder = _surface_jobs[key]
		if WorkerThreadPool.is_task_completed(job.worker_task_id):
			_ready_at_entry.append(key)
			if not worker_frames.has(key):
				worker_frames[key] = _call_frame
	max_ready = maxi(max_ready, _ready_at_entry.size())
	super._update_surfaces()
	var elapsed := Time.get_ticks_usec() - _call_started_us
	total_call_us += elapsed
	max_call_us = maxi(max_call_us, elapsed)
	for key in _ready_at_entry:
		if not _surface_jobs.has(key) and not cache_frames.has(key):
			cache_frames[key] = _call_frame
	if not _call_consumed and not _call_launched and elapsed >= State.WORK_SLICE_US:
		starved_calls += 1
	calls.append({
		"frame": _call_frame,
		"us": elapsed,
		"ready": _ready_at_entry.size(),
		"consumed": _call_consumed,
		"launched": _call_launched,
	})


func _consume_inflight(chunk_location: Vector3i) -> bool:
	var consumed := super._consume_inflight(chunk_location)
	if consumed:
		_call_consumed = true
		if not consume_frames.has(chunk_location):
			consume_frames[chunk_location] = []
		consume_frames[chunk_location].append(_call_frame)
	return consumed


func _launch_surface(chunk_location: Vector3i, active_frame: VoxelFrame) -> void:
	var before = _inflight_surface_keys.get(chunk_location, null)
	super._launch_surface(chunk_location, active_frame)
	var after = _inflight_surface_keys.get(chunk_location, null)
	if after != null and after != before:
		_call_launched = true
		if not launch_frames.has(chunk_location):
			launch_frames[chunk_location] = []
			launch_keys[chunk_location] = []
		launch_frames[chunk_location].append(_call_frame)
		launch_keys[chunk_location].append(after)
		if launched_keys.has(after):
			launched_keys[after] = int(launched_keys[after]) + 1
		else:
			launched_keys[after] = 1


func _install(chunk_location: Vector3i, surface_key: PackedInt64Array, entry: Dictionary) -> void:
	super._install(chunk_location, surface_key, entry)
	var shown = _displayed_surface_keys.get(chunk_location, null)
	if shown != null and shown == surface_key:
		if not install_frames.has(chunk_location):
			install_frames[chunk_location] = []
		install_frames[chunk_location].append(_call_frame)


func _tick_pool_trip() -> void:
	if _trip_task_id >= 0:
		if WorkerThreadPool.is_task_completed(_trip_task_id):
			WorkerThreadPool.wait_for_task_completion(_trip_task_id)
			pool_trips.append(_call_frame - _trip_start_frame)
			_trip_task_id = -1
	if _trip_task_id < 0:
		_trip_start_frame = _call_frame
		_trip_task_id = WorkerThreadPool.add_task(_trip_run, false, "phase probe")


func _trip_run() -> void:
	_trip_sink += 1
