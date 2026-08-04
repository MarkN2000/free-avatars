from __future__ import annotations

import argparse
import json
import math
import sys
import traceback
from datetime import datetime
from pathlib import Path

import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    blender_args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--log", type=Path, required=True)
    parser.add_argument("--avatar-name", action="append", default=[])
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--quality", type=int, default=70)
    parser.add_argument("--force", action="store_true")
    return parser.parse_args(blender_args)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for data_blocks in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for data_block in list(data_blocks):
            data_blocks.remove(data_block)


def mesh_bounds() -> tuple[Vector, Vector]:
    depsgraph = bpy.context.evaluated_depsgraph_get()
    minimum = Vector((math.inf, math.inf, math.inf))
    maximum = Vector((-math.inf, -math.inf, -math.inf))
    found_vertex = False

    for source_object in bpy.context.scene.objects:
        if source_object.type != "MESH" or source_object.hide_render:
            continue
        evaluated_object = source_object.evaluated_get(depsgraph)
        mesh = evaluated_object.to_mesh()
        try:
            for vertex in mesh.vertices:
                point = evaluated_object.matrix_world @ vertex.co
                minimum.x = min(minimum.x, point.x)
                minimum.y = min(minimum.y, point.y)
                minimum.z = min(minimum.z, point.z)
                maximum.x = max(maximum.x, point.x)
                maximum.y = max(maximum.y, point.y)
                maximum.z = max(maximum.z, point.z)
                found_vertex = True
        finally:
            evaluated_object.to_mesh_clear()

    if not found_vertex:
        raise RuntimeError("No renderable mesh vertices were found")
    return minimum, maximum


