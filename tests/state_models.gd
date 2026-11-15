extends "res://tests/test.gd"

## Checks the operation registry and the settings store as stand-alone models.

const OperationRegistry = preload("res://Globals/State/OperationRegistry.gd")
const SettingsStore = preload("res://Globals/State/SettingsStore.gd")


# A job that keeps the worker busy for a few frames, so the pump loop runs.
class WaitJob extends VoxelFrame.EditJob:
	var reached := 0

	func run() -> void:
		stage("Testing a job", 2)
		OS.delay_msec(30)
		reached = 1
		checkpoint(1)
		OS.delay_msec(30)
		reached = 2
		checkpoint(2)


var registry: OperationRegistry
var store: SettingsStore
var operation_id := 0
var owner_node: Node
var job: WaitJob
var first: VoxelDocument
var second: VoxelDocument
var third: VoxelDocument
var documents: Array[VoxelDocument]
var settings_path := ""
var callback_count := 0
var frames := 0


func _ready() -> void:
	test("an operation starts, updates, and finishes", _operation_lifecycle, "operation_lifecycle")
	test("a foreground operation blocks an edit", _foreground_busy, "operation_foreground")
	test("a foreground operation does not block its owner", _owner_not_blocked, "operation_owner")
	test("a cancel request calls the owner callback once", _cancel, "operation_cancel")
	test("run_edit_job joins its worker", _join, "operation_job")
	test("the settings store writes through a temporary file", _settings_write, "settings_write")
	test("the settings store keeps a corrupt file", _settings_corrupt, "settings_corrupt")
	test("the settings store remembers the session paths", _settings_session, "settings_session")


func before_test() -> void:
	callback_count = 0
	frames = 0
	operation_id = 0
	owner_node = null
	job = null
	first = null
	second = null
	third = null
	documents = []
	settings_path = "user://state_models_%s.cfg" % Time.get_ticks_usec()
	_remove_file(settings_path)
	registry = OperationRegistry.new()
	registry.tree = get_tree()
	store = SettingsStore.new()
	store.tree = get_tree()
	store.settings_path = settings_path


func after_test() -> void:
	while registry != null and registry.get_activity() != null:
		registry.finish_operation(registry.get_activity().id)
	_remove_file(settings_path)
	_remove_file(settings_path + ".tmp")


