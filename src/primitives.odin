package main
create_triangle_mesh :: proc() -> Mesh {
	@(static) TRI_POS := [3][4]f32{{-.5, -.5, 0, 1}, {0, .5, 0, 1}, {.5, -.5, 0, 1}}
	@(static) TRI_COL := [3][4]f32{{1, 0, 0, 1}, {0, 1, 0, 1}, {0, 0, 1, 1}}
	@(static) TRI_IDX := [3]u32{0, 1, 2}

	mesh: Mesh
	mesh[.POS] = Stream {
		data = raw_data(TRI_POS[:]),
		len  = len(TRI_POS),
		size = GPU_Stream_Sizes[.POS],
	}
	mesh[.COL] = Stream {
		data = raw_data(TRI_COL[:]),
		len  = len(TRI_COL),
		size = GPU_Stream_Sizes[.COL],
	}
	mesh[.IDX] = Stream {
		data = raw_data(TRI_IDX[:]),
		len  = len(TRI_IDX),
		size = GPU_Stream_Sizes[.IDX],
	}
	return mesh
}