def point_at(obj: bpy.types.Object, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def add_area_light(name: str, location: Vector, target: Vector, energy: float, size: float) -> None:
    light_data = bpy.data.lights.new(name=name, type="AREA")
    light_data.energy = energy
    light_data.shape = "DISK"
    light_data.size = size
    light_object = bpy.data.objects.new(name, light_data)
    bpy.context.scene.collection.objects.link(light_object)
    light_object.location = location
    point_at(light_object, target)


def configure_scene(minimum: Vector, maximum: Vector, output_path: Path, quality: int) -> None:
    scene = bpy.context.scene
    center = (minimum + maximum) * 0.5
    width = maximum.x - minimum.x
    depth = maximum.y - minimum.y
    height = maximum.z - minimum.z
    largest_dimension = max(width, depth, height, 0.1)

    camera_data = bpy.data.cameras.new("ThumbnailCamera")
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = max(height, width, 0.1) * 1.15
    camera_data.lens = 50
    camera_data.clip_start = 0.01
    camera_data.clip_end = largest_dimension * 20
    camera = bpy.data.objects.new("ThumbnailCamera", camera_data)
    scene.collection.objects.link(camera)
    camera.location = Vector((center.x, maximum.y + largest_dimension * 3, center.z))
    point_at(camera, center)
    scene.camera = camera

    add_area_light(
        "Key",
        center + Vector((largest_dimension * 2.5, largest_dimension * 3.0, largest_dimension * 2.5)),
        center,
        850.0,
        largest_dimension * 2.0,
    )
    add_area_light(
        "Fill",
        center + Vector((-largest_dimension * 2.5, largest_dimension * 2.0, largest_dimension * 0.5)),
        center,
        450.0,
        largest_dimension * 2.5,
    )
    add_area_light(
        "Rim",
        center + Vector((largest_dimension * 1.5, -largest_dimension * 2.0, largest_dimension * 2.5)),
        center,
        700.0,
        largest_dimension * 1.5,
    )

    world = scene.world or bpy.data.worlds.new("ThumbnailWorld")
    scene.world = world
    world.use_nodes = True
    background = world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (0.18, 0.20, 0.23, 1.0)
    background.inputs["Strength"].default_value = 0.65

    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 256
    scene.render.resolution_y = 256
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "WEBP"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.quality = quality
    scene.render.filepath = str(output_path)
    scene.render.use_file_extension = True

    scene.view_settings.look = "AgX - Medium High Contrast"


def fit_camera_to_visible_pixels(preview_path: Path) -> None:
    scene = bpy.context.scene
    final_filepath = scene.render.filepath
    final_format = scene.render.image_settings.file_format
    final_color_mode = scene.render.image_settings.color_mode
    preview_image = None
    try:
        scene.render.film_transparent = True
        scene.render.filepath = str(preview_path)
        scene.render.image_settings.file_format = "PNG"
        scene.render.image_settings.color_mode = "RGBA"
        bpy.ops.render.render(write_still=True)

        preview_image = bpy.data.images.load(str(preview_path), check_existing=False)
        width = int(preview_image.size[0])
        height = int(preview_image.size[1])
        pixels = preview_image.pixels[:]
        if width <= 0 or height <= 0 or len(pixels) < width * height * 4:
            raise RuntimeError(
                f"Preview pixel buffer is invalid: {width}x{height}, {len(pixels)} values"
            )
    finally:
        scene.render.filepath = final_filepath
        scene.render.image_settings.file_format = final_format
        scene.render.image_settings.color_mode = final_color_mode
        if preview_image is not None:
            bpy.data.images.remove(preview_image)
        preview_path.unlink(missing_ok=True)
    visible_x: list[int] = []
    visible_y: list[int] = []
    for y in range(height):
        row_offset = y * width * 4
        for x in range(width):
            if pixels[row_offset + x * 4 + 3] > 0.02:
                visible_x.append(x)
                visible_y.append(y)

    if not visible_x:
        raise RuntimeError("No visible pixels were found in the preview render")

    minimum_x = min(visible_x)
    maximum_x = max(visible_x)
    minimum_y = min(visible_y)
    maximum_y = max(visible_y)
    visible_width = maximum_x - minimum_x + 1
    visible_height = maximum_y - minimum_y + 1

    camera = scene.camera
    old_scale = camera.data.ortho_scale
    center_x = (minimum_x + maximum_x) * 0.5
    center_y = (minimum_y + maximum_y) * 0.5
    camera.location.x += ((center_x + 0.5) / width - 0.5) * old_scale
    camera.location.z += ((center_y + 0.5) / height - 0.5) * old_scale

    # Fill at most 88% of either axis, leaving an even margin around every model.
    occupancy = max(visible_width / width, visible_height / height)
    camera.data.ortho_scale = max(old_scale * occupancy / 0.88, 0.01)
    scene.render.film_transparent = False


def render_thumbnail(vrm_path: Path, output_path: Path, quality: int) -> dict[str, object]:
    clear_scene()
    result = bpy.ops.import_scene.gltf(filepath=str(vrm_path))
    if "FINISHED" not in result:
        raise RuntimeError(f"glTF import failed: {result}")

    minimum, maximum = mesh_bounds()
    configure_scene(minimum, maximum, output_path, quality)
    preview_path = output_path.with_name(f".{output_path.stem}.preview.png")
    fit_camera_to_visible_pixels(preview_path)
    bpy.ops.render.render(write_still=True)

    if not output_path.is_file() or output_path.stat().st_size == 0:
        raise RuntimeError("Blender did not create the thumbnail")

    print(f"THUMBNAIL_OUTPUT:{output_path}")
    return {
        "source": str(vrm_path),
        "output": str(output_path),
        "status": "rendered",
        "size": output_path.stat().st_size,
        "bounds": {"min": list(minimum), "max": list(maximum)},
    }


def main() -> int:
    args = parse_args()
    source_root = args.source_root.resolve()
    output_root = args.output_root.resolve()
    log_path = args.log.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)

    vrms = sorted(source_root.rglob("*.vrm"), key=lambda path: str(path).casefold())
    names = [vrm.stem for vrm in vrms]
    duplicates = sorted({name for name in names if names.count(name) > 1})
    if duplicates:
        raise RuntimeError(f"Duplicate VRM base names: {', '.join(duplicates)}")

    if args.avatar_name:
        requested = {name.casefold() for name in args.avatar_name}
        vrms = [vrm for vrm in vrms if vrm.stem.casefold() in requested]
        found = {vrm.stem.casefold() for vrm in vrms}
        missing = [name for name in args.avatar_name if name.casefold() not in found]
        if missing:
            raise RuntimeError(f"Requested avatars were not found: {', '.join(missing)}")
    if args.limit > 0:
        vrms = vrms[: args.limit]

    report: dict[str, object] = {
        "startedAt": datetime.now().isoformat(),
        "quality": args.quality,
        "results": [],
    }
    failures = 0

    for index, vrm_path in enumerate(vrms, start=1):
        output_path = output_root / f"{vrm_path.stem}.webp"
        print(f"[{index}/{len(vrms)}] {vrm_path.name}")
        if output_path.is_file() and output_path.stat().st_size > 0 and not args.force:
            report["results"].append(
                {"source": str(vrm_path), "output": str(output_path), "status": "skipped"}
            )
            continue
        try:
            report["results"].append(render_thumbnail(vrm_path, output_path, args.quality))
        except Exception as exception:
            failures += 1
            traceback.print_exc()
            report["results"].append(
                {
                    "source": str(vrm_path),
                    "output": str(output_path),
                    "status": "failed",
                    "error": str(exception),
                }
            )

    report["finishedAt"] = datetime.now().isoformat()
    report["failures"] = failures
    log_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Thumbnail rendering complete: {len(vrms) - failures} succeeded, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
