// The time since startup data is in the globals binding which is part of the mesh_view_bindings import
#import bevy_pbr::{
    mesh_view_bindings::globals,
    forward_io::VertexOutput,
}

// OKLab color space conversions for perceptually accurate color blending
fn oklab_to_linear_srgb(c: vec3<f32>) -> vec3<f32> {
    let L = c.x;
    let a = c.y;
    let b = c.z;

    let l_ = L + 0.3963377774 * a + 0.2158037573 * b;
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b;
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b;

    let l = l_ * l_ * l_;
    let m = m_ * m_ * m_;
    let s = s_ * s_ * s_;

    return vec3<f32>(
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s,
    );
}

// 2D Noise function based on Perlin noise principles
fn noise21(p: vec2<f32>) -> f32 {
    let i = floor(p);
    let f = fract(p);
    
    // Cubic Hermite interpolation for smoother blending
    let u = f * f * (3.0 - 2.0 * f);
    
    // Four corners hash values
    let a = fract(sin(dot(i + vec2<f32>(0.0, 0.0), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let b = fract(sin(dot(i + vec2<f32>(1.0, 0.0), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let c = fract(sin(dot(i + vec2<f32>(0.0, 1.0), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    let d = fract(sin(dot(i + vec2<f32>(1.0, 1.0), vec2<f32>(12.9898, 78.233))) * 43758.5453);
    
    // Bilinear interpolation
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Fractional Brownian Motion for layered noise
fn fbm(p: vec2<f32>, octaves: i32) -> f32 {
    var value = 0.0;
    var amplitude = 0.5;
    var frequency = 2.0;
    
    for (var i = 0; i < octaves; i = i + 1) {
        value += amplitude * noise21(p * frequency);
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return value;
}

@fragment
fn fragment(in: VertexOutput) -> @location(0) vec4<f32> {
    // Aurora-specific parameters
    let time = globals.time * 0.2;
    let coord = in.uv;
    
    // Aurora tends to appear in bands across the sky
    let y_stretch = 3.0; // Stretch the effect vertically
    let waviness = 0.8; // How wavy the aurora bands are
    
    // Create multiple layers of noise with different frequencies
    let noise_coord = vec2<f32>(coord.x * 2.0, coord.y * y_stretch) + vec2<f32>(time * 0.1, time * 0.05);
    let large_noise = fbm(noise_coord, 3) * waviness;
    
    // Create wave-like vertical displacement
    let wave_effect = sin(coord.y * 15.0 + time + large_noise * 5.0) * 0.05;
    let displaced_x = coord.x + wave_effect;
    
    // Create flow and movement
    let flow = sin(displaced_x * 10.0 + large_noise * 3.0 + time * 0.7) * 0.5 + 0.5;
    let height_mask = smoothstep(0.0, 0.7, 1.0 - abs(coord.y - 0.5) * 2.0); // Stronger in the middle
    
    // Aurora intensity varies with height and flow
    let intensity = flow * height_mask * smoothstep(0.0, 0.4, large_noise + 0.1);
    
    // Distance from center affects color mixing
    let dist_center = distance(coord, vec2<f32>(0.5, 0.5));
    let dist_factor = smoothstep(0.0, 1.2, dist_center);
    
    // Layer of smaller, faster moving details
    let small_noise = fbm(noise_coord * 4.0 + vec2<f32>(time * 0.2, 0.0), 2) * 0.4;
    let detail_intensity = small_noise * intensity * 0.8;
    
    // Time-varying parameters for color animation
    let t1 = sin(time * 0.3) * 0.5 + 0.5;
    let t2 = cos(time * 0.2) * 0.5 + 0.5;
    let t3 = sin(time * 0.4 + dist_center) * 0.5 + 0.5;
    
    // Aurora borealis colors in OKLab space for better blending
    // Vibrant greens and teals are common in auroras
    let green = vec3<f32>(0.86644, -0.233887, 0.179498);  // Vibrant green
    let teal = vec3<f32>(0.7, -0.1, 0.1);                 // Bluish-green
    let blue = vec3<f32>(0.701674, 0.174566, -0.269156);  // Cold blue
    let purple = vec3<f32>(0.7, 0.3, -0.1);               // Purplish hue
    
    // Final color is a complex mix based on multiple parameters
    let color1 = mix(green, teal, t1);
    let color2 = mix(blue, purple, t2);
    let mixed_color = mix(color1, color2, t3 * dist_factor + detail_intensity);
    
    // Apply intensity to color and convert back to linear RGB
    let final_color = mixed_color * (intensity + detail_intensity * 0.7);
    let rgb_color = oklab_to_linear_srgb(final_color);
    
    // Add a subtle glow effect
    let glow = intensity * 0.4;
    let glow_color = mix(vec3<f32>(0.05, 0.1, 0.2), rgb_color, intensity);
    
    return vec4<f32>(rgb_color + glow_color * glow, intensity * 0.9 + 0.1);
}