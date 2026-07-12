"""Materialize a complete isolated layered asset from calibrated kicker layers."""

from __future__ import annotations

import argparse
import json
import shutil
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base-dir", required=True, type=Path)
    parser.add_argument("--layers-dir", required=True, type=Path)
    parser.add_argument("--proof-manifest", required=True, type=Path)
    parser.add_argument("--out-dir", required=True, type=Path)
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    base_dir = args.base_dir.resolve()
    layers_dir = args.layers_dir.resolve()
    out_dir = args.out_dir.resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    for source in base_dir.iterdir():
        if source.is_file():
            shutil.copy2(source, out_dir / source.name)
    for file_name in ("albedo.png", "trunk.png", "foliage.png"):
        shutil.copy2(layers_dir / file_name, out_dir / file_name)

    proof = json.loads(args.proof_manifest.read_text(encoding="utf-8"))
    eight = next(item for item in proof["variants"] if float(item["target_lift_percent"]) == 8.0)
    meta_path = out_dir / "meta.json"
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    meta["asset"] = "tree_01_clock_10_low_rear_fill_08_proof"
    meta["bake_profile"]["low_rear_kicker"] = {
        "target_dark_trunk_lift_percent": 8.0,
        "measured_dark_trunk_lift_percent": eight["measured_trunk_lift_percent"],
        "measured_dark_foliage_lift_percent": eight["measured_dark_foliage_lift_percent"],
        "spot_energy": eight["spot_energy"],
        "use_shadow": False,
    }
    meta["notes"] = "Isolated candidate C with calibrated 8% low rear kicker; production not promoted."
    meta_path.write_text(json.dumps(meta, indent="\t", ensure_ascii=False), encoding="utf-8")

    profile_path = out_dir / "profile.json"
    profile = json.loads(profile_path.read_text(encoding="utf-8"))
    profile["profile_id"] = "station_mirny_tree_clock_10_low_rear_fill_08_proof"
    profile["version"] = 4
    profile["lighting"]["low_rear_kicker"] = {
        **proof["kicker"],
        "target_lift_percent": 8.0,
        "measured_trunk_lift_percent": eight["measured_trunk_lift_percent"],
        "measured_dark_foliage_lift_percent": eight["measured_dark_foliage_lift_percent"],
        "spot_energy": eight["spot_energy"],
    }
    profile_path.write_text(json.dumps(profile, indent="\t", ensure_ascii=False), encoding="utf-8")

    candidate_manifest = {
        "base_dir": str(base_dir),
        "layers_dir": str(layers_dir),
        "candidate_dir": str(out_dir),
        "target_lift_percent": 8.0,
        "frame_and_anchor_preserved": True,
        "masks_and_shadow_preserved_from_candidate_c": True,
        "production_promoted": False,
    }
    (out_dir / "candidate_manifest.json").write_text(
        json.dumps(candidate_manifest, indent=2, ensure_ascii=False), encoding="utf-8"
    )
    print(json.dumps(candidate_manifest, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
