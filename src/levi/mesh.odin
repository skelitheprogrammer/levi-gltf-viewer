package levi

import "../gpu/gpu"
import "core:mem"

create_mesh :: proc(eng: ^Engine, desc: Mesh_Desc) -> Mesh_ID {
	upload_arena := gpu.arena_create()
	defer gpu.arena_destroy(&upload_arena)
	cmd := gpu.commands_begin(.Main)

	pos_off := eng.renderer.heads[.Position]
	idx_off := eng.renderer.heads[.Indices]
	vertex_count := u32(0)

	for attr in Vertex_Attribute {
		data := desc.attributes[attr]
		if len(data) > 0 {
			stream_attr := Stream_Attribute(attr)
			count := i64(len(data)) / Stream_Element_Size[stream_attr]
			if attr == .Position do vertex_count = u32(count)

			staging := gpu.arena_alloc_raw(&upload_arena, len(data), 16)
			mem.copy(staging.cpu, raw_data(data), len(data))
			gpu.cmd_mem_copy_raw(cmd, eng.renderer.streams[stream_attr], staging.gpu, len(data))
			eng.renderer.heads[stream_attr] += u32(count)
		}
	}

	if len(desc.indices) > 0 {
		staging_idx := gpu.arena_alloc(&upload_arena, u32, len(desc.indices))
		copy(staging_idx.cpu, desc.indices)
		gpu.cmd_mem_copy_raw(
			cmd,
			eng.renderer.streams[.Indices],
			staging_idx.gpu,
			size_of(u32) * len(desc.indices),
		)
		eng.renderer.heads[.Indices] += u32(len(desc.indices))
	}

	gpu.cmd_barrier(cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {cmd})
	gpu.wait_idle()

	info := Mesh_Info {
		pos_offset   = pos_off,
		pos_count    = vertex_count,
		index_offset = idx_off,
		index_count  = u32(len(desc.indices)),
		aabb_min     = {-1, -1, -1},
		aabb_max     = {1, 1, 1},
	}
	append(&eng.renderer.meshes, info)
	return Mesh_ID(u32(len(eng.renderer.meshes) - 1))
}

generate_quad_mesh :: proc() -> Mesh_Desc {
	pos := make([][4]f32, 4)
	pos[0] = {-0.5, -0.5, 0, 1}; pos[1] = {0.5, -0.5, 0, 1}
	pos[2] = {0.5, 0.5, 0, 1}; pos[3] = {-0.5, 0.5, 0, 1}

	col := make([][4]f32, 4)
	for i in 0 ..< 4 do col[i] = {1, 1, 1, 1}

	idx := make([]u32, 6)
	idx[0] = 0; idx[1] = 1; idx[2] = 2; idx[3] = 0; idx[4] = 2; idx[5] = 3

	return Mesh_Desc {
		attributes = #partial{
			.Position = mem.slice_to_bytes(pos[:]),
			.Color = mem.slice_to_bytes(col[:]),
		},
		indices = idx,
	}
}
