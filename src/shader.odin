package renderer

import "core:fmt"
import "core:mem"
import "core:os"
import "gpu/gpu"

Shader_Pair :: [gpu.Shader_Type_Graphics]gpu.Shader

load_spirv :: proc(path: string, allocator := context.allocator) -> (words: []u32, err: os.Error) {
	resolved := resolve_asset_path(path, allocator) or_return
	defer delete(resolved)

	data := os.read_entire_file(resolved, allocator) or_return
	defer delete(data)

	if len(data) % 4 != 0 {
		fmt.eprintf("Invalid SPIR-V file (not 4-byte aligned): %s\n", resolved)
		return nil, .Invalid_File
	}

	word_count := len(data) / 4
	words = make([]u32, word_count, allocator)
	mem.copy(raw_data(words), raw_data(data), len(data))
	return words, os.ERROR_NONE
}


load_shader :: proc(
	path: string,
	type: gpu.Shader_Type_Graphics,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	shader: gpu.Shader,
	err: os.Error,
) {
	words := load_spirv(path, allocator) or_return
	defer delete(words)
	return gpu.shader_create(words, type, loc = loc), os.ERROR_NONE
}

load_shader_pair :: proc(
	vert_path: string,
	frag_path: string,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	pair: Shader_Pair,
	err: os.Error,
) {
	pair[.Vertex] = load_shader(vert_path, .Vertex, allocator, loc) or_return
	pair[.Fragment] = load_shader(frag_path, .Fragment, allocator, loc) or_return
	return pair, os.ERROR_NONE
}
