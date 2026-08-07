import "../shaders/shared/shared.slang";

struct VertRoot {
  float3 *positions;
  float4 *colors;
};

struct DrawRoot {
  float4x4 model;
  float4 color;
};

struct VSOut {
  float4 pos : SV_Position;
  float4 color : TEXCOORD0;
};

[shader("vertex")]
VSOut triangle_unlit_vert(uint vid: SV_VertexID,
                          GraphicsPipelineData<VertRoot, DrawRoot, void> data) {
  float3 p = data.vert.positions[vid];
  float4 world = mul(data.frag.model, float4(p, 1));

  VSOut o;
  o.pos = world;
  o.color = data.vert.colors[vid] * data.frag.color;
  return o;
}

[shader("fragment")]
float4 triangle_unlit_frag(VSOut input,
                           GraphicsPipelineData<void, DrawRoot, void> data)
    : SV_Target {
  return input.color;
}
