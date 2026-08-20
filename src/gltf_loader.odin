package renderer

import "core:c"
import "core:os"
import "core:strings"
import "gpu/gpu"
import "vendor:cgltf"

Result :: union #shared_nil {
	os.Error,
	cgltf.result,
}

SEM_TO_ATTR_TYPE := [Attribute_Type]cgltf.attribute_type {
	.POSITION = .position,
	.NORMAL   = .normal,
	.UV       = .texcoord,
	.COLOR    = .color,
}

get_attribute :: proc(
	primitive: ^cgltf.primitive,
	attr_type: cgltf.attribute_type,
) -> ^cgltf.accessor {
	for attr in primitive.attributes do if attr.type == attr_type && attr.index == 0 do return attr.data
	return nil
}

load_geometry :: proc(
	path: string,
	r: ^Renderer,
	arena: ^gpu.Arena,
	allocator := context.allocator,
) -> Result {
	joined := resolve_asset_path(path, allocator) or_return
	defer delete(joined)

	file_data := os.read_entire_file(joined, allocator) or_return
	defer delete(file_data)

	data, res := cgltf.parse({}, raw_data(file_data), len(file_data))
	if res != .success {return res}
	defer cgltf.free(data)

	path_cstr := strings.clone_to_cstring(joined, allocator)
	defer delete(path_cstr)

	res = cgltf.load_buffers({}, data, path_cstr)
	if res != .success {return res}

	geo := &r.geometry

	present: Attribute_Set = {.POSITION, .NORMAL, .UV, .COLOR}
	prim_count := 0
	for mesh in data.meshes {
		for &prim in mesh.primitives {
			prim_count += 1
			if get_attribute(&prim, .position) == nil do return cgltf.result.invalid_gltf

			for sem in Attribute_Type do if get_attribute(&prim, SEM_TO_ATTR_TYPE[sem]) == nil do present -= {sem}
		}
	}
	if prim_count == 0 do return cgltf.result.invalid_gltf

	geo.attr_mask = present

	total_vertices, total_indices := 0, 0
	max_attr_size: [Attribute_Type]int
	for mesh in data.meshes {
		for &prim in mesh.primitives {
			pos := get_attribute(&prim, .position)
			total_vertices += int(pos.count)
			if prim.indices != nil {
				total_indices += int(prim.indices.count)
			} else {
				total_indices += int(pos.count)
			}
			for sem in present {
				acc := get_attribute(&prim, SEM_TO_ATTR_TYPE[sem])
				sz := int(cgltf.calc_size(acc.type, acc.component_type))
				if sz > max_attr_size[sem] do max_attr_size[sem] = sz
			}
		}
	}

	for sem in present do geo.attributes[sem] = gpu.arena_alloc_slice(arena, u8, total_vertices * max_attr_size[sem])

	geo.indices = gpu.arena_alloc_slice(arena, u32, total_indices)
	geo.draws = gpu.arena_alloc_slice(arena, gpu.Draw_Indexed_Indirect_Command, prim_count)

	v_offset, i_offset, p_idx := 0, 0, 0
	for mesh in data.meshes {
		for &prim in mesh.primitives {
			pos := get_attribute(&prim, .position)
			v_count := int(pos.count)
			i_count := int(prim.indices.count) if prim.indices != nil else v_count

			geo.draws.cpu[p_idx] = gpu.Draw_Indexed_Indirect_Command {
				index_count    = u32(i_count),
				instance_count = 1,
				first_index    = u32(i_offset),
				vertex_offset  = i32(v_offset),
				first_instance = 0,
			}

			for sem in present {
				acc := get_attribute(&prim, SEM_TO_ATTR_TYPE[sem])
				elem_size := int(cgltf.calc_size(acc.type, acc.component_type))
				float_count := uint((elem_size / 4) * v_count)
				dst := cast([^]f32)rawptr(
					uintptr(raw_data(geo.attributes[sem].cpu)) +
					uintptr(v_offset * max_attr_size[sem]),
				)
				_ = cgltf.accessor_unpack_floats(acc, dst, float_count)
			}

			if prim.indices != nil {
				dst := rawptr(
					uintptr(raw_data(geo.indices.cpu)) + uintptr(i_offset * size_of(u32)),
				)
				_ = cgltf.accessor_unpack_indices(prim.indices, dst, 4, uint(prim.indices.count))
			} else do for i in 0 ..< v_count do geo.indices.cpu[i_offset + i] = u32(i)


			v_offset += v_count
			i_offset += i_count
			p_idx += 1
		}
	}

	r.draw_count = gpu.arena_alloc(arena, u32)
	r.draw_count.cpu^ = u32(prim_count)

	return nil
}
