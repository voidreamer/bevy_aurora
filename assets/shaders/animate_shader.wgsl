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

// Minimal, realistic star field with depth simulation and very subtle twinkling
fn stars(coord: vec2<f32>, time: f32) -> vec3<f32> {
    var star_color = vec3<f32>(0.0);
    
    // Ultra slow time progression for twinkling - barely noticeable
    // For ~20 second cycle: sin(t) completes a cycle in 2π seconds
    // So we need t to increase by 2π in 20 seconds
    // At 60fps, 20 seconds = 1200 frames, so t should increase by 2π/1200 ≈ 0.005 per frame
    // time * 0.0005 gives about 20-30 seconds per twinkle
    let ultra_slow_time = time * 0.0005; 
    
    // Just one primary star layer with very few stars
    let seed = 42.1;
    let scale = 18.0; // Lower scale = fewer stars
    
    // Almost completely stationary stars, virtually no movement
    let offset = vec2<f32>(seed, seed * 2.0) + ultra_slow_time * 0.001;
    
    // Base star field noise
    let n = fract(sin(dot(coord * scale + offset, vec2<f32>(12.9898, 78.233))) * 43758.5453);
    
    // Much higher threshold for far fewer stars (0.992 = approx only 0.8% of pixels)
    let base_threshold = 0.992; 
    
    // Subtle depth variation noise - used to vary star brightness
    let depth_noise = fract(sin(dot(floor(coord * 7.0), vec2<f32>(45.89, 98.233))) * 43758.5453);
    
    // Stars only appear if noise exceeds threshold
    if (n > base_threshold) {
        // Almost imperceptible twinkling with extremely slow cycle
        let individual_twinkle_rate = fract(n * 23.7) * 0.1 + 0.02; // 0.02-0.12 range (much slower)
        let twinkle = 0.97 + 0.03 * sin(ultra_slow_time * individual_twinkle_rate); // Only 3% variation
        
        // Basic brightness is determined by how far above threshold
        let base_brightness = (n - base_threshold) / (1.0 - base_threshold);
        
        // Depth simulation - make stars appear at different distances via brightness
        let depth_factor = 0.2 + depth_noise * 0.8; // Range from 0.2-1.0
        let brightness = base_brightness * twinkle * depth_factor * 0.5; // Reduce overall brightness
        
        // Color temperature based on apparent magnitude and spectral class
        // Dimmer stars tend to appear more red/orange, brighter ones more white/blue
        let temp_factor = depth_factor * 0.8 + base_brightness * 0.2;
        
        // Subtle color variation based on spectral class
        let spectral_seed = fract(n * 7.3);
        
        var star_color_temp = vec3<f32>(1.0);
        
        // Simplify to just 3 color categories for subtlety
        if (spectral_seed < 0.6) { // Most stars - main sequence G/K/M
            // Yellow to slightly reddish - subtle
            star_color_temp = mix(
                vec3<f32>(1.0, 0.85, 0.7), // Orange-ish K-type
                vec3<f32>(1.0, 0.95, 0.8), // Yellow-ish G-type (sun-like)
                temp_factor
            );
        } else if (spectral_seed < 0.9) { // Less common - F/A types
            // White to slightly yellow-white
            star_color_temp = mix(
                vec3<f32>(1.0, 0.95, 0.8), // Yellowish
                vec3<f32>(0.95, 0.95, 1.0), // White
                temp_factor
            );
        } else { // Rare - O/B types
            // Blue-white
            star_color_temp = mix(
                vec3<f32>(0.9, 0.95, 1.0), // Slightly blue-white
                vec3<f32>(0.85, 0.9, 1.0), // More blue
                temp_factor
            );
        }
        
        // Dim all colors slightly to avoid pure white
        star_color += star_color_temp * brightness * 0.7;
    }
    
    // A handful of brighter foreground stars
    let bright_seed = fract(sin(dot(floor(coord * 3.5), vec2<f32>(67.236, 27.719))) * 43758.5453);
    
    // Extremely low probability for brighter stars
    if (bright_seed > 0.9985) { // Only about 5-7 stars in the whole field
        // Very subtle twinkling for bright stars
        let bright_twinkle_rate = fract(bright_seed * 5.0) * 0.05 + 0.01; // 0.01-0.06 range (extremely slow)
        let bright_twinkle = 0.98 + 0.02 * sin(ultra_slow_time * bright_twinkle_rate); // Only 2% variation
        
        // Position the star within its grid cell (3.5 grids across the screen)
        let star_center = floor(coord * 3.5) / 3.5 + vec2<f32>(0.143, 0.143);
        let dist = distance(coord, star_center);
        
        // Subtle glow
        let glow_size = 0.01 + fract(bright_seed * 19.7) * 0.008; // Varied tiny glows
        let brightness = smoothstep(glow_size, 0.0, dist) * bright_twinkle * 0.7;
        
        // Foreground stars: primarily white to yellow-white
        let temp = fract(bright_seed * 7.1);
        let bright_color = mix(
            vec3<f32>(1.0, 0.95, 0.8), // Slightly yellow (G type)
            vec3<f32>(0.95, 0.95, 1.0),  // White (A type)
            temp
        ) * 0.9; // Reduce brightness to avoid true white
        
        star_color += bright_color * brightness;
    }
    
    return star_color;
}

