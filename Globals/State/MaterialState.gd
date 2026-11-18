extends RefCounted


const DocumentSession := preload("res://Globals/State/DocumentSession.gd")
const SettingsStore := preload("res://Globals/State/SettingsStore.gd")
const OperationRegistry := preload("res://Globals/State/OperationRegistry.gd")

signal color_changed(color: Color)
signal material_changed()
signal palette_changed()
signal default_palette_changed()

const DEFAULT_PALETTE_PATH := "user://default_palette.cfg"

var session: DocumentSession
var settings: SettingsStore
var operations: OperationRegistry
var commit_history := Callable()
var history_apply := Callable()
var history_restore_palette := Callable()

var default_palette := get_builtin_palette()
var current_palette_index := -1

var _current_material := VoxelFrame.material(Color.BLACK)
var current_material: PackedFloat32Array:
	get:
		return _current_material.duplicate()
	set(value):
		set_material(value)
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


func set_color(color: Color) -> void:
	var material := current_material
	material[0] = color.r
	material[1] = color.g
	material[2] = color.b
	material[3] = color.a
	set_material(material)


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


func apply_current_material() -> void:
	_apply_material(_current_material)


func _apply_material(material: PackedFloat32Array) -> void:
	var next := material.duplicate()
	var index := session.document.palette.find(next) if session.document else -1
	var changed := next != _current_material or index != current_palette_index
	_current_material = next
	current_palette_index = index
	if changed:
		color_changed.emit(current_color)
		material_changed.emit()


func apply_history_material(values: PackedFloat32Array) -> void:
	_apply_material(values)


func select_palette_entry(index: int) -> void:
	if index < 0 or index >= session.document.palette.size():
		return
	end_material_edit()
	_apply_material(session.document.palette[index])


func apply_workspace_material(material: PackedFloat32Array) -> void:
	if VoxelDocument.valid_material(material):
		_apply_material(material)


func add_material() -> void:
	if operations.edit_busy():
		return
	end_material_edit()
	var swatch_index := session.document.palette.find(_current_material)
	if swatch_index >= 0:
		select_palette_entry(swatch_index)
		return
	if session.document.palette.size() >= VoxelDocument.MAX_PALETTE_COLORS:
		return
	var before := _palette_snapshot()
	session.document.palette.append(_current_material.duplicate())
	_apply_material(_current_material)
	_record_palette_action("Add Palette Material", before)


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


func get_palette() -> Array[PackedFloat32Array]:
	return _copy_palette(session.document.palette)


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


func edit_material(material: PackedFloat32Array) -> void:
	if operations.edit_busy() or not VoxelDocument.valid_material(material) or material == _current_material:
		return
	var before := current_material
	_apply_material(material)
	if _material_edit_document != session.document:
		_record_material_action(before)


func begin_material_edit() -> void:
	if operations.edit_busy() or _material_edit_document != null:
		return
	_material_edit_document = session.document
	_material_edit_before = current_material


func end_material_edit() -> void:
	var edited_document := _material_edit_document
	var before := _material_edit_before
	_material_edit_document = null
	_material_edit_before = PackedFloat32Array()
	if edited_document == session.document and not before.is_empty() and before != _current_material:
		_record_material_action(before)


func cancel_material_edit() -> void:
	var edited_document := _material_edit_document
	var before := _material_edit_before
	_material_edit_document = null
	_material_edit_before = PackedFloat32Array()
	if edited_document == session.document and not before.is_empty():
		_apply_material(before)


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


func copy_default_palette() -> Array[PackedFloat32Array]:
	return _copy_palette(default_palette)


func _palette_snapshot() -> Dictionary:
	return {"palette": get_palette(), "material": current_material}


func _record_palette_action(action_name: String, before: Dictionary) -> void:
	var after := _palette_snapshot()
	if before == after:
		return
	var history := session.document.edit_history
	history.create_action(action_name)
	history.add_undo_method(history_restore_palette.bind(before))
	history.add_do_method(history_restore_palette.bind(after))
	commit_history.call(false)
	palette_changed.emit()


func _restore_palette(snapshot: Dictionary) -> void:
	session.document.palette = _copy_palette(snapshot.palette)
	_apply_material(snapshot.material)
	palette_changed.emit()


func restore_history_palette(snapshot: Dictionary) -> void:
	_restore_palette(snapshot)


func get_builtin_palette() -> Array[PackedFloat32Array]:
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
