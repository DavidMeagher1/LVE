extends VoxelFrame.EditJob


const PrimitiveField := preload("res://Globals/State/Tools/PrimitiveField.gd")

var request: Dictionary
var edited_frame: VoxelFrame
var changed_chunks: Array[Vector3i] = []
var bounds_min := Vector3i.ZERO
var bounds_max := Vector3i.ZERO
var changed_min := Vector3i.MAX
var changed_max := Vector3i.MIN
var blend_skipped := false


func run() -> void:
	var total := PrimitiveField.estimated_cells(request)
	if int(request.get("op", PrimitiveField.OP_ADD)) == PrimitiveField.OP_INTERSECT:
		total = maxi(total, edited_frame.count())
	stage("Building shape", total)
	var result := PrimitiveField.rasterize(request, edited_frame, self)
	blend_skipped = bool(result.get("blend_skipped", false))
	var shape_bounds := PrimitiveField.shape_cell_bounds(request)
	if shape_bounds.is_empty():
		bounds_min = result["bounds_min"]
		bounds_max = result["bounds_max"]
	else:
		bounds_min = shape_bounds[0]
		bounds_max = shape_bounds[1]
	var changes: Dictionary = result["changes"]
	if changes.is_empty():
		applied_cells = {}
		changed_chunks = []
		changed_min = Vector3i.MAX
		changed_max = Vector3i.MIN
		return
	var op := int(request.get("op", PrimitiveField.OP_ADD))
	if op == PrimitiveField.OP_ADD:
		applied_uniform = request.get("material", VoxelFrame.material(Color.WHITE))
		changed_chunks = apply_cells(edited_frame, changes)
	else:
		applied_uniform = VoxelFrame.material(Color.TRANSPARENT)
		if op == PrimitiveField.OP_INTERSECT:
			changed_chunks = edited_frame.set_cells(changes, self, applied_uniform)
		else:
			changed_chunks = apply_cells(edited_frame, changes)
	changed_min = Vector3i.MAX
	changed_max = Vector3i.MIN
	for cell: Vector3i in applied_cells:
		changed_min = Vector3i(mini(changed_min.x, cell.x), mini(changed_min.y, cell.y), mini(changed_min.z, cell.z))
		changed_max = Vector3i(maxi(changed_max.x, cell.x), maxi(changed_max.y, cell.y), maxi(changed_max.z, cell.z))