func _remove_file(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _on_cancel() -> void:
	callback_count += 1


func _on_frame() -> void:
	frames += 1


func _operation_lifecycle() -> void:
	step("Given an operation registry and one operation", func():
		operation_id = registry.begin_operation("Building", 10)
	)
	step("Then the operation is tracked", func():
		expect(registry.has_operation(operation_id), "the new operation is tracked")
		expect(registry.get_activity().label == "Building", "the label is the begin label")
		expect(not registry.get_activity().foreground, "a plain operation is in the background")
	)
	step("When the owner updates its progress", func():
		registry.update_operation(operation_id, 4, 10, "Merging", "four of ten")
	)
	step("Then the progress is stored", func():
		var operation := registry.get_activity()
		expect(operation.completed == 4, "the completed count updates")
		expect(operation.total == 10, "the total updates")
		expect(operation.phase == "Merging", "the phase is diagnostic")
		expect(operation.detail == "four of ten", "the detail is diagnostic")
	)
	step("When the operation finishes", func():
		registry.finish_operation(operation_id)
	)
	step("Then no operation remains", func():
		expect(not registry.has_operation(operation_id), "the finished operation leaves the list")
		expect(registry.get_activity() == null, "no activity remains")
		expect(registry.activity_elapsed_ms() == 0, "the activity clock resets")
	)


func _foreground_busy() -> void:
	step("Given a foreground operation", func():
		operation_id = registry.begin_operation("Scaling", 100, true, self)
	)
	step("Then another requester sees a busy edit", func():
		expect(registry.edit_busy(), "a foreground operation blocks an anonymous requester")
		expect(registry.edit_busy(main), "a foreground operation blocks another node")
	)
	step("When the foreground operation finishes", func():
		registry.finish_operation(operation_id)
		operation_id = registry.begin_operation("Building surfaces", -1, false, self)
	)
	step("Then a background operation does not block", func():
		expect(not registry.edit_busy(), "a background operation does not block an edit")
	)


func _owner_not_blocked() -> void:
	step("Given a foreground operation with an owner", func():
		owner_node = Node.new()
		operation_id = registry.begin_operation("Selecting", 10, true, owner_node)
	)
	step("Then the owner can still edit", func():
		expect(not registry.edit_busy(owner_node), "the owner is not blocked by its own operation")
		expect(registry.edit_busy(), "another requester is blocked")
	)
	step("When the owner is freed", func():
		owner_node.free()
		registry.update()
	)
	step("Then the stale operation is finished", func():
		expect(not registry.has_operation(operation_id), "the freed owner releases the operation")
	)


func _cancel() -> void:
	step("Given a cancellable foreground operation", func():
		operation_id = registry.begin_operation("Exporting", 10, true, self, _on_cancel)
	)
	step("Then the owner can cancel it once", func():
		expect(registry.get_activity().can_cancel(), "the registered callback makes the operation cancellable")
		expect(registry.cancel_operation(operation_id), "the first cancel request is accepted")
		expect(callback_count == 1, "the cancel callback runs once")
		expect(registry.get_activity().cancel_requested, "the cancellation stays pending")
		expect(not registry.cancel_operation(operation_id), "a second cancel request is refused")
		expect(callback_count == 1, "the refused request calls nothing")
		expect(registry.cancel_activity(), "a pending cancellation still owns Escape")
	)
	step("When the owner finishes the operation", func():
		registry.finish_operation(operation_id)
	)
	step("Then no operation remains", func():
		expect(registry.get_activity() == null, "the finished operation leaves the list")
	)


func _join() -> void:
	job = WaitJob.new()
	operation_id = registry.begin_operation("Testing a job", 2, true, self)
	await registry.run_edit_job(job, operation_id, "State models", _on_frame)
	step("Then the worker is joined before the call returns", func():
		expect(job.reached == 2, "the worker completed its work")
		expect(job.worker_task_id == -1, "the worker handle is retired")
		expect(frames > 0, "the call pumped at least one frame")
		expect(registry.get_activity().phase == "Testing a job", "the progress reached the operation")
		expect(registry.has_operation(operation_id), "the owner still finishes the operation")
	)
	step("When the owner finishes the operation", func():
		registry.finish_operation(operation_id)
	)
	step("Then no operation remains", func():
		expect(registry.get_activity() == null, "the finished operation leaves the list")
	)


func _settings_write() -> void:
	step("Given a settings store with a temporary file", func():
		store.remember_document("res://sample.lve")
	)
	step("Then the value is written through a temporary file", func():
		expect(FileAccess.file_exists(settings_path), "the settings file exists")
		expect(not FileAccess.file_exists(settings_path + ".tmp"), "no temporary file remains")
		expect(store.last_document_path() == "res://sample.lve", "the stored path is read back")
	)
	step("When the document path is forgotten", func():
		store.forget_document()
	)
	step("Then the file keeps no document path", func():
		expect(store.last_document_path() == "", "the forgotten path is empty")
		expect(FileAccess.file_exists(settings_path), "the settings file remains")
	)


func _settings_corrupt() -> void:
	step("Given a settings file with invalid text", func():
		var file := FileAccess.open(settings_path, FileAccess.WRITE)
		expect(file != null, "the corrupt fixture opens")
		if file != null:
			file.store_string("[broken\n")
			file.close()
		store.remember_document("res://replacement.lve")
	)
	step("Then the store keeps the corrupt bytes", func():
		expect(FileAccess.get_file_as_string(settings_path) == "[broken\n", "the corrupt file keeps its bytes")
		expect(store.last_document_path() == "", "the unreadable file gives no path")
		expect(not FileAccess.file_exists(settings_path + ".tmp"), "the refused write leaves no temporary file")
	)


func _settings_session() -> void:
	step("Given three tabs where one has no save path", func():
		first = VoxelDocument.new()
		second = VoxelDocument.new()
		third = VoxelDocument.new()
		first.edit_save_path = "res://first.lve"
		second.edit_save_path = "res://second.lve"
		documents = [first, second, third]
		store.remember_session(documents, 1)
	)
	step("Then only the saved paths and the active index are stored", func():
		expect(store.last_tabs() == PackedStringArray(["res://first.lve", "res://second.lve"]), "the pathless tab is skipped")
		expect(store.last_tab_index() == 1, "the active tab maps to the saved list")
		expect(store.last_document_path() == "res://second.lve", "the active path is remembered")
	)
	step("When the active tab has no path", func():
		store.remember_session(documents, 2)
	)
	step("Then the stored active index still fits", func():
		expect(store.last_tab_index() == 1, "a pathless active tab keeps the stored index")
		expect(store.last_document_path() == "res://second.lve", "the last document path stays")
	)
	step("Then a test scene is not the application session", func():
		expect(not store.is_app_session(), "the injected tree is not the app session")
	)

