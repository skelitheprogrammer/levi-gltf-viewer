package levi

import "../gpu/gpu"
import "core:fmt"

Shader_ID :: distinct u32
INVALID_SHADER_ID :: Shader_ID(~u32(0))


create_shader :: proc(
	eng: ^Engine,
	spirv: []u32,
	stage: gpu.Shader_Type_Graphics,
	loc := #caller_location,
) -> (
	id: Shader_ID,
	err: Error,
) {
	if eng == nil || len(spirv) == 0 {
		log_error(.Invalid_Argument, loc)
		return INVALID_SHADER_ID, .Invalid_Argument
	}

	shader := gpu.shader_create(spirv, stage)
	if shader == {} {
		log_error(.Shader_Load_Failed, loc)
		return INVALID_SHADER_ID, .Shader_Load_Failed
	}

	append(&eng.renderer.shaders, shader)
	id = Shader_ID(u32(len(eng.renderer.shaders) - 1))

	log_levi(fmt.tprintf("Shader %v (%v) creation complete.", id, stage), loc)
	return id, .None
}
