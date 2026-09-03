package levi

import "../gpu/gpu"

create_shader :: proc(eng: ^Engine, data: []u32, type: gpu.Shader_Type_Graphics) -> Shader_ID {
	shader := gpu.shader_create(data, type)
	id := Shader_ID(u32(len(eng.renderer.shaders)))
	append(&eng.renderer.shaders, shader)
	return id
}

create_material :: proc(
	eng: ^Engine,
	vert: Shader_ID,
	frag: Shader_ID,
	params_size: u32,
) -> Material_ID {
	id := Material_ID(u32(len(eng.renderer.materials)))
	append(
		&eng.renderer.materials,
		Material_Template{vert = vert, frag = frag, params_size = params_size},
	)
	return id
}
