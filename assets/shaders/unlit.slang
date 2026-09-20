import "../shaders/shared/shared.slang";

#define PAGE_SIZE_VERTS 128
#define PAGE_SIZE_IDX 128

public struct VirtualGeometryData {
  public uint64_t pos_pool;
  public uint64_t col_pool;
  public uint64_t idx_pool;
  public float4x4 view_proj;
}

public struct DrawUserData {
  public uint pos_page;
  public uint col_page;
  public uint idx_page;
}

struct VSOutput {
  float4 position : SV_Position;
  float4 color : COLOR0;
}

[shader("vertex")]
VSOutput vertMain(uint vertex_id: SV_VertexID,
                 GraphicsPipelineData<VirtualGeometryData, void, DrawUserData>
                     pipeline_data) {
  VSOutput output;

  VirtualGeometryData *root = pipeline_data.vert;

  DrawUserData draw_data = pipeline_data.drawData;

  float4 *pos_pool = (float4 *)root->pos_pool;
  float4 *col_pool = (float4 *)root->col_pool;
  uint *idx_pool = (uint *)root->idx_pool;

  uint local_idx = vertex_id;

  uint base_idx_offset = draw_data.idx_page * PAGE_SIZE_IDX;
  uint actual_vertex_idx = idx_pool[base_idx_offset + local_idx];

  uint base_vert_offset = draw_data.pos_page * PAGE_SIZE_VERTS;
  float4 pos = pos_pool[base_vert_offset + actual_vertex_idx];

  uint base_col_offset = draw_data.col_page * PAGE_SIZE_VERTS;
  float4 col = col_pool[base_col_offset + actual_vertex_idx];

  output.position = mul(root->view_proj, pos);
  output.color = col;

  return output;
}

[shader("fragment")]
float4 fragMain(VSOutput input) : SV_Target { return input.color; }
