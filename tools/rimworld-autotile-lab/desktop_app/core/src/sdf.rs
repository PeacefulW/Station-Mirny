use crate::model::MapData;

const INF_DISTANCE_SQ: f32 = 1.0e20;

#[derive(Debug, Clone)]
pub struct MapSdf {
    pub width: u32,
    pub height: u32,
    pub values: Vec<f32>,
    outside_padding: u32,
    outside_width: u32,
    outside_height: u32,
    outside_values: Vec<f32>,
}

impl MapSdf {
    pub fn compute(map: &MapData) -> Self {
        let width = map.width;
        let height = map.height;
        let expected = (width * height) as usize;
        if width == 0 || height == 0 || map.cells.len() != expected {
            return Self {
                width,
                height,
                values: Vec::new(),
                outside_padding: 0,
                outside_width: 0,
                outside_height: 0,
                outside_values: Vec::new(),
            };
        }

        let mut values = vec![0.0_f32; expected];
        let has_inside = map.cells.iter().any(|cell| *cell > 0);
        if !has_inside {
            let fallback = -(width.max(height).max(1) as f32);
            values.fill(fallback);
            return Self {
                width,
                height,
                values,
                outside_padding: 0,
                outside_width: 0,
                outside_height: 0,
                outside_values: Vec::new(),
            };
        }

        let inside_distance_sq = squared_distance_to_features(width, height, |x, y| {
            cell_inside(map, x as i32, y as i32)
        });
        let padded_width = width + 2;
        let padded_height = height + 2;
        let outside_distance_sq =
            squared_distance_to_features(padded_width, padded_height, |x, y| {
                if x == 0 || y == 0 || x + 1 == padded_width || y + 1 == padded_height {
                    return true;
                }
                !cell_inside(map, x as i32 - 1, y as i32 - 1)
            });

        for y in 0..height {
            for x in 0..width {
                let inside = cell_inside(map, x as i32, y as i32);
                let best_sq = if inside {
                    let padded_index = ((y + 1) * padded_width + x + 1) as usize;
                    outside_distance_sq[padded_index]
                } else {
                    inside_distance_sq[(y * width + x) as usize]
                };
                let distance = (best_sq.sqrt() - 0.5).max(0.0);
                values[(y * width + x) as usize] = if inside { distance } else { -distance };
            }
        }

        let outside_padding = 8;
        let outside_width = width + outside_padding * 2;
        let outside_height = height + outside_padding * 2;
        let outside_distance_sq =
            squared_distance_to_features(outside_width, outside_height, |x, y| {
                cell_inside(
                    map,
                    x as i32 - outside_padding as i32,
                    y as i32 - outside_padding as i32,
                )
            });
        let mut outside_values = vec![0.0_f32; (outside_width * outside_height) as usize];
        for y in 0..outside_height {
            for x in 0..outside_width {
                let map_x = x as i32 - outside_padding as i32;
                let map_y = y as i32 - outside_padding as i32;
                let value =
                    if map_x >= 0 && map_y >= 0 && map_x < width as i32 && map_y < height as i32 {
                        values[(map_y as u32 * width + map_x as u32) as usize]
                    } else {
                        let best_sq = outside_distance_sq[(y * outside_width + x) as usize];
                        if best_sq < INF_DISTANCE_SQ * 0.5 {
                            -(best_sq.sqrt() - 0.5).max(0.0)
                        } else {
                            -(width.max(height).max(1) as f32)
                        }
                    };
                outside_values[(y * outside_width + x) as usize] = value;
            }
        }

        Self {
            width,
            height,
            values,
            outside_padding,
            outside_width,
            outside_height,
            outside_values,
        }
    }

    pub fn sample(&self, cell_x: f32, cell_y: f32) -> f32 {
        if self.width == 0 || self.height == 0 || self.values.is_empty() {
            return 0.0;
        }

        let x0 = cell_x.floor() as i32;
        let y0 = cell_y.floor() as i32;
        let tx = cell_x - x0 as f32;
        let ty = cell_y - y0 as f32;

        let nw = self.value_at(x0, y0);
        let ne = self.value_at(x0 + 1, y0);
        let sw = self.value_at(x0, y0 + 1);
        let se = self.value_at(x0 + 1, y0 + 1);
        let north = lerp(nw, ne, tx);
        let south = lerp(sw, se, tx);
        lerp(north, south, ty)
    }

