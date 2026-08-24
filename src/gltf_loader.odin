package levi

import "core:math/linalg"
import "core:os"
import "core:strings"
import gpu "gpu/gpu"
import cgltf "vendor:cgltf"

Staging_Data :: struct {
	vertex_mask:  Vertex_Mask,
	vertex_count: u32,
	index_count:  u32,
	bounds_min:   linalg.Vector3f32,
	bounds_max:   linalg.Vector3f32,
	attributes:   [Vertex_Attribute]gpu.slice_t(u8),
	indices:      gpu.slice_t(u8),
	commands:     gpu.slice_t(Indirect_Command),
}

ACCESSOR_MAP := #partial [cgltf.attribute_type]Vertex_Attribute {
	.position = .Position,
	.normal   = .Normal,
	.texcoord = .Texcoord,
	.color    = .Color,
}

ACCESSOR_COMPONENT_COUNTS := #partial [cgltf.type]i32 {
	.scalar = 1,
	.vec2   = 2,
	.vec3   = 3,
	.vec4   = 4,
	.mat2   = 4,
	.mat3   = 9,
	.mat4   = 16,
}

read_floats :: proc(dst: gpu.slice_t(u8), accessor: ^cgltf.accessor, byte_offset: ^i32) {
	num_comp := ACCESSOR_COMPONENT_COUNTS[accessor.type]
	count_elems := i32(accessor.count) * num_comp
	if count_elems <= 0 {return}

	count_bytes := count_elems * size_of(f32)
	dst_ptr := &dst.cpu[byte_offset^]

	_ = cgltf.accessor_read_float(accessor, 0, cast(^f32)(dst_ptr), uint(count_elems))
	byte_offset^ += count_bytes
}

read_indices :: proc(dst: gpu.slice_t(u8), accessor: ^cgltf.accessor, byte_offset: ^i32) {
	count_elems := i32(accessor.count)
	if count_elems == 0 {return}

	count_bytes := count_elems * size_of(u32)
	dst_ptr := &dst.cpu[byte_offset^]

	_ = cgltf.accessor_read_uint(accessor, 0, cast(^u32)(dst_ptr), uint(count_elems))
	byte_offset^ += count_bytes
}

parse_gltf_to_staging :: proc(staging: ^gpu.Arena, p: string) -> Staging_Data {
	file_data, os_err := os.read_entire_file(p, context.allocator)
	if os_err != nil do return {}
	defer delete(file_data)

	options: cgltf.options
	data, err := cgltf.parse(options, raw_data(file_data), uint(len(file_data)))
	if err != .success do return {}
	defer cgltf.free(data)

	cp := strings.clone_to_cstring(p)
	defer delete(cp)
	if cgltf.load_buffers(options, data, cp) != .success do return {}

	byte_sizes: [Vertex_Attribute]i32
	total_idx_bytes: i32
	prim_count: i32
	vertex_count: u32
	index_count: u32
	mask: Vertex_Mask

	bounds_min := linalg.Vector3f32{1e30, 1e30, 1e30}
	bounds_max := linalg.Vector3f32{-1e30, -1e30, -1e30}

	for mesh in data.meshes {
		for prim in mesh.primitives {
			prim_count += 1
			for &attr in prim.attributes {
				mapped_attr := ACCESSOR_MAP[attr.type]
				if mapped_attr == .None {continue}
				mask += {mapped_attr}

				num_comp := ACCESSOR_COMPONENT_COUNTS[attr.data.type]
				byte_sizes[mapped_attr] += i32(attr.data.count) * num_comp * size_of(f32)

				if mapped_attr == .Position {
					vertex_count += u32(attr.data.count)
					if attr.data.has_min && attr.data.has_max {
						for i in 0 ..< 3 {
							if attr.data.min[i] < bounds_min[i] {bounds_min[i] = attr.data.min[i]}
							if attr.data.max[i] > bounds_max[i] {bounds_max[i] = attr.data.max[i]}
						}
					}
				}
			}
			if prim.indices != nil {
				total_idx_bytes += i32(prim.indices.count) * size_of(u32)
				index_count += u32(prim.indices.count)
			}
		}
	}

	res: Staging_Data
	res.vertex_mask = mask
	res.vertex_count = vertex_count
	res.index_count = index_count
	res.bounds_min = bounds_min
	res.bounds_max = bounds_max

	for size, attr in byte_sizes {
		if size > 0 {
			res.attributes[attr] = gpu.arena_alloc_slice(staging, u8, size)
		}
	}
	if total_idx_bytes > 0 {
		res.indices = gpu.arena_alloc_slice(staging, u8, total_idx_bytes)
	}
	res.commands = gpu.arena_alloc_slice(staging, Indirect_Command, prim_count)

	byte_offsets: [Vertex_Attribute]i32
	curr_idx_bytes: i32
	cmd_idx: i32

	for mesh in data.meshes {
		for prim in mesh.primitives {
			cmd := &res.commands.cpu[cmd_idx]
			cmd.instance_count = 1
			cmd.first_instance = 0
			cmd.data.model = linalg.MATRIX4F32_IDENTITY
			cmd.data.color = {1, 1, 1, 1}

			for &attr in prim.attributes {
				mapped_attr := ACCESSOR_MAP[attr.type]
				if mapped_attr == .None {continue}

				slice := res.attributes[mapped_attr]
				if len(slice.cpu) == 0 {continue}

				if mapped_attr == .Position {
					num_comp := ACCESSOR_COMPONENT_COUNTS[attr.data.type]
					elem_size := size_of(f32) * num_comp
					cmd.vertex_offset = byte_offsets[mapped_attr] / elem_size
				}

				read_floats(slice, attr.data, &byte_offsets[mapped_attr])
			}

			if prim.indices != nil {
				cmd.first_index = u32(curr_idx_bytes / size_of(u32))
				cmd.index_count = u32(prim.indices.count)
				read_indices(res.indices, prim.indices, &curr_idx_bytes)
			}

			cmd_idx += 1
		}
	}

	return res
}
