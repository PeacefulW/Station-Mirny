pub fn clamp(value: f32, min: f32, max: f32) -> f32 {
    value.max(min).min(max)
}

pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

fn smoothstep(t: f32) -> f32 {
    t * t * (3.0 - 2.0 * t)
}

pub fn hash2d(x: i32, y: i32, seed: u32) -> f32 {
    let mut n = (x as u32)
        .wrapping_mul(374_761_393)
        .wrapping_add((y as u32).wrapping_mul(668_265_263))
        .wrapping_add(seed.wrapping_mul(1_442_695_041));
    n ^= n >> 13;
    n = n.wrapping_mul(1_274_126_177);
    (n ^ (n >> 16)) as f32 / u32::MAX as f32
}

pub fn value_noise(x: f32, y: f32, seed: u32) -> f32 {
    let x0 = x.floor() as i32;
    let y0 = y.floor() as i32;
    let tx = x - x0 as f32;
    let ty = y - y0 as f32;
    let sx = smoothstep(tx);
    let sy = smoothstep(ty);

    let v00 = hash2d(x0, y0, seed);
    let v10 = hash2d(x0 + 1, y0, seed);
    let v01 = hash2d(x0, y0 + 1, seed);
    let v11 = hash2d(x0 + 1, y0 + 1, seed);

    let top = lerp(v00, v10, sx);
    let bottom = lerp(v01, v11, sx);
    lerp(top, bottom, sy)
}

pub fn fbm(x: f32, y: f32, octaves: u32, seed: u32) -> f32 {
    let mut amplitude = 1.0_f32;
    let mut frequency = 1.0_f32;
    let mut total = 0.0_f32;
    let mut weight = 0.0_f32;

    for octave in 0..octaves {
        total += value_noise(x * frequency, y * frequency, seed.wrapping_add(octave * 97)) * amplitude;
        weight += amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }

    if weight <= f32::EPSILON {
        0.0
    } else {
        total / weight
    }
}
