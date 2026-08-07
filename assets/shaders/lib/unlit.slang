import "../shared/shared.slang";

interface IProjection {
    float4 apply(float3 world_pos);
};

struct WithCamera : IProjection {
    float4x4 view_proj;
    float4 apply(float3 world_pos) {
        return mul(view_proj, float4(world_pos, 1));
    }
};

struct NoCamera : IProjection {
    float4 apply(float3 world_pos) {
        return float4(world_pos, 1);
    }
};

struct VertexData<bool hasUVs, TProj : IProjection> {
    float3* positions;
    Conditional<float2*, hasUVs> uvs;
    TProj proj;
};

struct DrawData<bool hasUVs> {
    float4x4 model;
    float4 color;
    Conditional<uint, hasUVs> tex_id;
    Conditional<uint, hasUVs> sampler_id;
};

struct VSOut<bool hasUVs> {
    float4 pos   : SV_Position;
    float4 color : TEXCOORD0;
    Conditional<float2, hasUVs> uv : TEXCOORD1;
};

[ForceInline]
float4 local_to_world(float3 p, float4x4 model) {
    return mul(model, float4(p, 1));
}

__generic<bool hasUVs, TProj : IProjection>
VSOut<hasUVs> vertexImpl(uint vid,
    GraphicsPipelineData<VertexData<hasUVs, TProj>, void, DrawData<hasUVs>> data) {

    let world = local_to_world(data.vert.positions[vid], data.drawData.model);

    VSOut<hasUVs> o;
    o.pos   = data.vert.proj.apply(world.xyz);
    o.color = data.drawData.color;

    if (hasUVs) {
        o.uv = data.vert.uvs.get().value[vid];
    }
    return o;
}

__generic<bool hasUVs>
float4 fragmentImpl(VSOut<hasUVs> input,
    GraphicsPipelineData<void, void, DrawData<hasUVs>> data) : SV_Target {

    if (hasUVs) {
        let tex = getTexture2D(data.drawData.tex_id.get().value);
        let smp = getSampler(data.drawData.sampler_id.get().value);
        return tex.Sample(smp, input.uv.get().value) * input.color;
    }
    return input.color;
}
