package renderer

import "core:os"

resolve_asset_path :: proc(
	path: string,
	allocator := context.allocator,
) -> (
	joined: string,
	err: os.Error,
) {
	exe_path := os.get_executable_directory(allocator) or_return
	defer delete(exe_path)

	joined = os.join_path({exe_path, path}, allocator) or_return
	return joined, os.ERROR_NONE
}
