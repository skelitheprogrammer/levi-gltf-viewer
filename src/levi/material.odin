package levi

import "core:fmt"
import "core:mem"

Material_Type_ID :: distinct u32
Material_Handle :: distinct u32

INVALID_MATERIAL_TYPE :: Material_Type_ID(~u32(0))
INVALID_MATERIAL_HANDLE :: Material_Handle(~u32(0))

MAX_MATERIAL_SIZE :: 256

Material_Type_Info :: struct {
	vert: Shader_ID,
	frag: Shader_ID,
	size: u32,
}

Material_Asset :: struct {
	type_id: Material_Type_ID,
	data:    [MAX_MATERIAL_SIZE]u8,
}

register_material_type :: #force_inline proc(
	$T: typeid,
	eng: ^Engine,
	vert: Shader_ID,
	frag: Shader_ID,
	loc := #caller_location,
) -> (
	Material_Type_ID,
	Error,
) {
	return register_material_type_internal(eng, typeid_of(T), size_of(T), vert, frag, loc)
}

@(private)
register_material_type_internal :: proc(
	eng: ^Engine,
	tid: typeid,
	size: int,
	vert: Shader_ID,
	frag: Shader_ID,
	loc := #caller_location,
) -> (
	Material_Type_ID,
	Error,
) {
	if eng == nil || vert == INVALID_SHADER_ID || frag == INVALID_SHADER_ID {
		log_error(.Invalid_Argument, loc)
		return INVALID_MATERIAL_TYPE, .Invalid_Argument
	}
	if size > MAX_MATERIAL_SIZE {
		log_error(.Material_Too_Large, loc)
		return INVALID_MATERIAL_TYPE, .Material_Too_Large
	}

	append(
		&eng.renderer.material_types,
		Material_Type_Info{vert = vert, frag = frag, size = u32(size)},
	)

	id := Material_Type_ID(u32(len(eng.renderer.material_types) - 1))
	log_levi(fmt.tprintf("Material type %v registered (size: %v bytes).", id, size), loc)
	return id, .None
}

create_material_asset :: #force_inline proc(
	eng: ^Engine,
	mat_type: Material_Type_ID,
	data: $T,
	loc := #caller_location,
) -> (
	Material_Handle,
	Error,
) {
	if size_of(T) > MAX_MATERIAL_SIZE {
		log_error(.Material_Too_Large, loc)
		return INVALID_MATERIAL_HANDLE, .Material_Too_Large
	}
	data_ptr := data
	return create_material_asset_internal(eng, mat_type, &data_ptr, size_of(T), loc)
}

@(private)
create_material_asset_internal :: proc(
	eng: ^Engine,
	mat_type: Material_Type_ID,
	data_ptr: rawptr,
	size: int,
	loc := #caller_location,
) -> (
	Material_Handle,
	Error,
) {
	if eng == nil || mat_type == INVALID_MATERIAL_TYPE {
		log_error(.Invalid_Argument, loc)
		return INVALID_MATERIAL_HANDLE, .Invalid_Argument
	}

	asset: Material_Asset
	asset.type_id = mat_type
	mem.copy(&asset.data, data_ptr, size)

	append(&eng.renderer.material_assets, asset)

	handle := Material_Handle(u32(len(eng.renderer.material_assets) - 1))
	log_levi(fmt.tprintf("Material asset %v created.", handle), loc)
	return handle, .None
}

update_material_asset :: #force_inline proc(
	eng: ^Engine,
	handle: Material_Handle,
	data: $T,
	loc := #caller_location,
) -> Error {
	if size_of(T) > MAX_MATERIAL_SIZE {
		log_error(.Material_Too_Large, loc)
		return .Material_Too_Large
	}
	data_ptr := data
	return update_material_asset_internal(eng, handle, &data_ptr, size_of(T), loc)
}

@(private)
update_material_asset_internal :: proc(
	eng: ^Engine,
	handle: Material_Handle,
	data_ptr: rawptr,
	size: int,
	loc := #caller_location,
) -> Error {
	if eng == nil || handle == INVALID_MATERIAL_HANDLE do return .Invalid_Argument
	idx := u32(handle)
	if idx >= u32(len(eng.renderer.material_assets)) do return .Invalid_ID

	mem.copy(&eng.renderer.material_assets[idx].data, data_ptr, size)
	return .None
}
