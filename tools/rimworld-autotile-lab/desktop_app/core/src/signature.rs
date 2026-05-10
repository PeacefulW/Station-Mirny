use serde::Serialize;

#[cfg(test)]
use crate::model::MapData;

#[derive(Debug, Clone, Serialize)]
pub struct Signature {
    pub index: usize,
    pub key: String,
    pub label: String,
    pub marching_mask: u8,
    pub corner_nw: bool,
    pub corner_ne: bool,
    pub corner_se: bool,
    pub corner_sw: bool,
    pub open_n: bool,
    pub open_e: bool,
    pub open_s: bool,
    pub open_w: bool,
    pub notch_ne: bool,
    pub notch_se: bool,
    pub notch_sw: bool,
    pub notch_nw: bool,
}

impl Signature {
    #[cfg(test)]
    pub fn create(
        n: bool,
        ne: bool,
        e: bool,
        se: bool,
        s: bool,
        sw: bool,
        w: bool,
        nw: bool,
    ) -> Self {
        let open_n = !n;
        let open_e = !e;
        let open_s = !s;
        let open_w = !w;
        let notch_ne = n && e && !ne;
        let notch_se = s && e && !se;
        let notch_sw = s && w && !sw;
        let notch_nw = n && w && !nw;
        let corner_nw = n || w || nw;
        let corner_ne = n || e || ne;
        let corner_se = s || e || se;
        let corner_sw = s || w || sw;
        let marching_mask = marching_mask(corner_nw, corner_ne, corner_se, corner_sw);
        let key = format!(
            "{}{}{}{}|{}{}{}{}",
            u8::from(open_n),
            u8::from(open_e),
            u8::from(open_s),
            u8::from(open_w),
            u8::from(notch_ne),
            u8::from(notch_se),
            u8::from(notch_sw),
            u8::from(notch_nw)
        );

        let mut edges = Vec::new();
        if open_n {
            edges.push("N");
        }
        if open_e {
            edges.push("E");
        }
        if open_s {
            edges.push("S");
        }
        if open_w {
            edges.push("W");
        }

        let mut notches = Vec::new();
        if notch_ne {
            notches.push("NE");
        }
        if notch_se {
            notches.push("SE");
        }
        if notch_sw {
            notches.push("SW");
        }
        if notch_nw {
            notches.push("NW");
        }

        let label = if edges.is_empty() {
            if notches.is_empty() {
                "solid".to_string()
            } else {
                format!("solid, notch {}", notches.join("/"))
            }
        } else if notches.is_empty() {
            format!("open {}", edges.join("/"))
        } else {
            format!("open {}, notch {}", edges.join("/"), notches.join("/"))
        };

        Self {
            index: 0,
            key,
            label,
            marching_mask,
            corner_nw,
            corner_ne,
            corner_se,
            corner_sw,
            open_n,
            open_e,
            open_s,
            open_w,
            notch_ne,
            notch_se,
            notch_sw,
            notch_nw,
        }
    }

    pub fn from_marching_mask(mask: u8) -> Self {
        let mask = mask & 0x0f;
        let corner_nw = mask & 0b0001 != 0;
        let corner_ne = mask & 0b0010 != 0;
        let corner_se = mask & 0b0100 != 0;
        let corner_sw = mask & 0b1000 != 0;
        let key = format!("ms_{mask:x}");
        let label = if mask == 0 {
            "ms empty".to_string()
        } else if mask == 0x0f {
            "ms solid".to_string()
        } else {
            format!("ms {mask:x}")
        };

        Self {
            index: 0,
            key,
            label,
            marching_mask: mask,
            corner_nw,
            corner_ne,
            corner_se,
            corner_sw,
            open_n: !(corner_nw && corner_ne),
            open_e: !(corner_ne && corner_se),
            open_s: !(corner_sw && corner_se),
            open_w: !(corner_nw && corner_sw),
            notch_ne: false,
            notch_se: false,
            notch_sw: false,
            notch_nw: false,
        }
    }
}

pub fn canonical_signatures() -> Vec<Signature> {
    let mut out: Vec<Signature> = (0_u8..16).map(Signature::from_marching_mask).collect();
    for (index, signature) in out.iter_mut().enumerate() {
        signature.index = index;
    }
    out
}

#[cfg(test)]
pub fn signature_at(map: &MapData, x: i32, y: i32) -> Signature {
    Signature::from_marching_mask(marching_mask(
        cell(map, x, y),
        cell(map, x + 1, y),
        cell(map, x + 1, y + 1),
        cell(map, x, y + 1),
    ))
}

#[cfg(test)]
fn cell(map: &MapData, x: i32, y: i32) -> bool {
    if x < 0 || y < 0 || x >= map.width as i32 || y >= map.height as i32 {
        return false;
    }
    map.cells[(y as u32 * map.width + x as u32) as usize] > 0
}

#[cfg(test)]
fn marching_mask(nw: bool, ne: bool, se: bool, sw: bool) -> u8 {
    u8::from(nw) | (u8::from(ne) << 1) | (u8::from(se) << 2) | (u8::from(sw) << 3)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_signatures_are_true_marching_square_cases() {
        let signatures = canonical_signatures();

        assert_eq!(signatures.len(), 16);
        assert_eq!(signatures[0].key, "ms_0");
        assert_eq!(signatures[15].key, "ms_f");
    }

    #[test]
    fn signature_at_reads_four_corner_samples() {
        let map = MapData {
            width: 2,
            height: 2,
            cells: vec![1, 0, 0, 1],
        };

        let signature = signature_at(&map, 0, 0);

        assert_eq!(signature.key, "ms_5");
    }
}
