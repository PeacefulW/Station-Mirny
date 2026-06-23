import json
import math
import sys
from pathlib import Path

import bpy


def argv_after_separator() -> list[str]:
    if "--" not in sys.argv:
        return []
    return sys.argv[sys.argv.index("--") + 1 :]


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for action in list(bpy.data.actions):
        bpy.data.actions.remove(action)


def inspect_clip(path: Path) -> dict:
    clear_scene()
    before = set(bpy.context.scene.objects)
    bpy.ops.import_scene.fbx(filepath=str(path))
    imported = [obj for obj in bpy.context.scene.objects if obj not in before]
    meshes = [obj for obj in imported if obj.type == "MESH"]
    armatures = [obj for obj in imported if obj.type == "ARMATURE"]
    assigned_action = None
    if armatures and armatures[0].animation_data:
        assigned_action = armatures[0].animation_data.action
    actions = []
    for action in bpy.data.actions:
        start, end = action.frame_range
        actions.append(
            {
                "name": action.name,
                "frame_start": int(math.floor(start)),
                "frame_end": int(math.ceil(end)),
                "frames": int(math.ceil(end) - math.floor(start) + 1),
                "assigned_to_armature": action == assigned_action,
            }
        )
    return {
        "path": str(path),
        "mesh_count": len(meshes),
        "armature_count": len(armatures),
        "action_count": len(actions),
        "actions": actions,
        "object_names": [obj.name for obj in imported[:20]],
    }


def main() -> None:
    args = argv_after_separator()
    if len(args) < 2:
        raise SystemExit("Usage: blender --background --python inspect_mixamo_fbx_clips.py -- <output.json> <clip.fbx>...")
    output = Path(args[0])
    clips = [Path(arg) for arg in args[1:]]
    output.parent.mkdir(parents=True, exist_ok=True)
    results = [inspect_clip(path) for path in clips]
    output.write_text(json.dumps(results, indent=2), encoding="utf-8")
    print("MIXAMO_FBX_CLIP_INSPECT_COMPLETE")
    print(json.dumps(results, indent=2))


if __name__ == "__main__":
    main()
