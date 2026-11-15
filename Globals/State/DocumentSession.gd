extends RefCounted

## The open documents and the animation playback.
##
## The session owns the tab list, the active document, and the playback state.
## It emits the document and playback signals. State forwards them and supplies
## the editor steps that an adoption needs through the hook callables.

## Emitted when the document is replaced.
signal document_changed()
## Emitted before the active document is replaced. Observers save their view
## state for the document that is still active.
signal document_deactivating()
## Emitted when [method set_document] creates a new document from a value that is
## not a [VoxelDocument].
signal document_created()
## Emitted when a document is saved to a path. The unsaved mark is already clear.
signal document_saved(document: VoxelDocument)
## Emitted before a document is encoded for a save or an autosave copy. Observers
## capture the active editor workspace into the active document.
signal workspace_capture_requested()
## Emitted when the frame list or a tag range changes.
signal frames_changed()
## Emitted when a frame property changes.
signal frame_changed()
## Emitted when a tag property changes.
signal tag_changed()
## Emitted when playback starts or stops. [param toggled_on] is the new state.
signal is_playing_toggled(toggled_on: bool)
## Emitted when a tab is added or removed.
signal tabs_changed()
## Emitted when the active tab changes.
signal active_tab_changed()
## Emitted when a save or an open changed the remembered paths. State stores the
## session in the settings file.
signal session_remember_requested()

## The animation playback state.
var playback := AnimationPlayback.new()
## The open documents, one per tab.
var tabs: Array[VoxelDocument] = []
## The index of the active tab.
var active_tab := 0

## Returns a copy of the palette for a new document. State supplies it, because
## the palette belongs to the material state.
var palette_provider := Callable()
## Returns [code]true[/code] while an open edit or a foreground operation blocks
## a tab switch. State supplies it.
var switch_blocked := Callable()
## Runs after [signal document_deactivating] and before the active document
## changes. State resets its material edit and cancels the open edit here.
var on_deactivated := Callable()
## Runs after the active document changes and before the tag and playback setup.
## State applies the current material here.
var on_installed := Callable()
## Runs after the adopted document signals. State emits its selection, history,
## and edit state signals here.
var on_adopted := Callable()

## The document of the active tab. A write replaces that tab's document.
var document: VoxelDocument:
	get:
		return _active_document
	set(value):
		set_document(value)

# The document of the active tab.
var _active_document: VoxelDocument
# Whether a document is being installed. It keeps adoption from marking the
# incoming document dirty.
var _adopting := false


func _init() -> void:
	playback.frame_changed.connect(frame_changed.emit)
	playback.is_playing_toggled.connect(is_playing_toggled.emit)
	playback.tag_changed.connect(tag_changed.emit)
	_active_document = VoxelDocument.new()
	# The startup document skips _adopt_document, so it needs the default tag.
	_active_document.add_tag("Default", 0, _active_document.frames.size() - 1)
	tabs.append(_active_document)
	playback.document = _active_document


## Returns a new empty document with the current default palette.
func new_document() -> VoxelDocument:
	var created := VoxelDocument.new()
	if palette_provider.is_valid():
		created.palette = palette_provider.call()
	return created


## Replaces the active tab's document. A value that is not a [VoxelDocument]
## creates a new empty document.
func set_document(value: VoxelDocument) -> void:
	var created := not (value is VoxelDocument)
	var next: VoxelDocument = value if not created else new_document()
	if next == _active_document:
		return
	if tabs.is_empty():
		tabs.append(next)
		active_tab = 0
	else:
		tabs[active_tab] = next
	_adopt_document(next)
	if created:
		document_created.emit()
	tabs_changed.emit()


## Adds one document as a tab and returns its index. A document that is already
## open returns its index.
func add_tab(value: VoxelDocument) -> int:
	var next: VoxelDocument = value if value is VoxelDocument else new_document()
	var existing := tabs.find(next)
	if existing >= 0:
		return existing
	tabs.append(next)
	tabs_changed.emit()
	return tabs.size() - 1


