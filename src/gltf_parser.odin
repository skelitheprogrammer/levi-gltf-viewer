package main

import levi "../src/levi"
import "core:fmt"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:path/filepath"
import "core:strings"
import "vendor:cgltf"

// ============================================================================
// Scene Types
// ============================================================================

GLTF_Instance :: struct {
	mesh_id:    levi.Mesh_ID,
	mat_handle: levi.Material_Handle,
	transform:  [16]f32,
	name:       string,
}

GLTF_Scene :: struct {
	instances: [dynamic]GLTF_Instance,
}

destroy_gltf_scene :: proc(scene: ^GLTF_Scene) {
	for inst in scene.instances {
		delete(inst.name)
	}
	delete(scene.instances)
	scene^ = {}
}

// ============================================================================
// Zero-Copy Mappers
// ============================================================================

@(rodata)
CGLTF_COMPONENT_TO_VERTEX_FORMAT: [cgltf.component_type]levi.Vertex_Format = {
	.invalid = .Float32,
	.r_8     = .Int8,
	.r_8u    = .Uint8,
	.r_16    = .Int16,
	.r_16u   = .Uint16,
	.r_32u   = .Uint32,
	.r_32f   = .Float32,
}

@(rodata)
CGLTF_TYPE_TO_COMPONENT_COUNT: [cgltf.type]u32 = {
	.invalid = 0,
	.scalar  = 1,
	.vec2    = 2,
	.vec3    = 3,
	.vec4    = 4,
	.mat2    = 4,
	.mat3    = 9,
	.mat4    = 16,
}

// ============================================================================
// Zero-Copy Data Extraction
// ============================================================================

@(private)
get_attribute_raw_data :: proc(
	acc: ^cgltf.accessor,
) -> (
	data: []u8,
	desc: levi.Vertex_Attribute_Desc,
	err: levi.Error,
) {
	if acc == nil ||
	   acc.buffer_view == nil ||
	   acc.buffer_view.buffer == nil ||
	   acc.buffer_view.buffer.data == nil {
		return nil, {}, levi.Error.Invalid_Argument
	}

	format := CGLTF_COMPONENT_TO_VERTEX_FORMAT[acc.component_type]
	comp_count := CGLTF_TYPE_TO_COMPONENT_COUNT[acc.type]

	elem_size := int(cgltf.calc_size(acc.type, acc.component_type))
	stride := int(acc.stride)
	if stride == 0 {
		stride = elem_size
	}

	total_bytes := stride * int(acc.count)

	base_ptr := cast(^u8)(acc.buffer_view.buffer.data)
	offset := uintptr(acc.offset + acc.buffer_view.offset)
	ptr := mem.ptr_offset(base_ptr, offset)

	data_slice := mem.slice_ptr(ptr, total_bytes)

	desc = levi.Vertex_Attribute_Desc {
		format          = format,
		component_count = comp_count,
		offset          = 0,
		stride          = u32(stride),
		normalized      = bool(acc.normalized),
	}

	return data_slice, desc, levi.Error.None
}

@(private)
get_indices_raw_data :: proc(
	acc: ^cgltf.accessor,
) -> (
	indices: []u32,
	allocated: bool,
	err: levi.Error,
) {
	if acc == nil ||
	   acc.buffer_view == nil ||
	   acc.buffer_view.buffer == nil ||
	   acc.buffer_view.buffer.data == nil {
		return nil, false, levi.Error.Invalid_Argument
	}

	if acc.component_type == .r_32u {
		stride := int(acc.stride)
		if stride == 0 {
			stride = 4
		}

		if stride == 4 {
			base_ptr := cast(^u8)(acc.buffer_view.buffer.data)
			offset := uintptr(acc.offset + acc.buffer_view.offset)
			ptr := cast(^u32)mem.ptr_offset(base_ptr, offset)

			indices_slice := mem.slice_ptr(ptr, int(acc.count))
			return indices_slice, false, levi.Error.None
		}
	}

	indices = make([]u32, int(acc.count))
	unpacked := cgltf.accessor_unpack_indices(acc, raw_data(indices), 4, uint(acc.count))
	if unpacked == 0 {
		delete(indices)
		return nil, false, levi.Error.Invalid_Argument
	}

	return indices, true, levi.Error.None
}

