use serde::Serialize;

use crate::model::MapData;

#[derive(Debug, Clone, Serialize)]
pub struct Signature {
    pub index: usize,
    pub key: String,
    pub label: String,
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
    pub fn create(n: bool, ne: bool, e: bool, se: bool, s: bool, sw: bool, w: bool, nw: bool) -> Self {
        let open_n = !n;
        let open_e = !e;
        let open_s = !s;
        let open_w = !w;
        let notch_ne = n && e && !ne;
        let notch_se = s && e && !se;
        let notch_sw = s && w && !sw;
        let notch_nw = n && w && !nw;
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
}

pub fn canonical_signatures() -> Vec<Signature> {
    let mut unique = std::collections::BTreeMap::<String, Signature>::new();

    for mask in 0_u16..256 {
        let signature = Signature::create(
            mask & 1 != 0,
            mask & 2 != 0,
            mask & 4 != 0,
            mask & 8 != 0,
            mask & 16 != 0,
            mask & 32 != 0,
            mask & 64 != 0,
            mask & 128 != 0,
        );
        unique.entry(signature.key.clone()).or_insert(signature);
    }

    let mut out: Vec<Signature> = unique.into_values().collect();
    out.sort_by(|left, right| {
        let left_score = edge_count(left) * 10 + notch_count(left);
        let right_score = edge_count(right) * 10 + notch_count(right);
        left_score.cmp(&right_score).then(left.key.cmp(&right.key))
    });
    for (index, signature) in out.iter_mut().enumerate() {
        signature.index = index;
    }
    out
}

pub fn signature_at(map: &MapData, x: i32, y: i32) -> Signature {
    Signature::create(
        cell(map, x, y - 1),
        cell(map, x + 1, y - 1),
        cell(map, x + 1, y),
        cell(map, x + 1, y + 1),
        cell(map, x, y + 1),
        cell(map, x - 1, y + 1),
        cell(map, x - 1, y),
        cell(map, x - 1, y - 1),
    )
}

fn cell(map: &MapData, x: i32, y: i32) -> bool {
    if x < 0 || y < 0 || x >= map.width as i32 || y >= map.height as i32 {
        return false;
    }
    map.cells[(y as u32 * map.width + x as u32) as usize] > 0
}

fn edge_count(signature: &Signature) -> usize {
    usize::from(signature.open_n)
        + usize::from(signature.open_e)
        + usize::from(signature.open_s)
        + usize::from(signature.open_w)
}

fn notch_count(signature: &Signature) -> usize {
    usize::from(signature.notch_ne)
        + usize::from(signature.notch_se)
        + usize::from(signature.notch_sw)
        + usize::from(signature.notch_nw)
}
