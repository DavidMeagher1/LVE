extends "res://tests/test.gd"


const PREVIEW := preload("res://Globals/Rendering/VoxelPreview.gd")


class GatedJob extends PREVIEW.PreviewJob:
	static var gate: Semaphore

	func run() -> void:
		gate.wait()
		super.run()


class GatedPreview extends PREVIEW:
	var installs := 0

	func _new_job() -> PreviewJob:
		return GatedJob.new()

	func _finish_preview() -> void:
		var before := mesh
		super._finish_preview()
		if mesh != null and mesh != before:
			installs += 1


class Token extends RefCounted:
	pass


var preview
var cached_mesh: Mesh
var _variant_base := 0


func _ready() -> void:
	timeout = 30.0
	test("a coalescing cursor installs a completed snapshot before release", _coalesced_installs, "preview_coalesce_installs")
	test("a coalescing cursor settles on the newest exact snapshot", _coalesced_settles, "preview_coalesce_settles")
	test("a superseded strict snapshot never installs", _strict_latest_only, "preview_strict_latest")
	test("a clear hides a running coalescing cursor and no worker resurrects it", _clear_hides, "preview_clear_hides")
	test("a newer cached exact surface survives an older worker", _cache_beats_worker, "preview_cache_holds")
	test("the preview exposes the exact installed cells", _installed_cells_exposed, "preview_installed_cells")
	test("an identical settings or document change keeps the running worker", _settings_change_keeps, "preview_settings_keeps")
	test("a changed shading cancels the running worker and queues a new snapshot", _settings_change_replaces, "preview_settings_replaces")
	test("a cache hit reports the token of the request that asked for it", _cache_hit_token, "preview_cache_token")
	test("a cache hit keeps the next request in step", _cache_hit_dedupe, "preview_cache_dedupe")
	test("a clear or a cancel drops the installed token", _token_clear, "preview_token_clear")


func before_test() -> void:
	State.stop()
	State.document = VoxelDocument.new()
	State.clear_selection()
	State.symmetry_axes = 0
	State.symmetry_origin = State.DEFAULT_SYMMETRY_ORIGIN
	State.document._bounds_dirty = true
	_variant_base += 4096
	GatedJob.gate = Semaphore.new()


func after_test() -> void:
	if preview != null and is_instance_valid(preview):
		if GatedJob.gate != null:
			for i in 32:
				GatedJob.gate.post()
		preview.free()
		preview = null
	GatedJob.gate = null


func _variant(index: int) -> Dictionary:
	var cells := {}
	var start := _variant_base + index * 32
	for i in 16:
		cells[Vector3i(start + i, 0, 0)] = Color.WHITE
	return cells


func _same_keys(first: Dictionary, second: Dictionary) -> bool:
	if first.size() != second.size():
		return false
	for key in first:
		if not second.has(key):
			return false
	return true


func _aabb_of(cells: Dictionary) -> AABB:
	var min_corner := Vector3(INF, INF, INF)
	var max_corner := Vector3(-INF, -INF, -INF)
	for cell in cells:
		min_corner = min_corner.min(Vector3(cell) - Vector3(0.5, 0.5, 0.5))
		max_corner = max_corner.max(Vector3(cell) + Vector3(0.5, 0.5, 0.5))
	return AABB(min_corner, max_corner - min_corner)


func _aabb(instance) -> AABB:
	return instance.mesh.get_aabb()


func _await_installs(instance, count: int) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while instance.installs < count and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _await_settled(instance) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while not instance.is_settled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _await_discard(instance) -> void:
	var deadline := Time.get_ticks_msec() + 4000
	while Time.get_ticks_msec() < deadline:
		if instance._pending_cells.is_empty() and instance._preview_job != null:
			return
		await get_tree().process_frame


func _coalesced_installs() -> void:
	step("Given a coalescing cursor and a blocked slow worker", func():
		preview = GatedPreview.new()
		preview.coalesce_requests = true
		add_child(preview)
		preview.show_voxels(_variant(0), Color.RED, false, 0, false)
		expect(preview._preview_job != null, "the first snapshot runs on a worker")
		expect(preview.installs == 0, "the blocked worker installed nothing")
	)
	step("When the pointer changes the request every frame while the worker runs", func():
		for index in range(1, 6):
			preview.show_voxels(_variant(index), Color.RED, false, 0, false)
		expect(preview._preview_job != null, "the running worker is not cancelled")
		expect(not preview._pending_cells.is_empty(), "the newest snapshot waits")
		expect(preview.installs == 0, "no snapshot installed yet")
	)
	step("When the blocked worker finishes", func():
		GatedJob.gate.post()
	)
	await _await_installs(preview, 1)
	step("Then the completed snapshot reached the screen before any release", func():
		expect(preview.installs >= 1, "the cursor installed geometry during the change")
		expect(preview.mesh != null and preview.visible, "the cursor shows the installed snapshot")
	)


