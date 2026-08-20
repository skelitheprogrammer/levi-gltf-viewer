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

attr_semantic :: proc(t: cgltf.attribute_type) -> (Attribute_Semantic, bool) {
	#partial switch t {
	case .position:
		return .POSITION, true
	case .normal:
		return .NORMAL, true
	case .texcoord:
		return .UV, true
	case .color:
		return .COLOR, true
	}
	return .POSITION, false
}

get_attribute :: proc(
	primitive: ^cgltf.primitive,
	attr_type: cgltf.attribute_type,
) -> ^cgltf.accessor {
	for attr in primitive.attributes {
		if attr.type == attr_type && attr.index == 0 {
			return attr.data
		}
	}
	return nil
}

load_geometry :: proc(
	path: string,
	geo: ^Geometry,
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

	total_vertices, total_indices, prim_count := 0, 0, 0
	max_attr_size: [Attribute_Semantic]int

	for mesh in data.meshes {
		for &prim in mesh.primitives {
			for attr in prim.attributes {
				sem, ok := attr_semantic(attr.type)
				if !ok || attr.index != 0 {continue}
				sz := int(cgltf.calc_size(attr.data.type, attr.data.component_type))
				if sz > max_attr_size[sem] {max_attr_size[sem] = sz}
			}
			if pos := get_attribute(&prim, .position); pos != nil {
				total_vertices += int(pos.count)
			}
			if prim.indices != nil {total_indices += int(prim.indices.count)}
			prim_count += 1
		}
	}

	for sem in Attribute_Semantic {
		geo.attributes[sem] = gpu.arena_alloc_slice(arena, u8, total_vertices * max_attr_size[sem])
	}
	geo.indices = gpu.arena_alloc_slice(arena, u32, total_indices)
	geo.draws = gpu.arena_alloc_slice(arena, gpu.Draw_Indexed_Indirect_Command, prim_count)

	v_offset, i_offset, p_idx := 0, 0, 0

	for mesh in data.meshes {
		for &prim in mesh.primitives {
			pos := get_attribute(&prim, .position)
			idx := prim.indices

			v_count := int(pos.count) if pos != nil else 0
			i_count := int(idx.count) if idx != nil else 0

			geo.draws.cpu[p_idx] = gpu.Draw_Indexed_Indirect_Command {
				index_count    = u32(i_count),
				instance_count = 1,
				first_index    = u32(i_offset),
				vertex_offset  = i32(v_offset),
				first_instance = 0,
			}

			for attr in prim.attributes {
				sem, ok := attr_semantic(attr.type)
				if !ok || attr.index != 0 {continue}

				acc := attr.data
				elem_size := int(cgltf.calc_size(acc.type, acc.component_type))
				float_count := uint((elem_size / 4) * v_count)

				dst := cast([^]f32)rawptr(
					uintptr(raw_data(geo.attributes[sem].cpu)) +
					uintptr(v_offset * max_attr_size[sem]),
				)
				_ = cgltf.accessor_unpack_floats(acc, dst, float_count)
			}

			if idx != nil {
				dst := rawptr(
					uintptr(raw_data(geo.indices.cpu)) + uintptr(i_offset * size_of(u32)),
				)
				_ = cgltf.accessor_unpack_indices(idx, dst, 4, uint(idx.count))
			}

			v_offset += v_count
			i_offset += i_count
			p_idx += 1
		}
	}
	return nil
}