    pub fn gradient(&self, cell_x: f32, cell_y: f32) -> (f32, f32) {
        let step = 0.5_f32;
        let dx = (self.sample(cell_x + step, cell_y) - self.sample(cell_x - step, cell_y))
            / (step * 2.0);
        let dy = (self.sample(cell_x, cell_y + step) - self.sample(cell_x, cell_y - step))
            / (step * 2.0);
        (dx, dy)
    }

    fn value_at(&self, x: i32, y: i32) -> f32 {
        if x >= 0 && y >= 0 && x < self.width as i32 && y < self.height as i32 {
            return self.values[(y as u32 * self.width + x as u32) as usize];
        }
        self.outside_value_at(x, y)
    }

    fn outside_value_at(&self, x: i32, y: i32) -> f32 {
        if self.outside_padding > 0 {
            let px = x + self.outside_padding as i32;
            let py = y + self.outside_padding as i32;
            if px >= 0
                && py >= 0
                && px < self.outside_width as i32
                && py < self.outside_height as i32
            {
                return self.outside_values[(py as u32 * self.outside_width + px as u32) as usize];
            }
        }

        let max_x = self.width as i32 - 1;
        let max_y = self.height as i32 - 1;
        let clamped_x = x.clamp(0, max_x);
        let clamped_y = y.clamp(0, max_y);
        let edge_value = self.values[(clamped_y as u32 * self.width + clamped_x as u32) as usize];
        let dx = if x < 0 {
            -x
        } else if x > max_x {
            x - max_x
        } else {
            0
        };
        let dy = if y < 0 {
            -y
        } else if y > max_y {
            y - max_y
        } else {
            0
        };
        edge_value - ((dx * dx + dy * dy) as f32).sqrt()
    }
}

fn cell_inside(map: &MapData, x: i32, y: i32) -> bool {
    if x < 0 || y < 0 || x >= map.width as i32 || y >= map.height as i32 {
        return false;
    }
    map.cells[(y as u32 * map.width + x as u32) as usize] > 0
}

fn squared_distance_to_features<F>(width: u32, height: u32, mut is_feature: F) -> Vec<f32>
where
    F: FnMut(u32, u32) -> bool,
{
    let width = width as usize;
    let height = height as usize;
    let mut grid = vec![INF_DISTANCE_SQ; width * height];
    for y in 0..height {
        for x in 0..width {
            if is_feature(x as u32, y as u32) {
                grid[y * width + x] = 0.0;
            }
        }
    }

    let mut row_pass = vec![INF_DISTANCE_SQ; width * height];
    let max_axis = width.max(height).max(1);
    let mut line = vec![INF_DISTANCE_SQ; max_axis];
    let mut transformed = vec![INF_DISTANCE_SQ; max_axis];

    for y in 0..height {
        let start = y * width;
        line[..width].copy_from_slice(&grid[start..start + width]);
        distance_transform_1d(&line[..width], &mut transformed[..width]);
        row_pass[start..start + width].copy_from_slice(&transformed[..width]);
    }

    let mut out = vec![INF_DISTANCE_SQ; width * height];
    for x in 0..width {
        for y in 0..height {
            line[y] = row_pass[y * width + x];
        }
        distance_transform_1d(&line[..height], &mut transformed[..height]);
        for y in 0..height {
            out[y * width + x] = transformed[y];
        }
    }

    out
}

