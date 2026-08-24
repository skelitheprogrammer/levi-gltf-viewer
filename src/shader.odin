package levi

import "core:fmt"
import "core:log"
import "core:os"
import "core:path"
import gpu "gpu/gpu"

Shader_Pair :: [gpu.Shader_Type_Graphics]gpu.Shader

Shader_System :: struct {
	sources: map[string]string,
	cache:   map[u32]Shader_Pair,
}

shader_system_init :: proc(sys: ^Shader_System, shader_dir: string) {
	files, ok := os.read_dir(shader_dir)
	if !ok {
		log.error("shader directory not found", "path", shader_dir)
		return
	}
	for file in files {
		if file.is_dir do continue
		ext := path.extension(file.name)
		if ext == ".slang" {
			name := path.base_name(file.name, false)
			sys.sources[name] = path.join({shader_dir, file.name})
		}
	}
	log.info("shader system initialised", "sources", len(sys.sources))
}

shader_system_destroy :: proc(sys: ^Shader_System) {
	for _, pair in sys.cache {
		gpu.shader_destroy(pair[.Vertex])
		gpu.shader_destroy(pair[.Fragment])
	}
}

generate_vertex_entry :: proc(mask: Vertex_Mask) -> string {
	has_nrm := Vertex_Attribute.Normal in mask
	has_uv := Vertex_Attribute.UV0 in mask
	return fmt.tprintf("vs_main<%s, %s>", has_nrm ? "true" : "false", has_uv ? "true" : "false")
}

shader_system_get_or_compile :: proc(sys: ^Shader_System, mask: Vertex_Mask) -> Shader_Pair {
	raw_mask := cast(u32)mask
	if p, ok := sys.cache[raw_mask]; ok do return p

	src_path, ok := sys.sources["unlit"]
	if !ok {
		log.error("unlit.slang not found in shader directory")
		return {}
	}

	vert_entry := generate_vertex_entry(mask)
	frag_entry := "fs_main"

	vert_spirv := compile_slang_stdout(src_path, vert_entry, "vertex")
	frag_spirv := compile_slang_stdout(src_path, frag_entry, "fragment")

	pair: Shader_Pair
	pair[.Vertex] = gpu.shader_create(vert_spirv, .Vertex, vert_entry)
	pair[.Fragment] = gpu.shader_create(frag_spirv, .Fragment, frag_entry)

	sys.cache[raw_mask] = pair
	log.info("shader compiled", "mask", raw_mask, "entry", vert_entry)
	return pair
}

compile_slang_stdout :: proc(source, entry, stage: string) -> []u32 {
	args := []string {
		"slangc",
		source,
		"-entry",
		entry,
		"-stage",
		stage,
		"-target",
		"spirv",
		"-profile",
		"glsl_460",
		"-o",
		"-",
	}

	read_end, write_end := os.pipe()
	saved_stdout := os.dup(1)
	os.dup2(write_end, 1)
	os.close(write_end)

	os.exec(args)

	os.dup2(saved_stdout, 1)
	os.close(saved_stdout)

	buf: [dynamic]byte
	tmp: [65536]byte
	for {
		n := os.read(read_end, tmp[:])
		if n <= 0 do break
		append(&buf, tmp[:n])
	}
	os.close(read_end)

	return cast([]u32)buf[:]
}
