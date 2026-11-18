extends VoxelFrame.EditJob


const SpraySampler := preload("./SpraySampler.gd")
const VoxelPreview := preload("res://Globals/Rendering/VoxelPreview.gd")

var frame: VoxelFrame
var source_frame: VoxelFrame
var center := Vector3i.ZERO
var axes := 0
var origin_twice := Vector3i.ZERO
var selection := {}
var slice_axis := -1
var slice_index := 0
var slice_count := 1
var material := PackedFloat32Array()
var spot_size := 1
var search_size := 9
var speed := 8
var sample_state := 0
var result_state := 0
var rng_epoch := 0
var shape_cache: RefCounted
var capture_chunk_count := 0
var selection_index: RefCounted
var built_selection_index: RefCounted
var index_builds := 0
var index_grid_reads := 0
var index_build_slots := 0
var selection_builds := 0
var row_ops := 0
var footprint_visits := 0
var request_epoch := 0
var cells: Array[Vector3i] = []
var witness := {}
var preview_payload: VoxelPreview.SolidPayload
var local_estimate := 0
var candidate_count := 0

func run() -> void:
	var context := VoxelFrame.EditContext.new()
	context.axes = axes
	context.origin_twice = origin_twice
	context.selection = selection
	var rng := RandomNumberGenerator.new()
	rng.state = sample_state
	stage("Sampling spray", local_estimate)
	var report := {}
	cells = SpraySampler.sample(center, frame, context, spot_size, search_size, speed, rng, material, shape_cache, self, report, selection_index)
	cells = SpraySampler.in_slice(cells, slice_axis, slice_index, slice_count)
	candidate_count = report.get("candidates", 0)
	built_selection_index = report.get("selection_index")
	index_builds = report.get("index_builds", 0)
	index_grid_reads = report.get("index_grid_reads", 0)
	index_build_slots = report.get("index_build_slots", 0)
	selection_builds = report.get("selection_builds", 0)
	row_ops = report.get("row_ops", 0)
	footprint_visits = report.get("footprint_visits", 0)
	result_state = rng.state
	if not checkpoint(0):
		cells = []
		return
	witness = SpraySampler.witness(frame, cells)
	preview_payload = VoxelPreview.build_solid_payload(cells, VoxelFrame.material_color(material))
