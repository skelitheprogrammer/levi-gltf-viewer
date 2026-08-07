package render

import "core:math/linalg"

prim_triangle :: proc(allocator := context.allocator) -> (vertex: Mesh) {
	positions := make([][3]f32, 3, allocator)
	positions[0] = {-0.5, -0.5, 0}
	positions[1] = {0.5, -0.5, 0}
	positions[2] = {0.0, 0.5, 0}
	vertex.streams[.Position] = transmute([]u8)positions

	normals := make([][3]f32, 3, allocator)
	for &n in normals do n = {0, 0, 1}
	vertex.streams[.Normal] = transmute([]u8)normals

	vertex.indices = make([]u32, 3, allocator)
	vertex.indices[0] = 0
	vertex.indices[1] = 1
	vertex.indices[2] = 2

	vertex.base_color = {1, 1, 1, 1}
	vertex.aabb_min = {-0.5, -0.5, 0}
	vertex.aabb_max = {0.5, 0.5, 0}
	return
}

prim_quad :: proc(allocator := context.allocator) -> (vertex: Mesh) {
	positions := make([][3]f32, 4, allocator)
	positions[0] = {-0.5, -0.5, 0}
	positions[1] = {0.5, -0.5, 0}
	positions[2] = {0.5, 0.5, 0}
	positions[3] = {-0.5, 0.5, 0}
	vertex.streams[.Position] = transmute([]u8)positions

	normals := make([][3]f32, 4, allocator)
	for &n in normals do n = {0, 0, 1}
	vertex.streams[.Normal] = transmute([]u8)normals

	vertex.indices = make([]u32, 6, allocator)
	vertex.indices[0] = 0
	vertex.indices[1] = 1
	vertex.indices[2] = 2
	vertex.indices[3] = 0
	vertex.indices[4] = 2
	vertex.indices[5] = 3

	vertex.base_color = {1, 1, 1, 1}
	vertex.aabb_min = {-0.5, -0.5, 0}
	vertex.aabb_max = {0.5, 0.5, 0}
	return
}

compute_face_normal :: #force_inline proc "contextless" (p: [][3]f32) -> [3]f32 {
	e1 := p[1] - p[0]
	e2 := p[2] - p[0]
	return linalg.normalize(linalg.cross(e1, e2))
}
