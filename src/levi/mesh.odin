package levi

import "../gpu/gpu"
import "core:fmt"
import "core:mem"

Vertex_Attribute :: enum {
	Position,
	Color,
	Normal,
	UV0,
}

Vertex_Format :: enum {
	Float32,
	Float16,
	Uint32,
	Uint16,
	Uint8,
	Int32,
	Int16,
	Int8,
}

vertex_format_size :: #force_inline proc(format: Vertex_Format) -> int {
	switch format {
	case .Float32:
		return 4
	case .Float16:
		return 2
	case .Uint32, .Int32:
		return 4
	case .Uint16, .Int16:
		return 2
	case .Uint8, .Int8:
		return 1
	}
	return 0
}

Vertex_Attribute_Desc :: struct {
	format:          Vertex_Format,
	component_count: u32, // 1-4 components
	offset:          u32, // Byte offset in vertex
	stride:          u32, // Byte stride between vertices
	normalized:      bool, // Normalize integers to [0,1] or [-1,1]
}

vertex_attribute_byte_size :: #force_inline proc(desc: Vertex_Attribute_Desc) -> int {
	return int(desc.component_count) * vertex_format_size(desc.format)
}

// ============================================================================
// Mesh Types
// ============================================================================

Mesh_Desc :: struct {
	attributes:      [Vertex_Attribute][]u8,
	attribute_descs: [Vertex_Attribute]Vertex_Attribute_Desc,
	indices:         []u32,
}

Mesh_Info :: struct #align (16) {
	pos_offset:      u32,
	pos_count:       u32,
	index_offset:    u32,
	index_count:     u32,
	aabb_min:        [3]f32,
	aabb_max:        [3]f32,
	attribute_descs: [Vertex_Attribute]Vertex_Attribute_Desc,
}

// ============================================================================
// Mesh Creation
// ============================================================================

create_mesh :: proc(
	eng: ^Engine,
	desc: ^Mesh_Desc,
	loc := #caller_location,
) -> (
	id: Mesh_ID,
	err: Error,
) {
	if eng == nil {
		log_error(.Invalid_Argument, loc)
		return INVALID_MESH_ID, .Invalid_Argument
	}

	// Validate formats
	for attr in Vertex_Attribute {
		data := desc.attributes[attr]
		if len(data) > 0 {
			attr_desc := desc.attribute_descs[attr]
			if attr_desc.component_count < 1 || attr_desc.component_count > 4 {
				log_error(.Invalid_Format, loc)
				return INVALID_MESH_ID, .Invalid_Format
			}
			expected_size := vertex_attribute_byte_size(attr_desc)
			if expected_size == 0 {
				log_error(.Invalid_Format, loc)
				return INVALID_MESH_ID, .Invalid_Format
			}
			if attr_desc.stride == 0 {
				desc.attribute_descs[attr].stride = u32(expected_size)
			}
		}
	}

	upload_arena := gpu.arena_create()
	defer gpu.arena_destroy(&upload_arena)

	cmd := gpu.commands_begin(.Main)
	defer gpu.queue_wait_idle(.Main)

	pos_off := eng.renderer.heads[.Position]
	idx_off := eng.renderer.heads[.Indices]
	vertex_count := u32(0)

	for attr in Vertex_Attribute {
		data := desc.attributes[attr]
		if len(data) > 0 {
			stream_attr := Stream_Attribute(attr)
			attr_desc := desc.attribute_descs[attr]

			if attr_desc.stride > 0 {
				count := i64(len(data)) / i64(attr_desc.stride)
				if attr == .Position do vertex_count = u32(count)
			}

			staging := gpu.arena_alloc_raw(&upload_arena, len(data), 16)
			mem.copy(staging.cpu, raw_data(data), len(data))
			gpu.cmd_mem_copy_raw(cmd, eng.renderer.streams[stream_attr], staging.gpu, len(data))
			eng.renderer.heads[stream_attr] += u32(
				len(data) / vertex_format_size(attr_desc.format),
			)
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

	info := Mesh_Info {
		pos_offset      = pos_off,
		pos_count       = vertex_count,
		index_offset    = idx_off,
		index_count     = u32(len(desc.indices)),
		aabb_min        = {-1, -1, -1},
		aabb_max        = {1, 1, 1},
		attribute_descs = desc.attribute_descs,
	}

	append(&eng.renderer.meshes, info)
	id = Mesh_ID(u32(len(eng.renderer.meshes) - 1))

	log_levi(fmt.tprintf("Mesh %v creation complete.", id), loc)
	return id, .None
}
