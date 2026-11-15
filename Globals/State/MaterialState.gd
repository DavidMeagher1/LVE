extends RefCounted

## The current material and the document palette.
##
## The model owns the palette values, the current material, and the default
## palette. It records the material and palette changes in the active document's
## history. State forwards the properties and re-emits the signals.

const DocumentSession := preload("res://Globals/State/DocumentSession.gd")
const SettingsStore := preload("res://Globals/State/SettingsStore.gd")
const OperationRegistry := preload("res://Globals/State/OperationRegistry.gd")

## Emitted when the current color changes.
signal color_changed(color: Color)
## Emitted when the current material changes.
signal material_changed()
## Emitted when the document palette changes.
signal palette_changed()
## Emitted when the default palette changes.
signal default_palette_changed()

## The user path of the saved default palette.
const DEFAULT_PALETTE_PATH := "user://default_palette.cfg"

## The session that owns the active document.
var session: DocumentSession
## The user settings file. The default palette writes through it.
var settings: SettingsStore
## The tracked operations for the edit lock.
var operations: OperationRegistry
## Commits the active document's undo history. State supplies it.
var commit_history := Callable()
## Applies one material value for a history step. State supplies it, so an undo
## action does not hold this model.
var history_apply := Callable()
## Restores one palette snapshot for a history step. State supplies it, so an
## undo action does not hold this model.
var history_restore_palette := Callable()

## The palette that the New Document action applies.
var default_palette := get_builtin_palette()
## The palette index that matches the current material, or -1 when none matches.
var current_palette_index := -1

var _current_material := VoxelFrame.material(Color.BLACK)
## The current material as nine floats. A read returns a copy. A write records a
## history action.
var current_material: PackedFloat32Array:
	get:
		return _current_material.duplicate()
	set(value):
		set_material(value)
## The color of the current material. A write keeps the other material values.
var current_color: Color:
	get:
		return VoxelFrame.material_color(_current_material)
	set(value):
		var material := current_material
		material[0] = value.r
		material[1] = value.g
		material[2] = value.b
		material[3] = value.a
		_apply_material(material)
var _material_edit_document: VoxelDocument
var _material_edit_before := PackedFloat32Array()


## Sets the RGB and alpha of the current material and records a history action.
func set_color(color: Color) -> void:
	var material := current_material
	material[0] = color.r
	material[1] = color.g
	material[2] = color.b
	material[3] = color.a
	set_material(material)


## Sets the current material and records a history action. An invalid material
## is ignored.
func set_material(material: PackedFloat32Array) -> void:
	if not VoxelDocument.valid_material(material):
		return
	end_material_edit()
	if material == _current_material:
		return
	var history := session.document.edit_history
	history.create_action("Set Material", UndoRedo.MERGE_ENDS)
	history.add_undo_method(history_apply.bind(current_material))
	history.add_do_method(history_apply.bind(material.duplicate()))
	commit_history.call(true)


## Applies the current material to the active document without a history action.
## A document adoption calls it, so the swatch match follows the new palette.
func apply_current_material() -> void:
	_apply_material(_current_material)


func _apply_material(material: PackedFloat32Array) -> void:
	var next := material.duplicate()
	# A swatch is selected only while all its values match the current material.
	var index := session.document.palette.find(next) if session.document else -1
	var changed := next != _current_material or index != current_palette_index
	_current_material = next
	current_palette_index = index
	if changed:
		color_changed.emit(current_color)
		material_changed.emit()


## Applies one material value for a history step. [member history_apply] calls it.
func apply_history_material(values: PackedFloat32Array) -> void:
	_apply_material(values)


## Selects a palette entry as the current material. An out-of-range index is
## ignored.
func select_palette_entry(index: int) -> void:
	if index < 0 or index >= session.document.palette.size():
		return
	end_material_edit()
	_apply_material(session.document.palette[index])


## Applies a saved workspace material without a history action. An invalid
## material is ignored.
func apply_workspace_material(material: PackedFloat32Array) -> void:
	if VoxelDocument.valid_material(material):
		_apply_material(material)


