import "../shaders/shared/shared.slang";

#define MAX_CLUSTERS 256

public struct ClusterDesc {
  public uint pos_page;
  public uint col_page;
  public uint idx_page;
  public uint index_count;
  public float3 bounds_min;
  public float3 bounds_max;
}

public struct IndirectData {

  public uint indexCount;
  public uint instanceCount;
  public uint firstIndex;
  public int vertexOffset;
  public uint firstInstance;

  public uint pos_page;
  public uint col_page;
  public uint idx_page;
}

public struct CullRootData {
  public uint64_t cluster_table;
  public uint64_t out_cmds;
  public uint64_t out_count;
  public float4x4 view_proj;
}

[shader("compute")]
[numthreads(64, 1, 1)]
void cs_cull(uint3 global_invocation_id: SV_DispatchThreadID,
             uniform ComputePipelineData<CullRootData> pipeline_data) {
  CullRootData *root = pipeline_data.data;

  uint cluster_id = global_invocation_id.x;
  if (cluster_id >= MAX_CLUSTERS)
    return;

  ClusterDesc *table = (ClusterDesc *)root->cluster_table;
  IndirectData *out_cmds = (IndirectData *)root->out_cmds;
  uint *out_count = (uint *)root->out_count;

  ClusterDesc desc = table[cluster_id];

  if (desc.pos_page == 0xFFFFFFFF)
    return;

  float4 row0 = root->view_proj[0];
  float4 row1 = root->view_proj[1];
  float4 row2 = root->view_proj[2];
  float4 row3 = root->view_proj[3];

  float4 planes[6];
  planes[0] = row3 + row0;
  planes[1] = row3 - row0;
  planes[2] = row3 + row1;
  planes[3] = row3 - row1;
  planes[4] = row3 + row2;
  planes[5] = row3 - row2;

  float3 aabb_min = desc.bounds_min;
  float3 aabb_max = desc.bounds_max;

  bool visible = true;
  for (int i = 0; i < 6; i++) {
    float3 p_vertex = float3(planes[i].x >= 0.0 ? aabb_max.x : aabb_min.x,
                             planes[i].y >= 0.0 ? aabb_max.y : aabb_min.y,
                             planes[i].z >= 0.0 ? aabb_max.z : aabb_min.z);
    if (dot(float4(p_vertex, 1.0), planes[i]) < 0.0) {
      visible = false;
      break;
    }
  }

  if (visible) {
    uint draw_idx;
    InterlockedAdd(out_count[0], 1, draw_idx);

    IndirectData cmd;
    cmd.indexCount = desc.index_count;
    cmd.instanceCount = 1;
    cmd.firstIndex = 0;
    cmd.vertexOffset = 0;
    cmd.firstInstance = 0;

    cmd.pos_page = desc.pos_page;
    cmd.col_page = desc.col_page;
    cmd.idx_page = desc.idx_page;

    out_cmds[draw_idx] = cmd;
  }
}