fn distance_transform_1d(features: &[f32], distances: &mut [f32]) {
    let Some(first_feature) = features
        .iter()
        .position(|value| *value < INF_DISTANCE_SQ * 0.5)
    else {
        distances.fill(INF_DISTANCE_SQ);
        return;
    };

    let n = features.len();
    let mut parabola_locations = vec![0_usize; n];
    let mut boundaries = vec![0.0_f32; n + 1];
    let mut active = 0_usize;
    parabola_locations[0] = first_feature;
    boundaries[0] = f32::NEG_INFINITY;
    boundaries[1] = f32::INFINITY;

    for candidate in (first_feature + 1)..n {
        if features[candidate] >= INF_DISTANCE_SQ * 0.5 {
            continue;
        }
        let mut intersection =
            parabola_intersection(features, candidate, parabola_locations[active]);
        while intersection <= boundaries[active] {
            if active == 0 {
                break;
            }
            active -= 1;
            intersection = parabola_intersection(features, candidate, parabola_locations[active]);
        }
        if intersection <= boundaries[active] {
            active = 0;
        } else {
            active += 1;
        }
        parabola_locations[active] = candidate;
        boundaries[active] = intersection;
        boundaries[active + 1] = f32::INFINITY;
    }

    active = 0;
    for (query, distance) in distances.iter_mut().enumerate() {
        while boundaries[active + 1] < query as f32 {
            active += 1;
        }
        let feature = parabola_locations[active];
        let offset = query as f32 - feature as f32;
        *distance = offset * offset + features[feature];
    }
}

fn parabola_intersection(features: &[f32], candidate: usize, active: usize) -> f32 {
    let candidate_f = candidate as f32;
    let active_f = active as f32;
    let numerator =
        features[candidate] + candidate_f * candidate_f - features[active] - active_f * active_f;
    numerator / (2.0 * candidate_f - 2.0 * active_f)
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[cfg(test)]
mod tests {
    use super::*;

    use crate::model::MapData;

    #[test]
    fn signed_distance_is_positive_inside_and_negative_outside() {
        let map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };

        let sdf = MapSdf::compute(&map);

        assert!(sdf.values[(sdf.width + 1) as usize] > 0.0);
        assert!(sdf.values[0] < 0.0);
    }

    #[test]
    fn bilinear_sample_crosses_zero_between_inside_and_outside_cells() {
        let map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };

        let sdf = MapSdf::compute(&map);

        assert!(sdf.sample(1.0, 1.0) > 0.0);
        assert!(sdf.sample(2.0, 1.0) < 0.0);
        assert!(
            sdf.sample(1.5, 1.0).abs() < 0.0001,
            "midpoint between opposite cells should be the smooth contour"
        );
    }

    #[test]
    fn adjacent_opposite_cells_measure_half_cell_to_the_contour() {
        let map = MapData {
            width: 1,
            height: 2,
            cells: vec![1, 0],
        };

        let sdf = MapSdf::compute(&map);

        assert!((sdf.values[0] - 0.5).abs() < 0.0001);
        assert!((sdf.values[1] + 0.5).abs() < 0.0001);
        assert!(sdf.sample(0.0, 0.5).abs() < 0.0001);
    }

    #[test]
    fn gradient_points_toward_increasing_inside_distance() {
        let map = MapData {
            width: 3,
            height: 3,
            cells: vec![0, 0, 0, 0, 1, 0, 0, 0, 0],
        };

        let sdf = MapSdf::compute(&map);
        let (gx, gy) = sdf.gradient(1.5, 1.0);

        assert!(
            gx < -0.5,
            "right edge gradient should point back into the blob"
        );
        assert!(
            gy.abs() < 0.01,
            "horizontal edge should not invent vertical normal"
        );
    }

    #[test]
    fn compute_scales_to_large_preview_maps() {
        let width = 128;
        let height = 128;
        let mut cells = vec![0_u8; (width * height) as usize];
        for y in 8..120 {
            for x in 8..120 {
                if (x + y) % 9 != 0 {
                    cells[(y * width + x) as usize] = 1;
                }
            }
        }
        let map = MapData {
            width,
            height,
            cells,
        };

        let started = std::time::Instant::now();
        let sdf = MapSdf::compute(&map);
        let elapsed_ms = started.elapsed().as_millis();

        assert_eq!(sdf.values.len(), (width * height) as usize);
        assert!(
            elapsed_ms < 500,
            "SDF preview map compute took {elapsed_ms}ms; expected a near-linear pass"
        );
    }
}
