package levi

import "core:fmt"

Instance_Data :: struct #align (16) {
	mesh_id:    Mesh_ID,
	mat_handle: Material_Handle,
	transform:  [16]f32,
}

spawn_instance :: #force_inline proc(
	eng: ^Engine,
	mesh: Mesh_ID,
	mat: Material_Handle,
	transform: [16]f32,
	loc := #caller_location,
) -> (
	Instance_ID,
	Error,
) {
	if eng == nil || mesh == INVALID_MESH_ID || mat == INVALID_MATERIAL_HANDLE {
		log_error(.Invalid_Argument, loc)
		return INVALID_INSTANCE_ID, .Invalid_Argument
	}

	id := Instance_ID(u32(len(eng.renderer.instances)))
	append(
		&eng.renderer.instances,
		Instance_Data{mesh_id = mesh, mat_handle = mat, transform = transform},
	)

	log_levi(fmt.tprintf("Instance %v spawned.", id), loc)
	return id, .None
}

destroy_instance :: #force_inline proc(
	eng: ^Engine,
	id: Instance_ID,
	loc := #caller_location,
) -> Error {
	if eng == nil {
		log_error(.Invalid_Argument, loc)
		return .Invalid_Argument
	}

	idx := u32(id)
	last := u32(len(eng.renderer.instances)) - 1

	if idx > last {
		log_error(.Invalid_ID, loc)
		return .Invalid_ID
	}

	if idx != last {
		eng.renderer.instances[idx] = eng.renderer.instances[last]
	}
	unordered_remove(&eng.renderer.instances, last)

	log_levi(fmt.tprintf("Instance %v destroyed.", id), loc)
	return .None
}
