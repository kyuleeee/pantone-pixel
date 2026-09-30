// Pantone Pixel CRT 효과: 주사선 + 은은한 번짐 + 가장자리 어둡게
// Windows Terminal의 experimental.pixelShaderPath 로 불러와요.

Texture2D shaderTexture;
SamplerState samplerState;

cbuffer PixelShaderSettings {
    float  Time;
    float  Scale;
    float2 Resolution;
    float4 Background;
};

float4 main(float4 pos : SV_POSITION, float2 tex : TEXCOORD) : SV_TARGET
{
    float4 color = shaderTexture.Sample(samplerState, tex);
    float2 px = 1.0 / Resolution;

    // 번짐: 위아래 양옆 픽셀을 조금씩 더해 글자가 살짝 빛나 보이게
    float4 glow = shaderTexture.Sample(samplerState, tex + float2(px.x, 0))
                + shaderTexture.Sample(samplerState, tex - float2(px.x, 0))
                + shaderTexture.Sample(samplerState, tex + float2(0, px.y))
                + shaderTexture.Sample(samplerState, tex - float2(0, px.y));
    color.rgb += glow.rgb * 0.06;

    // 주사선: 3줄마다 한 줄씩 어둡게
    float scan = fmod(floor(pos.y / max(Scale, 1.0)), 3.0) < 1.0 ? 0.8 : 1.0;
    color.rgb *= scan;

    // 비네트: 화면 가장자리를 살짝 어둡게
    float2 d = tex - 0.5;
    color.rgb *= 1.0 - dot(d, d) * 0.5;

    return color;
}
