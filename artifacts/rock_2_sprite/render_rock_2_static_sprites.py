import importlib.util
import math
import sys
from pathlib import Path

import bpy


ROCK_1_SCRIPT = Path(__file__).resolve().parents[1] / "rock_1_sprite" / "render_rock_static_sprites.py"


def load_base_module():
    spec = importlib.util.spec_from_file_location("rock_static_base", ROCK_1_SCRIPT)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load base render script: {ROCK_1_SCRIPT}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def render_rock_2_rotations(turntable_root, output_dir: Path, rotations: int) -> None:
    scene = bpy.context.scene
    output_dir.mkdir(parents=True, exist_ok=True)
    for index in range(rotations):
        degrees = round(360.0 * index / rotations)
        turntable_root.rotation_euler.z = math.tau * index / rotations
        bpy.context.view_layer.update()
        scene.render.filepath = str(output_dir / f"rock_2_rot_{index:02d}_{degrees:03d}deg.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    module = load_base_module()
    module.render_rotations = render_rock_2_rotations
    module.main()


if __name__ == "__main__":
    main()
