extends RefCounted


static func build(vertices: PackedVector3Array) -> ArrayMesh:
	var surface := ArrayMesh.new()
	if vertices.is_empty():
		return surface
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	surface.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return surface