func _coalesced_settles() -> void:
	step("Given a coalescing cursor that changed its request every frame", func():
		preview = GatedPreview.new()
		preview.coalesce_requests = true
		add_child(preview)
		preview.show_voxels(_variant(0), Color.RED, false, 0, false)
		for index in range(1, 6):
			preview.show_voxels(_variant(index), Color.RED, false, 0, false)
	)
	step("When every blocked worker is released", func():
		for i in 12:
			GatedJob.gate.post()
	)
	await _await_settled(preview)
	step("Then the cursor holds the newest exact snapshot", func():
		expect(preview.is_settled(), "the cursor settles after the pointer stops")
		expect(preview.visible, "the newest snapshot is visible")
		expect(_aabb(preview).position.is_equal_approx(_aabb_of(_variant(5)).position), "the final mesh sits on the newest cells")
		expect(_aabb(preview).size.is_equal_approx(_aabb_of(_variant(5)).size), "the final mesh spans the newest cells")
		expect(_same_keys(preview.installed_cells(), _variant(5)), "the installed cells are the newest snapshot")
	)


func _strict_latest_only() -> void:
	step("Given a strict preview with a blocked worker", func():
		preview = GatedPreview.new()
		add_child(preview)
		expect(preview.coalesce_requests == false, "the strict path is the default")
		preview.show_voxels(_variant(0), Color.RED, false, 0, false)
		expect(preview._preview_job != null, "the first strict snapshot runs on a worker")
	)
	step("When a newer strict request supersedes the running worker", func():
		preview.show_voxels(_variant(1), Color.RED, false, 0, false)
		GatedJob.gate.post()
	)
	await _await_discard(preview)
	step("Then the superseded snapshot never installed", func():
		expect(preview.installs == 0, "a superseded strict snapshot is discarded")
	)
	step("When the newest snapshot's worker finishes", func():
		GatedJob.gate.post()
	)
	await _await_installs(preview, 1)
	step("Then only the newest strict snapshot installed", func():
		expect(preview.installs == 1, "the newest strict request wins alone")
		expect(_aabb(preview).position.is_equal_approx(_aabb_of(_variant(1)).position), "the installed mesh is the newest snapshot")
	)


func _clear_hides() -> void:
	step("Given a coalescing cursor with a blocked worker", func():
		preview = GatedPreview.new()
		preview.coalesce_requests = true
		add_child(preview)
		preview.show_voxels(_variant(0), Color.RED, false, 0, false)
		expect(preview._preview_job != null, "the snapshot runs on a worker")
	)
	step("When the cursor clears before the worker finishes", func():
		preview.show_voxels({}, Color.RED, false, 0, false)
		GatedJob.gate.post()
	)
	await _await_settled(preview)
	step("Then the clear stays hidden and no worker resurrects the cursor", func():
		expect(not preview.visible, "the cleared cursor stays hidden")
		expect(preview.installs == 0, "no surface installs after a clear")
		expect(preview.installed_cells().is_empty(), "the clear empties the installed cells")
		expect(preview.is_settled(), "the clear leaves no pending request")
	)


func _cache_beats_worker() -> void:
	var small := {Vector3i(_variant_base + 2048, 0, 0): Color.WHITE, Vector3i(_variant_base + 2049, 0, 0): Color.WHITE}
	step("Given a small uniform surface that installs and caches", func():
		preview = PREVIEW.new()
		preview.coalesce_requests = true
		add_child(preview)
		preview.show_voxels(small, Color.RED, false, 0, false)
	)
	await _await_settled(preview)
	step("Then the small surface is cached", func():
		expect(preview.mesh != null and preview.is_settled(), "the small surface installed")
		cached_mesh = preview.mesh
	)
	step("When a slow wide worker starts and the cached surface returns", func():
		preview.show_voxels(_variant(0), Color.RED, false, 0, false)
		expect(preview._preview_job != null, "the wide batch runs on a worker")
		preview.show_voxels(small, Color.RED, false, 0, false)
		expect(preview.mesh == cached_mesh, "the newer exact surface returns from the cache at once")
	)
	await _await_settled(preview)
	step("Then the older worker cannot overwrite the newer cached surface", func():
		expect(preview.mesh == cached_mesh, "the older worker result is discarded")
		expect(preview._pending_cells.is_empty(), "the cache hit leaves no pending request")
	)


func _installed_cells_exposed() -> void:
	step("Given a coalescing preview with its first snapshot released", func():
		preview = GatedPreview.new()
		preview.coalesce_requests = true
		add_child(preview)
		GatedJob.gate.post()
		preview.show_voxels(_variant(0), Color.RED, false, 0, false)
	)
	await _await_installs(preview, 1)
	step("Then the installed cells are the exact immutable requested cells", func():
		expect(preview.installed_cells().is_read_only(), "the installed cells are immutable")
		expect(preview.installed_cells().size() == 16, "the installed cells hold the whole snapshot")
		expect(_same_keys(preview.installed_cells(), _variant(0)), "the installed cells are the requested cells")
	)
	step("When a newer snapshot is requested but its worker still runs", func():
		preview.show_voxels(_variant(1), Color.RED, false, 0, false)
		expect(preview._preview_job != null, "the newer snapshot runs on a worker")
		expect(_same_keys(preview.installed_cells(), _variant(0)), "the installed cells stay the displayed A")
		expect(not _same_keys(preview._requested_cells, _variant(0)), "the requested cells are the newer B")
	)


