package levi

import "core:fmt"
import "core:log"

FLIGHT :: 3


Mesh_ID :: distinct u32
Material_Type_ID :: distinct u32
Material_Handle :: distinct u32
Shader_ID :: distinct u32
Instance_ID :: distinct u32

INVALID_MESH_ID :: Mesh_ID(~u32(0))
INVALID_MATERIAL_TYPE :: Material_Type_ID(~u32(0))
INVALID_MATERIAL_HANDLE :: Material_Handle(~u32(0))
INVALID_SHADER_ID :: Shader_ID(~u32(0))
INVALID_INSTANCE_ID :: Instance_ID(~u32(0))


Error :: enum {
	None,
	Out_Of_Memory,
	Invalid_ID,
	Shader_Load_Failed,
	Mesh_Creation_Failed,
	Material_Too_Large,
	Invalid_Format,
	Invalid_Argument,
}

@(rodata)
Error_Strings: [Error]string = {
	.None                 = "None",
	.Out_Of_Memory        = "Out of memory",
	.Invalid_ID           = "Invalid ID",
	.Shader_Load_Failed   = "Shader load failed",
	.Mesh_Creation_Failed = "Mesh creation failed",
	.Material_Too_Large   = "Material struct exceeds max size",
	.Invalid_Format       = "Invalid vertex format",
	.Invalid_Argument     = "Invalid argument",
}

error_string :: #force_inline proc(err: Error) -> string {
	return Error_Strings[err]
}

@(private)
log_levi :: proc(msg: string, loc := #caller_location) {
	log.info(fmt.tprintf("[LEVI %v:%v] %v", loc.file_path, loc.line, msg))
}

@(private)
log_error :: proc(err: Error, loc := #caller_location) {
	log.error(fmt.tprintf("[LEVI ERROR %v:%v] %v", loc.file_path, loc.line, error_string(err)))
}
