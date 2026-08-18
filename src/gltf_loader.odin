package renderer

import "core:mem"
import "core:os"
import "core:strings"
import "gpu/gpu"
import cg "vendor:cgltf"

Result :: union #shared_nil {
	os.Error,
	cg.result,
}

load_to_staging :: proc(
	path: string,
	renderer: ^Renderer,
	arena: ^gpu.Arena,
	allocator := context.allocator,
) -> Result {
	joined := resolve_asset_path(path, allocator) or_return
	defer delete(joined)

	file_data := os.read_entire_file(joined, allocator) or_return
	defer delete(file_data)

	data := cg.parse({}, raw_data(file_data), len(file_data)) or_return

	path_cstr := strings.clone_to_cstring(joined, allocator)
	defer delete(path_cstr)
	cg.load_buffers({}, data, path_cstr) or_return

	defer cg.free(data)

	process_meshes(renderer, data.meshes, arena)

	return nil
}

process_meshes :: proc(renderer: ^Renderer, meshes: []cg.mesh, arena: ^gpu.Arena) {
	pos_count: int = 0
	idx_count: int = 0
	attr_counts: [Attribute_Type]int

	for mesh in meshes {
		for prim in mesh.primitives {
			for attr in prim.attributes {
				acc := attr.data
				count := int(acc.count)
				#partial switch attr.type {
				case .position:
					pos_count += count
				case .normal:
					attr_counts[.NORMAL] += count
				case .color:
					attr_counts[.COLOR] += count
				case .texcoord:
					attr_counts[.UV] += count
				}
			}
			if prim.indices != nil do idx_count += int(prim.indices.count)
		}
	}

	if pos_count > 0 {
		renderer.positions = gpu.arena_alloc(arena, [3]f32, pos_count)
	}
	if idx_count > 0 {
		renderer.indices = gpu.arena_alloc(arena, u32, idx_count)
	}

	for t in Attribute_Type {
		count := attr_counts[t]

		if count == 0 {
			count = pos_count
		}

		if count > 0 {
			renderer.attributes[t] = gpu.arena_alloc(arena, u8, count * STRIDES[t])
		}
	}

	pos_offset: int = 0
	idx_offset: int = 0
	attr_offsets: [Attribute_Type]int = {}

	for mesh in meshes {
		for prim in mesh.primitives {
			for attr in prim.attributes {
				acc := attr.data
				count := int(acc.count)
				if count == 0 do continue

				bv := acc.buffer_view
				if bv == nil do continue

				src_ptr := &cg.buffer_view_data(bv)[int(acc.offset)]
				elem_size := int(cg.calc_size(acc.type, acc.component_type))
				stride := int(acc.stride)
				if stride == 0 {stride = elem_size}

				dst_ptr: ^u8
				dst_stride: int

				#partial switch attr.type {
				case .position:
					dst_ptr = cast(^u8)&renderer.positions.cpu[pos_offset]
					dst_stride = size_of([3]f32)
					pos_offset += count
				case .normal:
					dst_ptr = &renderer.attributes[.NORMAL].cpu[attr_offsets[.NORMAL]]
					dst_stride = STRIDES[.NORMAL]
					attr_offsets[.NORMAL] += count * STRIDES[.NORMAL]
				case .color:
					dst_ptr = &renderer.attributes[.COLOR].cpu[attr_offsets[.COLOR]]
					dst_stride = STRIDES[.COLOR]
					attr_offsets[.COLOR] += count * STRIDES[.COLOR]
				case .texcoord:
					dst_ptr = &renderer.attributes[.UV].cpu[attr_offsets[.UV]]
					dst_stride = size_of([2]f32)
					attr_offsets[.UV] += count * STRIDES[.UV]
				case:
					continue
				}

				if stride == elem_size && dst_stride == elem_size {
					mem.copy(dst_ptr, src_ptr, elem_size * count)
				} else {
					for i in 0 ..< count {
						src_elem := mem.ptr_offset(src_ptr, i * stride)
						dst_elem := mem.ptr_offset(dst_ptr, i * dst_stride)
						mem.copy(dst_elem, src_elem, elem_size)
					}
				}
			}

			if prim.indices != nil {
				acc := prim.indices
				count := int(acc.count)
				if count == 0 do continue

				bv := acc.buffer_view
				if bv == nil do continue

				src_ptr := &cg.buffer_view_data(bv)[int(acc.offset)]
				elem_size := int(cg.calc_size(acc.type, acc.component_type))
				stride := int(acc.stride)
				if stride == 0 {stride = elem_size}

				// FIX 3: Explicitly cast to u32 to prevent index corruption
				if acc.component_type == .r_16u {
					for i in 0 ..< count {
						src_val := cast(^u16)mem.ptr_offset(src_ptr, i * stride)
						renderer.indices.cpu[idx_offset + i] = u32(src_val^)
					}
				} else if acc.component_type == .r_8u {
					for i in 0 ..< count {
						src_val := cast(^u8)mem.ptr_offset(src_ptr, i * stride)
						renderer.indices.cpu[idx_offset + i] = u32(src_val^)
					}
				} else {
					// Assume u32 fallback
					dst_ptr := cast(^u8)&renderer.indices.cpu[idx_offset]
					if stride == elem_size {
						mem.copy(dst_ptr, src_ptr, elem_size * count)
					} else {
						for i in 0 ..< count {
							src_elem := mem.ptr_offset(src_ptr, i * stride)
							dst_elem := mem.ptr_offset(dst_ptr, i * size_of(u32))
							mem.copy(dst_elem, src_elem, elem_size)
						}
					}
				}
				idx_offset += count
			}
		}
	}

	for t in Attribute_Type {
		if attr_counts[t] == 0 && len(renderer.attributes[t].cpu) > 0 {
			byte_len := len(renderer.attributes[t].cpu)
			elem_count := byte_len / STRIDES[t]
			ptr := cast(^u8)raw_data(renderer.attributes[t].cpu)

			for i in 0 ..< elem_count {
				dst := mem.ptr_offset(ptr, i * STRIDES[t])

				switch t {
				case .NORMAL:
					n := [3]f32{0, 1, 0}
					mem.copy(dst, &n[0], STRIDES[t])
				case .UV:
					uv := [2]f32{0, 0}
					mem.copy(dst, &uv[0], STRIDES[t])
				case .COLOR:
					c := [4]f32{1, 1, 1, 1}
					mem.copy(dst, &c[0], STRIDES[t])
				}
			}
		}
	}
}