func _settings_change_keeps() -> void:
	step("Given a coalescing preview with a blocked worker", func():
		preview = GatedPreview.new()
		preview.coalesce_requests = true
		add_child(preview)
		preview.show_voxels(_variant(0), Color.RED, false, 0, false)
		expect(preview._preview_job != null, "the worker runs")
	)
	step("When the model settings change but the request is identical", func():
		State.model_settings_changed.emit()
		expect(preview._preview_job != null, "the unchanged request keeps the running worker")
	)
	step("When a document change repeats the identical request", func():
		State.document_changed.emit()
		expect(preview._preview_job != null, "the repeated document change keeps the running worker")
	)
	step("When the blocked worker finishes", func():
		GatedJob.gate.post()
	)
	await _await_installs(preview, 1)
	step("Then the preview still installed its surface", func():
		expect(preview.installs >= 1, "an unchanged settings change never drops the preview")
		expect(preview.mesh != null and preview.visible, "the preview stays visible")
		expect(_same_keys(preview.installed_cells(), _variant(0)), "the installed cells are the requested snapshot")
	)


func _settings_change_replaces() -> void:
	step("Given a coalescing preview with a blocked worker", func():
		preview = GatedPreview.new()
		preview.coalesce_requests = true
		add_child(preview)
		preview.show_voxels(_variant(0), Color.RED, false, 0, false)
		expect(preview._preview_job != null, "the worker runs")
	)
	step("When the smooth normals change", func():
		State.document.smooth_normals = true
		State.model_settings_changed.emit()
		expect(preview._preview_job._cancel_requested, "the changed request cancels the old worker")
		expect(not preview._pending_cells.is_empty(), "the changed request queues a new snapshot")
	)


func _cache_hit_token() -> void:
	var cells := _variant(0)
	var first := Token.new()
	var second := Token.new()
	step("Given a surface that installs and caches with its request token", func():
		preview = PREVIEW.new()
		add_child(preview)
		preview.show_voxels(cells, Color.RED, false, 0, false, first)
	)
	await _await_settled(preview)
	step("Then the installed token is the first request", func():
		expect(preview.installed_token() == first, "the first install reports its own token")
		cached_mesh = preview.mesh
	)
	step("When a second request for the same cells hits the mesh cache", func():
		preview._clear_request()
		preview.show_voxels(cells, Color.RED, false, 0, false, second)
	)
	step("Then the cached surface reports the second request token", func():
		expect(preview.mesh == cached_mesh, "the surface comes from the cache")
		expect(preview.installed_token() == second, "the cache hit reports the request that asked for it")
		expect(is_same(preview.installed_cells(), preview._requested_cells), "the requested cells are the installed cells")
		expect(_same_keys(preview.installed_cells(), cells), "the cached cells hold the requested cells")
	)


func _cache_hit_dedupe() -> void:
	var first := _variant(0)
	var second := _variant(1)
	step("Given two cached surfaces", func():
		preview = PREVIEW.new()
		add_child(preview)
		preview.show_voxels(first, Color.RED, false, 0, false)
	)
	await _await_settled(preview)
	step("When the second surface installs and the first one repeats", func():
		preview.show_voxels(second, Color.RED, false, 0, false)
	)
	await _await_settled(preview)
	step("Then a repeat of the second surface installs it again", func():
		preview.show_voxels(first, Color.RED, false, 0, false)
		preview.show_voxels(second, Color.RED, false, 0, false)
		expect(_same_keys(preview.installed_cells(), second), "the installed surface follows the newest request")
	)


func _token_clear() -> void:
	var token := Token.new()
	step("Given an installed surface with a request token", func():
		preview = PREVIEW.new()
		add_child(preview)
		preview.show_voxels({Vector3i(_variant_base + 3000, 0, 0): Color.WHITE}, Color.RED, false, 0, false, token)
	)
	await _await_settled(preview)
	step("Then the token belongs to the installed surface", func():
		expect(preview.installed_token() == token, "the installed surface reports its token")
	)
	step("When the preview clears", func():
		preview.show_voxels({}, Color.RED)
	)
	step("Then the clear drops the token", func():
		expect(preview.installed_token() == null, "a clear drops the installed token")
		expect(preview.installed_cells().is_empty(), "a clear drops the installed cells")
	)
	step("When a blocked request clears before its worker installs", func():
		preview.free()
		preview = GatedPreview.new()
		add_child(preview)
		preview.show_voxels(_variant(0), Color.RED, false, 0, false, token)
		preview.show_voxels({}, Color.RED)
		GatedJob.gate.post()
	)
	await _await_settled(preview)
	step("Then the cancelled request installs no token", func():
		expect(preview.installed_token() == null, "the cancelled request installs no token")
		expect(preview.installed_cells().is_empty(), "the cancelled request installs no cells")
	)