// ============================================================================
// Parsing Logic
// ============================================================================

@(private)
parse_primitive :: proc(
	eng: ^levi.Engine,
	prim: ^cgltf.primitive,
) -> (
	mesh_id: levi.Mesh_ID,
	err: levi.Error,
) {
	pos_acc: ^cgltf.accessor
	for attr in prim.attributes {
		if attr.type == .position && attr.index == 0 {
			pos_acc = attr.data
			break
		}
	}

	if pos_acc == nil {
		return levi.INVALID_MESH_ID, levi.Error.Invalid_Format
	}

	attrs: [levi.Vertex_Attribute][]u8
	descs: [levi.Vertex_Attribute]levi.Vertex_Attribute_Desc

	pos_data, pos_desc, pos_err := get_attribute_raw_data(pos_acc)
	if pos_err != .None do return levi.INVALID_MESH_ID, pos_err
	attrs[.Position] = pos_data
	descs[.Position] = pos_desc

	for attr in prim.attributes {
		if attr.type == .normal && attr.index == 0 {
			normal_data, normal_desc, normal_err := get_attribute_raw_data(attr.data)
			if normal_err == .None {
				attrs[.Normal] = normal_data
				descs[.Normal] = normal_desc
			}
			break
		}
	}

	for attr in prim.attributes {
		if attr.type == .texcoord && attr.index == 0 {
			uv_data, uv_desc, uv_err := get_attribute_raw_data(attr.data)
			if uv_err == .None {
				attrs[.UV0] = uv_data
				descs[.UV0] = uv_desc
			}
			break
		}
	}

	for attr in prim.attributes {
		if attr.type == .color && attr.index == 0 {
			color_data, color_desc, color_err := get_attribute_raw_data(attr.data)
			if color_err == .None {
				attrs[.Color] = color_data
				descs[.Color] = color_desc
			}
			break
		}
	}

	indices: []u32
	indices_allocated := false
	if prim.indices != nil {
		idx_err: levi.Error
		indices, indices_allocated, idx_err = get_indices_raw_data(prim.indices)
		if idx_err != .None {
			return levi.INVALID_MESH_ID, idx_err
		}
	} else {
		vertex_count := int(pos_acc.count)
		indices = make([]u32, vertex_count)
		indices_allocated = true
		for i in 0 ..< vertex_count do indices[i] = u32(i)
	}
	defer if indices_allocated do delete(indices)

	mesh_desc := levi.Mesh_Desc {
		attributes      = attrs,
		attribute_descs = descs,
		indices         = indices,
	}

	return levi.create_mesh(eng, &mesh_desc)
}

@(private)
parse_material :: proc(
	eng: ^levi.Engine,
	mat: ^cgltf.material,
	mat_type: levi.Material_Type_ID,
) -> (
	handle: levi.Material_Handle,
	err: levi.Error,
) {
	pbr := mat.pbr_metallic_roughness

	custom_mat := Custom_Material {
		color = pbr.base_color_factor,
		time  = 0.0,
	}

	return levi.create_material_asset(eng, mat_type, custom_mat)
}