## Adds the current material to the palette. An existing equal entry is selected
## instead.
func add_material() -> void:
	if operations.edit_busy():
		return
	end_material_edit()
	var index := session.document.palette.find(_current_material)
	if index >= 0:
		select_palette_entry(index)
		return
	if session.document.palette.size() >= VoxelDocument.MAX_PALETTE_COLORS:
		return
	var before := _palette_snapshot()
	session.document.palette.append(_current_material.duplicate())
	_apply_material(_current_material)
	_record_palette_action("Add Palette Material", before)


## Removes the selected palette entry.
func remove_palette_entry() -> void:
	if operations.edit_busy() or current_palette_index < 0:
		return
	end_material_edit()
	var before := _palette_snapshot()
	var index := current_palette_index
	session.document.palette.remove_at(index)
	if session.document.palette.is_empty():
		_apply_material(_current_material)
	else:
		_apply_material(session.document.palette[mini(index, session.document.palette.size() - 1)])
	_record_palette_action("Remove Palette Material", before)


## Returns a copy of the document palette.
func get_palette() -> Array[PackedFloat32Array]:
	return _copy_palette(session.document.palette)


## Replaces the document palette and records a history action. An invalid
## palette is ignored. The default action name is [code]Replace Palette[/code].
func set_palette(materials: Array[PackedFloat32Array], action_name: String = "Replace Palette") -> void:
	if operations.edit_busy() or not VoxelDocument.valid_palette(materials):
		return
	end_material_edit()
	var unique := _copy_palette(materials)
	if session.document.palette == unique:
		return
	var before := _palette_snapshot()
	session.document.palette = unique
	_apply_material(_current_material)
	_record_palette_action(action_name, before)


## Moves one palette entry to a new index and records a history action.
func move_palette_entry(from_index: int, to_index: int) -> void:
	if operations.edit_busy() or from_index == to_index or from_index < 0 or to_index < 0 or from_index >= session.document.palette.size() or to_index >= session.document.palette.size():
		return
	end_material_edit()
	var before := _palette_snapshot()
	var material := session.document.palette[from_index]
	session.document.palette.remove_at(from_index)
	session.document.palette.insert(to_index, material)
	_apply_material(_current_material)
	_record_palette_action("Move Palette Material", before)


## Applies one material edit. A control gesture records one history step for all
## its changes.
func edit_material(material: PackedFloat32Array) -> void:
	if operations.edit_busy() or not VoxelDocument.valid_material(material) or material == _current_material:
		return
	var before := current_material
	_apply_material(material)
	# A control gesture records one undo step for all its changes.
	if _material_edit_document != session.document:
		_record_material_action(before)


## Starts one material edit gesture. The gesture records one history action.
func begin_material_edit() -> void:
	if operations.edit_busy() or _material_edit_document != null:
		return
	_material_edit_document = session.document
	_material_edit_before = current_material


## Ends the material edit gesture and records its history action.
func end_material_edit() -> void:
	var edited_document := _material_edit_document
	var before := _material_edit_before
	_material_edit_document = null
	_material_edit_before = PackedFloat32Array()
	if edited_document == session.document and not before.is_empty() and before != _current_material:
		_record_material_action(before)


## Cancels the material edit gesture and restores the start material.
func cancel_material_edit() -> void:
	var edited_document := _material_edit_document
	var before := _material_edit_before
	_material_edit_document = null
	_material_edit_before = PackedFloat32Array()
	if edited_document == session.document and not before.is_empty():
		_apply_material(before)


## Drops the material edit gesture without a history action. A document
## replacement calls it.
func reset_edit() -> void:
	_material_edit_document = null
	_material_edit_before = PackedFloat32Array()


func _record_material_action(before: PackedFloat32Array) -> void:
	var history := session.document.edit_history
	history.create_action("Edit Material")
	history.add_undo_method(history_apply.bind(before))
	history.add_do_method(history_apply.bind(current_material))
	commit_history.call(false)


func _copy_palette(materials: Array) -> Array[PackedFloat32Array]:
	return VoxelDocument.unique_palette(materials)


