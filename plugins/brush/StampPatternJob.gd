extends VoxelFrame.EditJob


const VoxelBrushSize := preload("res://Globals/State/Tools/VoxelBrushSize.gd")

const SPHERE := 1

var diameter := 1
var shape := 0
var pattern := {}
var offsets: Array = []


func run() -> void:
	pattern = build_pattern(diameter, shape, self)
	if not pattern.is_empty():
		offsets = pattern.keys()


static func build_pattern(brush_diameter: int, brush_shape: int, job: VoxelFrame.EditJob = null) -> Dictionary:
	var cells := {}
	var first_offset := VoxelBrushSize.first_offset(brush_diameter)
	var last_offset := VoxelBrushSize.last_offset(brush_diameter)
	var sphere := brush_shape == SPHERE
	if job:
		job.stage("Preparing brush shape", brush_diameter ** 3)
	var completed := 0
	for x in range(first_offset, last_offset + 1):
		for y in range(first_offset, last_offset + 1):
			for z in range(first_offset, last_offset + 1):
				if not sphere or VoxelBrushSize.contains_sphere(brush_diameter, Vector3i(x, y, z)):
					cells[Vector3i(x, y, z)] = Color.TRANSPARENT
				completed += 1
				if job and completed % 4096 == 0 and not job.checkpoint(completed):
					return {}
	return cells
