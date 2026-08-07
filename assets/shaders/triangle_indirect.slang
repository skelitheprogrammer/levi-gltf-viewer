import "../shaders/shared/shared.slang";

struct VertexOutput {
  float4 pos : SV_Position;
  float4 color : TEXCOORD0;
};

struct VertexInput {
  float4 pos;
  float4 col;
};

struct VertexData {
  VertexInput *vertices;
  float4x4 view_proj;
};

struct DrawUserData {
  float4x4 model;
  float4 color;
};

[shader("vertex")]
VertexOutput triangle_indirect_unlit_vert(
    uint vert_id: SV_VertexID,
    GraphicsPipelineData<VertexData, void, DrawUserData> pipeline) {
  VertexInput v = pipeline.vert.vertices[vert_id];

  VertexOutput out;

  out.pos = mul(pipeline.vert.view_proj, mul(pipeline.drawData.model, v.pos));
  out.color = v.col * pipeline.drawData.color;
  return out;
}

[shader("fragment")]
float4 triangle_indirect_unlit_frag(VertexOutput input) : SV_Target {
  return input.color;
}