## Returns a copy of the default palette for a new document.
func copy_default_palette() -> Array[PackedFloat32Array]:
	return _copy_palette(default_palette)


func _palette_snapshot() -> Dictionary:
	# The index follows from the palette and the material. Store only what an undo must restore.
	return {"palette": get_palette(), "material": current_material}


func _record_palette_action(action_name: String, before: Dictionary) -> void:
	var after := _palette_snapshot()
	if before == after:
		return
	var history := session.document.edit_history
	history.create_action(action_name)
	# The history belongs to the document, so the action always applies to the
	# active document. Do not bind the document here: the resulting
	# document -> history -> callable -> document cycle would never free.
	history.add_undo_method(history_restore_palette.bind(before))
	history.add_do_method(history_restore_palette.bind(after))
	commit_history.call(false)
	palette_changed.emit()


func _restore_palette(snapshot: Dictionary) -> void:
	session.document.palette = _copy_palette(snapshot.palette)
	_apply_material(snapshot.material)
	palette_changed.emit()


## Restores one palette snapshot for a history step.
## [member history_restore_palette] calls it.
func restore_history_palette(snapshot: Dictionary) -> void:
	_restore_palette(snapshot)


## Returns the built-in default palette.
func get_builtin_palette() -> Array[PackedFloat32Array]:
	# Keep grayscale first, then vivid hues, cooler shadows, and warmer highlights.
	var colors := PackedColorArray([
		Color.BLACK, Color("808080"), Color.WHITE,
		Color("ff0000"), Color("ff8000"), Color("ffff00"), Color("80ff00"), Color("00ff00"), Color("00ff80"),
		Color("00ffff"), Color("0080ff"), Color("0000ff"), Color("8000ff"), Color("ff00ff"), Color("ff0080"),
		Color("800020"), Color("608000"), Color("008020"), Color("006080"), Color("200080"), Color("600080"),
		Color("ffb399"), Color("fffbef"), Color("bfffaa"), Color("b3ffec"), Color("b3c6ff"), Color("ffb3ec"),
	])
	var materials: Array[PackedFloat32Array] = []
	for color in colors:
		materials.append(VoxelFrame.material(color))
	return materials


## Loads the default palette from a config file. A missing or invalid file keeps
## the built-in palette. The default path is [constant DEFAULT_PALETTE_PATH].
func load_default_palette(path: String = DEFAULT_PALETTE_PATH) -> void:
	default_palette = get_builtin_palette()
	var config := ConfigFile.new()
	if config.load(path) == OK:
		var materials: Variant = config.get_value("palette", "materials") if config.has_section_key("palette", "materials") else null
		if materials == null:
			var colors: Variant = config.get_value("palette", "colors") if config.has_section_key("palette", "colors") else null
			if colors is PackedColorArray and colors.size() <= VoxelDocument.MAX_PALETTE_COLORS:
				materials = []
				for color in colors:
					materials.append(VoxelFrame.material(color))
		if VoxelDocument.valid_palette(materials) and not materials.is_empty():
			default_palette = _copy_palette(materials)
	default_palette_changed.emit()


## Saves the current palette as the default. Returns the error code.
func save_default_palette(path: String = DEFAULT_PALETTE_PATH) -> Error:
	if operations.edit_busy():
		return ERR_BUSY
	var materials := get_palette()
	if materials.is_empty() or not VoxelDocument.valid_palette(materials):
		return ERR_INVALID_DATA
	var config := ConfigFile.new()
	config.set_value("palette", "materials", Array(materials))
	var error := settings._save_config_file(config, path)
	if error == OK:
		default_palette = _copy_palette(materials)
		default_palette_changed.emit()
	return error


## Deletes the saved default palette and restores the built-in palette. Returns
## the error code.
func reset_default_palette(path: String = DEFAULT_PALETTE_PATH) -> Error:
	if operations.edit_busy():
		return ERR_BUSY
	if FileAccess.file_exists(path):
		var error := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		if error != OK:
			return error
	default_palette = get_builtin_palette()
	default_palette_changed.emit()
	return OK
