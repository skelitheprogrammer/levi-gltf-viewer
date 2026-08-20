import "../shaders/shared/shared.slang";


struct VertexData {
  float4x4 viewProj;
  uint64_t models;
  uint64_t attributes[4];
};

struct FragmentData {
  float4 baseColor;
};

struct VSInput {
  uint vertexID : SV_VertexID;
};

struct VSOutput {
  float4 pos : SV_Position;
  float3 normal : NORMAL;
};

[shader("vertex")]
VSOutput vertMain(VSInput input,
                  GraphicsPipelineData<VertexData, FragmentData> pipeline) {
  VSOutput output;

  float3 *positions = (float3 *)pipeline.vert->attributes[0];
  float3 *normals   = (float3 *)pipeline.vert->attributes[1];

  float3 pos    = positions[input.vertexID];
  float3 normal = normals[input.vertexID];

  output.pos    = mul(pipeline.vert->viewProj, float4(pos, 1.0));
  output.normal = normal;

  return output;
}

struct PSInput {
  float4 pos : SV_Position;
  float3 normal : NORMAL;
};

[shader("fragment")]
float4 fragMain(PSInput input,
                GraphicsPipelineData<VertexData, FragmentData> pipeline) {
  float3 n = normalize(input.normal);
  float3 color = n * 0.5 + 0.5;
  return float4(color, 1.0);
}
