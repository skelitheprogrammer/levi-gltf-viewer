package levi

spawn_instance :: proc(eng: ^Engine, mesh: Mesh_ID, material: Material_ID) -> Instance_ID {
	id := Instance_ID(u32(len(eng.renderer.instances)))
	append(&eng.renderer.instances, Instance_Data{mesh_id = mesh, material_id = material})
	return id
}

destroy_instance :: proc(eng: ^Engine, id: Instance_ID) {
	last := u32(len(eng.renderer.instances)) - 1
	idx := u32(id)
	if idx != last {
		eng.renderer.instances[idx] = eng.renderer.instances[last]
	}
	unordered_remove(&eng.renderer.instances, last)
}
