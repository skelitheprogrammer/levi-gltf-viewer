package asset_management

import g "../glTF2"
import "../render"
import "core:math/linalg"

Load_Result :: struct {
	meshes: [dynamic]render.Mesh,
	models: [dynamic]matrix[4, 4]f32,
}

load_scene_data :: proc(path: string, allocator := context.allocator) -> Load_Result {
	data, err := g.load_from_file(path, allocator)
	ensure(err == nil)
	defer g.unload(data)

	ensure(len(data.extensions_required) == 0, "asset requires unsupported glTF extensions")

	meshes := make([dynamic]render.Mesh, allocator)
	models := make([dynamic]matrix[4, 4]f32, allocator)

	Stack_Entry :: struct {
		node:         g.Integer,
		parent_world: matrix[4, 4]f32,
	}
	stack := make([dynamic]Stack_Entry, allocator)
	defer delete(stack)


	if idx, ok := data.scene.?; ok && int(idx) < len(data.scenes) {
		for node in data.scenes[idx].nodes do append(&stack, Stack_Entry{node, linalg.MATRIX4F32_IDENTITY})
	} else {
		for scene in data.scenes {
			for node in scene.nodes do append(&stack, Stack_Entry{node, linalg.MATRIX4F32_IDENTITY})
		}
	}

	for len(stack) > 0 {
		entry := stack[len(stack) - 1]
		resize(&stack, len(stack) - 1)

		node := &data.nodes[entry.node]
		world := entry.parent_world * node_transform(node)

		if mid, ok := node.mesh.?; ok {
			mesh := &data.meshes[mid]
			for &prim in mesh.primitives {
				if prim.mode != .Triangles do continue
				append(&meshes, emit_mesh(data, &prim, allocator))
				append(&models, world)
			}
		}

		for child in node.children do append(&stack, Stack_Entry{child, world})
	}

	return Load_Result{meshes, models}
}

free_scene_data :: proc(r: Load_Result) {
	for &m in r.meshes {
		for &s in m.streams do delete(s)
		delete(m.indices)
	}
	delete(r.meshes)
	delete(r.models)
}

@(private)
emit_mesh :: proc(
	data: ^g.Data,
	prim: ^g.Mesh_Primitive,
	allocator := context.allocator,
) -> render.Mesh {
	m: render.Mesh
	m.base_color = {1, 1, 1, 1}

	for name, acc in prim.attributes {
		switch name {
		case "POSITION":
			m.streams[.Position] = transmute([]u8)gather_vec3(data, acc, allocator)
			a := data.accessors[acc]
			if mn, ok := a.min.?; ok do m.aabb_min = {f32(mn[0]), f32(mn[1]), f32(mn[2])}
			if mx, ok := a.max.?; ok do m.aabb_max = {f32(mx[0]), f32(mx[1]), f32(mx[2])}
		case "NORMAL":
			m.streams[.Normal] = transmute([]u8)gather_vec3(data, acc, allocator)
		case "TEXCOORD_0":
			m.streams[.UV0] = transmute([]u8)gather_vec2(data, acc, allocator)
		case "COLOR_0":
			m.streams[.Color] = transmute([]u8)gather_color(data, acc, allocator)
		}
	}
	ensure(len(m.streams[.Position]) > 0, "primitive without POSITION")

	if pid, ok := prim.indices.?; ok {
		#partial switch vals in g.buffer_slice(data, pid) {
		case []u8:
			m.indices = make([]u32, len(vals), allocator)
			for i, v in vals do m.indices[i] = u32(v)
		case []u16:
			m.indices = make([]u32, len(vals), allocator)
			for i, v in vals do m.indices[i] = u32(v)
		case []u32:
			m.indices = make([]u32, len(vals), allocator)
			copy(m.indices, vals)
		case:
			ensure(false, "unsupported index component type")
		}
	} else {
		count := render.mesh_vertex_count(&m)
		m.indices = make([]u32, count, allocator)
		for i in 0 ..< count do m.indices[i] = u32(i)
	}

	if mid, ok := prim.material.?; ok && int(mid) < len(data.materials) {
		if mr, ok2 := data.materials[mid].metallic_roughness.?; ok2 {
			f := mr.base_color_factor
			m.base_color = {f32(f[0]), f32(f[1]), f32(f[2]), f32(f[3])}
		}
	}

	return m
}


@(private)
gather_vec3 :: proc(data: ^g.Data, acc: g.Integer, allocator := context.allocator) -> [][3]f32 {
	#partial switch vals in g.buffer_slice(data, acc) {
	case [][3]f32:
		out := make([][3]f32, len(vals), allocator)
		copy(out, vals)
		return out
	case:
		ensure(false, "unsupported VEC3 component format")
	}
	return nil
}

@(private)
gather_vec2 :: proc(data: ^g.Data, acc: g.Integer, allocator := context.allocator) -> [][2]f32 {
	out: [][2]f32
	#partial switch vals in g.buffer_slice(data, acc) {
	case [][2]f32:
		out = make([][2]f32, len(vals), allocator)
		copy(out, vals)
	case [][3]f32:
		out = make([][2]f32, len(vals), allocator)
		for v, i in vals do out[i] = {v[0], v[1]}
	case:
		ensure(false, "unsupported TEXCOORD format")
	}
	return out
}

@(private)
gather_color :: proc(data: ^g.Data, acc: g.Integer, allocator := context.allocator) -> [][4]f32 {
	out: [][4]f32
	#partial switch vals in g.buffer_slice(data, acc) {
	case [][3]f32:
		out = make([][4]f32, len(vals), allocator)
		for v, i in vals do out[i] = {v[0], v[1], v[2], 1}
	case [][4]f32:
		out = make([][4]f32, len(vals), allocator)
		copy(out, vals)
	case [][4]u8:
		out = make([][4]f32, len(vals), allocator)
		for v, i in vals do out[i] = {f32(v[0]) / 255, f32(v[1]) / 255, f32(v[2]) / 255, f32(v[3]) / 255}
	case:
		ensure(false, "unsupported COLOR_0 format")
	}
	return out
}

@(private)
node_transform :: #force_inline proc "contextless" (node: ^g.Node) -> matrix[4, 4]f32 {
	if node.mat != linalg.MATRIX4F32_IDENTITY do return node.mat
	r := node.rotation
	s := node.scale
	if r == linalg.Quaternionf32(0) do r = linalg.QUATERNIONF32_IDENTITY
	if s == {0, 0, 0} do s = {1, 1, 1}
	return linalg.matrix4_from_trs_f32(node.translation, r, s)
}
