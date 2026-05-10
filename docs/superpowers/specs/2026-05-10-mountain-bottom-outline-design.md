# Mountain Bottom Outline Design

## Purpose

Add an optional black contact outline along the bottom contour of generated mountains. The outline is meant to separate the cliff face from the ground, matching the supplied RimWorld-style reference where the lower mountain edge remains readable against similarly colored terrain.

## Scope

The outline applies only to the lower boundary where the mountain face meets empty/base terrain. It must not draw a full silhouette around the mountain, tint the top lip, or replace the existing rim and edge-debris controls.

## Settings

- `mountain_outline_enabled`: enables or disables the contact outline.
- `mountain_outline_width`: controls the line width in pixels.

The mountain preset enables the outline by default with a narrow width. Saved recipes include the settings, and older recipes fall back to defaults through request sanitization.

## Rendering

Render the outline as a post-process over the albedo tile buffers. A face pixel is part of the outline when base/empty terrain is directly below it within the configured width. This keeps the effect bottom-only, including lower edges inside notches, without affecting top or side boundaries.

The line uses near-black color and fades across the configured width to avoid a jagged hard band at supersampled contours.

## Testing

Core tests cover three behaviors:

- disabled outline does not change albedo;
- enabled outline darkens the lower face-to-ground contact;
- enabled outline does not darken the top lip.

Shell tests cover preset defaults and request payload fields.