@(private)
extract_instances :: proc(
	scene: ^GLTF_Scene,
	node: ^cgltf.node,
	parent_transform: matrix[4, 4]f32,
	data: ^cgltf.data,
	mesh_ids: [][]levi.Mesh_ID,
	mat_handles: []levi.Material_Handle,
) {
	local_mat: matrix[4, 4]f32
	if node.has_matrix {
		local_mat = transmute(matrix[4, 4]f32)node.matrix_
	} else {
		trans := linalg.Vector3f32(node.translation)
		rot := transmute(linalg.Quaternionf32)node.rotation
		scale := linalg.Vector3f32(node.scale)
		local_mat = linalg.matrix4_from_trs_f32(trans, rot, scale)
	}

	world_mat := linalg.mul(parent_transform, local_mat)

	if node.mesh != nil {
		mesh_idx := cgltf.mesh_index(data, node.mesh)
		if int(mesh_idx) < len(mesh_ids) {
			for j in 0 ..< len(node.mesh.primitives) {
				prim := node.mesh.primitives[j]
				if j < len(mesh_ids[mesh_idx]) {
					mesh_id := mesh_ids[mesh_idx][j]

					mat_handle: levi.Material_Handle = levi.INVALID_MATERIAL_HANDLE
					if prim.material != nil {
						mat_idx := cgltf.material_index(data, prim.material)
						if int(mat_idx) < len(mat_handles) {
							mat_handle = mat_handles[mat_idx]
						}
					}

					inst := GLTF_Instance {
						mesh_id    = mesh_id,
						mat_handle = mat_handle,
						transform  = transmute([16]f32)world_mat,
						name       = cast(string)node.name,
					}
					append(&scene.instances, inst)
				}
			}
		}
	}

	for child in node.children {
		extract_instances(scene, child, world_mat, data, mesh_ids, mat_handles)
	}
}

// ============================================================================
// Main Entry Point
// ============================================================================

load_gltf :: proc(
	eng: ^levi.Engine,
	file_path: string,
	mat_type: levi.Material_Type_ID,
) -> (
	scene: GLTF_Scene,
	err: levi.Error,
) {
	log.info(fmt.tprintf("[GLTF] Loading: %v", file_path))

	path_cstr := strings.clone_to_cstring(file_path)
	defer delete(path_cstr)

	data, res := cgltf.parse_file({}, path_cstr)
	if res != .success {
		log.error(fmt.tprintf("[GLTF] Parse failed: %v", res))
		return {}, levi.Error.Invalid_Argument
	}
	defer cgltf.free(data)

	dir := filepath.dir(file_path)
	dir_cstr := strings.clone_to_cstring(dir)
	defer delete(dir_cstr)

	res = cgltf.load_buffers({}, data, dir_cstr)
	if res != .success {
		log.error(fmt.tprintf("[GLTF] Buffer load failed: %v", res))
		return {}, levi.Error.Invalid_Argument
	}

	log.info(
		fmt.tprintf(
			"[GLTF] Parsed %v meshes, %v materials",
			len(data.meshes),
			len(data.materials),
		),
	)

	mat_handles := make([]levi.Material_Handle, len(data.materials))
	defer delete(mat_handles)

	for i in 0 ..< len(data.materials) {
		mat := &data.materials[i]
		handle, mat_err := parse_material(eng, mat, mat_type)
		if mat_err != .None {
			log.error("[GLTF] Material parse failed")
			return {}, mat_err
		}
		mat_handles[i] = handle
	}

	mesh_ids := make([][]levi.Mesh_ID, len(data.meshes))
	defer {
		for m in mesh_ids do delete(m)
		delete(mesh_ids)
	}

	for i in 0 ..< len(data.meshes) {
		mesh := &data.meshes[i]
		mesh_ids[i] = make([]levi.Mesh_ID, len(mesh.primitives))
		for j in 0 ..< len(mesh.primitives) {
			prim := &mesh.primitives[j]
			mesh_id, mesh_err := parse_primitive(eng, prim)
			if mesh_err != .None {
				log.error("[GLTF] Primitive parse failed")
				return {}, mesh_err
			}
			mesh_ids[i][j] = mesh_id
		}
	}

	if data.scene != nil {
		identity := linalg.MATRIX4F32_IDENTITY
		for i in 0 ..< len(data.scene.nodes) {
			node := data.scene.nodes[i]
			extract_instances(&scene, node, identity, data, mesh_ids, mat_handles)
		}
	}

	log.info(fmt.tprintf("[GLTF] Extracted %v instances", len(scene.instances)))
	log.info("[GLTF] Load complete")

	return scene, levi.Error.None
}