## Adds one document and makes it the active tab.
func open_tab(value: VoxelDocument) -> int:
	var index := add_tab(value)
	activate_tab(index)
	return index


## Captures the active editor workspace into [param captured] before it is
## encoded. Only the active document has live editor state. An inactive document
## keeps the state that its deactivation captured.
func capture_workspace(captured: VoxelDocument) -> void:
	if captured == null or captured == _active_document:
		workspace_capture_requested.emit()


## Records a saved document path in its tab and the session. It clears the
## unsaved mark and refreshes the tab strip.
func record_saved(saved: VoxelDocument, path: String) -> void:
	saved.file_path = path
	saved.edit_save_path = path
	saved.edit_dirty = false
	tabs_changed.emit()
	session_remember_requested.emit()
	document_saved.emit(saved)


## Records an opened document path in its tab and the session.
func record_opened(opened: VoxelDocument, path: String) -> void:
	opened.edit_save_path = path
	session_remember_requested.emit()


## Replaces every tab with [param documents] and activates [param index]. It
## restores a session in one step, without an empty startup tab.
func set_tabs(documents: Array[VoxelDocument], index: int = 0) -> void:
	if documents.is_empty():
		documents.append(new_document())
	tabs.clear()
	tabs.append_array(documents)
	active_tab = clampi(index, 0, documents.size() - 1)
	_adopt_document(tabs[active_tab])
	tabs_changed.emit()
	active_tab_changed.emit()


## Makes one tab active. Returns [code]false[/code] while an edit is open.
func activate_tab(index: int) -> bool:
	if index < 0 or index >= tabs.size() or index == active_tab:
		return false
	if _is_switch_blocked():
		return false
	_adopt_document(tabs[index])
	active_tab = index
	active_tab_changed.emit()
	return true


## Removes one tab. Returns [code]false[/code] while an edit is open.
func close_tab(index: int) -> bool:
	if index < 0 or index >= tabs.size():
		return false
	if _is_switch_blocked():
		return false
	var was_active := index == active_tab
	var closed := tabs[index]
	tabs.remove_at(index)
	if was_active:
		if tabs.is_empty():
			tabs.append(new_document())
		var next := mini(index, tabs.size() - 1)
		_adopt_document(tabs[next])
		active_tab = next
	elif index < active_tab:
		active_tab -= 1
	# UndoRedo is an Object, so free it with the tab. Empty the actions first.
	closed.edit_history.clear_history()
	closed.edit_history.free()
	closed.edit_history = null
	tabs_changed.emit()
	if was_active:
		active_tab_changed.emit()
	return true


## Returns [code]true[/code] while [method _adopt_document] replaces the active
## document. Adoption emits the content signals too, so a listener must not treat
## them as edits.
func is_adopting() -> bool:
	return _adopting


## Advances the playback by one time step. Call it once per frame.
func update(delta: float) -> void:
	playback.update(delta)


func _is_switch_blocked() -> bool:
	return switch_blocked.is_valid() and bool(switch_blocked.call())


# Installs one document as the active document. The caller keeps [member tabs]
# current. The frame, tag, selection, and history live on the document, so a
# switch restores them without a copy.
func _adopt_document(value: VoxelDocument) -> void:
	document_deactivating.emit()
	if on_deactivated.is_valid():
		on_deactivated.call()
	_adopting = true
	_active_document = value
	if on_installed.is_valid():
		on_installed.call()
	if _active_document.tags.is_empty():
		_active_document.add_tag("Default", 0, _active_document.frames.size() - 1)
	_active_document.edit_frame = clampi(_active_document.edit_frame, 0, _active_document.frames.size() - 1)
	_active_document.edit_tag = clampi(_active_document.edit_tag, -1, _active_document.tags.size() - 1)
	playback.document = _active_document
	playback.restore_playback()
	document_changed.emit()
	frames_changed.emit()
	frame_changed.emit()
	tag_changed.emit()
	_adopting = false
	if on_adopted.is_valid():
		on_adopted.call()
