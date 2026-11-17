extends RefCounted

## The workspace JSON shapes.
##
## The editor stores the camera, lighting, view, and export settings on the
## document. This class turns those dictionaries into the JSON shape that the
## MCP workspace tools accept, and back.

const MCPJson := preload("res://Globals/MCP/MCPJson.gd")


## Coerces whole JSON numbers to ints for the fields that the document format
## requires as integers. JSON has no integer type.
static func coerce_whole_ints(data: Dictionary, keys: Array) -> void:
	for key in keys:
		if not data.has(key):
			continue
		var value: Variant = data[key]
		if value is float and is_equal_approx(value, roundf(value)):
			data[key] = int(roundf(value))


## Returns the workspace of one document in the JSON shape that the setter
## accepts. The revision is the server's content revision.
static func data(document: VoxelDocument, revision: int) -> Dictionary:
	return {
		"revision": revision,
		"camera": camera_json(document.edit_camera),
		"lighting": lighting_json(document.lighting_settings, false),
		"view": document.view_settings.duplicate(),
		"export": export_json(document.export_settings),
		"frame": State.current_frame,
		"tag": State.active_tag,
		"playing": State.is_playing,
		"size": [document.size.x, document.size.y, document.size.z],
	}


static func camera_json(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var camera: Dictionary = value
	var data := {}
	for key in ["yaw", "pitch", "distance", "initial_distance", "orthographic", "fov"]:
		if camera.has(key):
			data[key] = camera[key]
	if camera.has("target"):
		var target_value: Variant = camera["target"]
		if target_value is Vector3:
			data["target"] = MCPJson.vector_json(target_value)
	return data


static func camera(value: Variant) -> Variant:
	if not (value is Dictionary):
		return null
	var source: Dictionary = value
	var data := source.duplicate()
	if data.has("target"):
		var target: Variant = vector(data["target"])
		if target == null:
			return null
		data["target"] = target
	if not VoxelDocument.valid_camera_pose(data):
		return null
	return data


static func lighting_json(value: Variant, exported: bool) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var settings: Dictionary = value
	if settings.is_empty():
		return {}
	var data := {}
	for key in settings:
		var name := str(key)
		match name:
			"basis", "view_basis":
				data[name] = basis_json(settings[key])
			"color", "ambient_color":
				var color: Color = settings[key]
				data[name] = MCPJson.hex_color(Color(color.r, color.g, color.b, 1.0))
				if not exported:
					var energy_key := "energy" if name == "color" else "ambient_energy"
					data[energy_key] = snappedf(color.a, 0.001)
			_:
				data[name] = settings[key]
	return data


static func lighting(value: Variant, exported: bool) -> Variant:
	if not (value is Dictionary):
		return null
	var source: Dictionary = value
	if source.is_empty():
		return {}
	var data := {}
	for key in source:
		var name := str(key)
		match name:
			"basis", "view_basis":
				var basis_value: Variant = basis(source[key])
				if basis_value == null:
					return null
				data[name] = basis_value
			"color", "ambient_color":
				var color_value: Variant = MCPJson.parse_color(source[key])
				if color_value == null:
					return null
				var color: Color = color_value
				data[name] = Color(color.r, color.g, color.b, 1.0)
			"energy", "ambient_energy":
				if not (source[key] is int or source[key] is float):
					return null
				data[name] = clampf(float(source[key]), 0.0, 16.0)
			_:
				data[name] = source[key]
	if exported:
		return data
	# The editor lighting stores each strength in the color alpha.
	var light: Color = data.get("color", Color.WHITE)
	light.a = float(data.get("energy", 1.0))
	data["color"] = light
	var ambient: Color = data.get("ambient_color", Color.WHITE)
	ambient.a = float(data.get("ambient_energy", 1.0))
	data["ambient_color"] = ambient
	data.erase("energy")
	data.erase("ambient_energy")
	if not VoxelDocument.valid_lighting_settings(data):
		return null
	return data


static func export_json(value: Variant) -> Dictionary:
	if not (value is Dictionary):
		return {}
	var settings: Dictionary = value
	var data := {}
	for key in settings:
		var name := str(key)
		match name:
			"lighting":
				data[name] = lighting_json(settings[key], true)
			"camera":
				data[name] = camera_json(settings[key])
			_:
				data[name] = settings[key]
	return data


static func export(value: Variant, tag_count: int) -> Variant:
	if not (value is Dictionary):
		return null
	var source: Dictionary = value
	var data := {}
	for key in source:
		var name := str(key)
		match name:
			"lighting":
				var lighting_value: Variant = lighting(source[key], true)
				if lighting_value == null:
					return null
				data[name] = lighting_value
			"camera":
				var camera_value: Variant = camera(source[key])
				if camera_value == null:
					return null
				data[name] = camera_value
			_:
				data[name] = source[key]
	coerce_whole_ints(data, ["view", "model_tag", "sheet_tag"])
	if not VoxelDocument.valid_export_settings(data, tag_count):
		return null
	return data


static func basis_json(value: Variant) -> Array:
	var basis_value: Basis = value if value is Basis else Basis.IDENTITY
	return [MCPJson.vector_json(basis_value.x), MCPJson.vector_json(basis_value.y), MCPJson.vector_json(basis_value.z)]


static func basis(value: Variant) -> Variant:
	if not (value is Array):
		return null
	var columns: Array = value
	if columns.size() != 3:
		return null
	var vectors: Array[Vector3] = []
	for column in columns:
		var vector_value: Variant = vector(column)
		if vector_value == null:
			return null
		vectors.append(vector_value)
	return Basis(vectors[0], vectors[1], vectors[2])


static func vector(value: Variant) -> Variant:
	if not (value is Array):
		return null
	var components: Array = value
	if components.size() != 3:
		return null
	for component in components:
		if not (component is int or component is float):
			return null
	return Vector3(float(components[0]), float(components[1]), float(components[2]))