// Nebula effect for subtle space dust
fn nebula(coord: vec2<f32>, time: f32) -> vec3<f32> {
    // Very subtle shifting noise field
    let nebula_noise = fbm(coord * 4.0 + vec2<f32>(time * 0.01, 0.0), 3) * 0.15;
    
    // Vary nebula color based on position
    let hue = fbm(coord * 2.0 - vec2<f32>(time * 0.02, 0.0), 2);
    
    // Very subtle bluish/purplish dust
    let nebula_color = mix(
        vec3<f32>(0.02, 0.035, 0.05),  // Deep blue
        vec3<f32>(0.04, 0.02, 0.06),   // Purple tint
        hue
    );
    
    return nebula_color * nebula_noise * smoothstep(0.4, 0.6, noise21(coord * 3.0 + vec2<f32>(time * 0.03, 0.0)));
}

// Shooting star effect
fn shooting_star(coord: vec2<f32>, time: f32) -> vec3<f32> {
    // Only show shooting star occasionally
    let show_time = sin(time * 0.05) > 0.95;
    
    if (!show_time) {
        return vec3<f32>(0.0);
    }
    
    // Shooting star parameters
    let star_speed = 0.3;
    let length = 0.1;
    let width = 0.002;
    
    // Moving position for the shooting star
    let shooting_time = fract(time * 0.1);
    let pos = vec2<f32>(
        1.0 - shooting_time * 1.5, // X movement (right to left)
        0.8 - shooting_time * 0.7  // Y movement (slight downward trajectory)
    );
    
    // Trail calculation
    let trail_dir = normalize(vec2<f32>(-star_speed, -star_speed * 0.5));
    let coord_proj = dot(coord - pos, trail_dir);
    let coord_orth = length(coord - pos - coord_proj * trail_dir);
    
    // Trail visibility
    let in_trail = coord_proj > -length && coord_proj < 0.0 && coord_orth < width;
    let trail_intensity = smoothstep(0.0, -length, coord_proj) * smoothstep(width, 0.0, coord_orth);
    
    // Fade trail based on time
    let fade = smoothstep(0.0, 0.3, shooting_time) * smoothstep(1.0, 0.7, shooting_time);
    
    return vec3<f32>(1.0, 0.95, 0.9) * trail_intensity * fade * 2.0 * f32(in_trail);
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
    let aurora_lab_color = mixed_color * (intensity + detail_intensity * 0.7);
    let rgb_color = oklab_to_linear_srgb(aurora_lab_color);
    
    // Add a subtle glow effect
    let glow = intensity * 0.4;
    let glow_color = mix(vec3<f32>(0.05, 0.1, 0.2), rgb_color, intensity);
    let aurora_color = rgb_color + glow_color * glow;
    
    // Generate stars and celestial elements
    let star_color = stars(coord, time);
    let nebula_color = nebula(coord, time);
    let shooting_star_color = shooting_star(coord, time);
    
    // Add small comet dust particles
    let dust_noise = noise21(coord * 30.0 + time * 0.05) * noise21(coord * 25.0 - time * 0.02);
    let dust_particles = smoothstep(0.985, 1.0, dust_noise) * 0.2;
    let dust_color = vec3<f32>(0.8, 0.9, 1.0) * dust_particles;
    
    // Create a subtle vignette effect
    let vignette = smoothstep(1.2, 0.5, length(coord - vec2<f32>(0.5)));
    
    // Background gradient for night sky
    let bg_gradient = mix(
        vec3<f32>(0.0, 0.01, 0.03),  // Bottom - darker
        vec3<f32>(0.01, 0.03, 0.07), // Top - slightly lighter
        coord.y * 0.7
    ) * vignette;
    
    // Create the night sky background first
    let sky_color = bg_gradient + nebula_color;
    
    // Generate star field
    let stars_with_dust = star_color + dust_color + shooting_star_color;
    
    // Create composite sky with stars (sky + stars first, before aurora overlay)
    let star_sky = sky_color + stars_with_dust;
    
    // Aurora overlay - use a lower blend factor to keep stars visible
    let aurora_blend_factor = clamp(intensity * 0.7, 0.0, 0.8); // Cap at 0.8 to always let stars show
    
    // Blend aurora over the starry sky
    let with_aurora = mix(star_sky, aurora_color, aurora_blend_factor);
    
    // Add some star brightness on top to ensure key stars are visible through aurora
    // But much more subtle than before
    let brightest_stars = star_color * 0.3;
    
    // Final color with stars showing through aurora
    let final_color = with_aurora + brightest_stars;
    
    return vec4<f32>(final_color, intensity * 0.9 + 0.1);
}