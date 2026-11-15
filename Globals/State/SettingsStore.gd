extends RefCounted

## The user settings file and the remembered session.
##
## The store reads and writes the one settings file through a temporary file. A
## file that cannot be read stays as it is, so a damaged file is never replaced
## by an empty one. State forwards these methods.

## The one user settings file. It stores the interface, agent, version, session,
## and file dialog state.
const SETTINGS_PATH := "user://settings.cfg"
## The legacy files that the migration reads once.
const LEGACY_SETTINGS_PATHS := [
	"user://interface.cfg",
	"user://session.cfg",
	"user://file_dialog.cfg",
]
## The image file extensions that the importer supports.
const IMAGE_EXTENSIONS := ["bmp", "dds", "exr", "hdr", "jpg", "jpeg", "ktx", "ktx2", "png", "svg", "tga", "webp"]

## The tree that [method is_app_session] inspects. State sets it in its _ready.
var tree: SceneTree
## The settings file. Tests set a temporary path.
var settings_path := SETTINGS_PATH


## Loads a settings file. A missing file gives an empty configuration. Returns
## [code]null[/code] when the file exists but cannot be read.
func _load_settings(path: String) -> ConfigFile:
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == OK or error == ERR_FILE_NOT_FOUND:
		return config
	push_warning("Cannot read the user settings: %s" % error_string(error))
	return null


## Returns the path for a settings read or write. An empty path uses the one
## settings file.
func _settings_path(path: String) -> String:
	return settings_path if path.is_empty() else path


## Writes a configuration through a temporary file, so a crash cannot truncate
## the previous file.
func _save_config_file(config: ConfigFile, path: String) -> Error:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(config.encode_to_text())
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	return error


## Moves every missing key from the legacy files into the target file. The
## target wins on a conflict. It removes only the legacy files that it read.
func migrate_settings(target_path: String = "", legacy_paths: PackedStringArray = PackedStringArray()) -> Error:
	if target_path.is_empty():
		target_path = settings_path
	if legacy_paths.is_empty():
		legacy_paths = PackedStringArray(LEGACY_SETTINGS_PATHS)
	var target := _load_settings(target_path)
	if target == null:
		return ERR_FILE_CORRUPT
	var merged := false
	var loaded_legacy_paths := PackedStringArray()
	for legacy_path in legacy_paths:
		var legacy := ConfigFile.new()
		if legacy.load(legacy_path) != OK:
			continue
		loaded_legacy_paths.append(legacy_path)
		for section in legacy.get_sections():
			for key in legacy.get_section_keys(section):
				if target.has_section_key(section, key):
					continue
				target.set_value(section, key, legacy.get_value(section, key))
				merged = true
	if merged:
		var error := _save_config_file(target, target_path)
		if error != OK:
			push_warning("Cannot save the user settings: %s" % error_string(error))
			return error
	for legacy_path in loaded_legacy_paths:
		if FileAccess.file_exists(legacy_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	return OK


## Stores the last document path in the settings file.
func remember_document(path: String, config_path: String = "") -> void:
	config_path = _settings_path(config_path)
	var config := _load_settings(config_path)
	if config == null:
		return
	config.set_value("files", "last_document", path)
	var error := _save_config_file(config, config_path)
	if error != OK:
		push_warning("Cannot save the user settings: %s" % error_string(error))


## Removes the last document path from the settings file.
func forget_document(config_path: String = "") -> void:
	config_path = _settings_path(config_path)
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	if config.has_section_key("files", "last_document"):
		config.erase_section_key("files", "last_document")
	var error := _save_config_file(config, config_path)
	if error != OK:
		push_warning("Cannot save the user settings: %s" % error_string(error))


## Returns the stored last document path, or an empty string.
func last_document_path(config_path: String = "") -> String:
	config_path = _settings_path(config_path)
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return ""
	var path: Variant = config.get_value("files", "last_document", "")
	return path if path is String else ""


## Returns the saved tab paths, or an empty array.
func last_tabs(config_path: String = "") -> PackedStringArray:
	config_path = _settings_path(config_path)
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return PackedStringArray()
	var stored: Variant = config.get_value("files", "tabs", PackedStringArray())
	if stored is PackedStringArray:
		return stored
	var paths := PackedStringArray()
	if stored is Array:
		for value in stored:
			if value is String:
				paths.append(value)
	return paths


## Returns the saved active tab index, or zero.
func last_tab_index(config_path: String = "") -> int:
	config_path = _settings_path(config_path)
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return 0
	return int(config.get_value("files", "active", 0))


## Writes the open documents that have a path, and the active index. [param
## documents] supplies the tabs and [param active_index] is the active one. A tab
## that was never saved has no path, so a restart cannot reopen it.
func remember_session(documents: Array[VoxelDocument], active_index: int, config_path: String = "") -> void:
	config_path = _settings_path(config_path)
	var config := _load_settings(config_path)
	if config == null:
		return
	var stored_active := int(config.get_value("files", "active", 0))
	var paths := PackedStringArray()
	var active_path := -1
	for index in documents.size():
		var document := documents[index]
		# Only a written path is a save path. A bundled sample has a file path
		# but must not be saved over, so the next launch opens it again.
		var path := document.edit_save_path
		if path.is_empty():
			continue
		if index == active_index:
			active_path = paths.size()
		paths.append(path)
	# A pathless active tab, such as the splash, must not discard the saved
	# active tab. Keep the stored index when it still fits the saved paths.
	var active := active_path
	if active < 0:
		active = clampi(stored_active, 0, maxi(paths.size() - 1, 0))
	config.set_value("files", "tabs", paths)
	config.set_value("files", "active", active)
	if not paths.is_empty():
		config.set_value("files", "last_document", paths[active])
	var error := _save_config_file(config, config_path)
	if error != OK:
		push_warning("Cannot save the user settings: %s" % error_string(error))


## Returns [code]true[/code] when the current scene is the application Main
## scene. A test scene has no current scene, so a null match is not enough.
func is_app_session() -> bool:
	if tree == null:
		return false
	var main := tree.root.get_node_or_null("Main")
	return main != null and tree.current_scene == main


## Returns the file dialog filter for the supported image formats.
func get_image_file_filter() -> String:
	var patterns := PackedStringArray()
	for extension in IMAGE_EXTENSIONS:
		patterns.append("*." + extension)
	return ", ".join(patterns) + " ; Images"
