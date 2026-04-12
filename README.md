# TAVI Planning Plugin for Horos

This project builds a native `arm64` Horos plugin that provides a manual or semi-automated TAVI planning workflow inside Horos. It is designed for `Horos 4.0.1` on Apple Silicon and intentionally avoids nibs and `xcodebuild`, so it can be built with the Command Line Tools alone.

## What It Does

- opens a dedicated `TAVI Planning` window from the Horos plugin menu
- captures native Horos ROIs for:
  - annulus contour
  - LVOT contour
  - left coronary ostium point
  - right coronary ostium point
  - membranous septum point pair
  - sinus of Valsalva contour
  - sinotubular junction contour
  - ascending aorta contour
- computes:
  - perimeter, area, equivalent diameter, minimum diameter, maximum diameter
  - assisted annulus ellipse fit derived from the captured annulus contour
  - left and right coronary heights relative to the annulus plane
  - LVOT and membranous septum measurements
  - horizontal aorta angle relative to the axial reference plane
  - advisory LAO/RAO and cranial/caudal fluoroscopic angle guidance
  - optional 3-point sinus confirmation for projection-angle review
  - threshold-based calcium assist metrics using the captured ROI slice, including a 2D Agatston-like score
- renders a lightweight projection preview that overlays the captured annulus, assisted annulus fit, LVOT, membranous septum, ostial markers, and a virtual valve ring
- generates structured text and CSV exports

## Build

Run:

```sh
./scripts/build.sh
```

The plugin bundle is written to:

```text
build/TAVIMeasurementPlugin.osirixplugin
```

## Test

Run:

```sh
./scripts/test.sh
```

This compiles and runs geometry and calcium unit-style checks in `tests/TAVIGeometryTests.m`.

## Install

Install the built bundle by copying it into your Horos plugins location, for example:

```text
~/Library/Application Support/Horos/Plugins/
```

Then relaunch Horos or use the plugin manager to refresh plugins.

## Workflow

1. Open a volumic series or the MPR plane you want to measure.
2. Draw or select a ROI directly in Horos.
3. In the plugin window, follow the guided order:
   - ascending aorta
   - STJ
   - sinus of Valsalva
   - optional LVOT
   - annulus
   - optional 3 sinus points for projection confirmation
   - optional membranous septum point pair
   - left ostium
   - right ostium
4. Use `Use Assisted Annulus` if you want the fitted annulus ellipse to drive coronary-height and preview planning instead of the raw contour.
5. Adjust the `Virtual Valve (mm)` field if you want to preview a chosen prosthesis diameter instead of the annulus-derived suggestion.
6. Adjust the calcium threshold and manual calcification grades if needed.
7. Review the projection preview, structured report, and export CSV or text.

## Borrowed From The OsiriX TAVIReport Manual

The current UI now explicitly borrows the old TAVIReport plugin's step-by-step acquisition sequence from the OsiriX manual:

- ascending aorta first
- sino-tubular junction second
- sinus of Valsalva before annulus
- annulus before coronary heights
- projection-angle review after annulus capture

Current v1 differences from that manual:

- the old manual used Length ROI measurements for several diameter steps; this plugin currently standardizes on contour capture for root structures and point capture for ostia
- the old manual used 3 sinus points plus MIP alignment for projection-angle confirmation; this plugin now supports an optional 3-point confirmation step, but still uses a lightweight preview instead of a full MIP workflow
- brochure-style extras such as LVOT, membranous septum length, horizontal-aorta-style angle reporting, a virtual valve overlay, and Agatston-like calcium scoring are now included in a lightweight form
- the old manual included PDF screenshots and access-route planning steps; this plugin currently exports text and CSV only

## Notes

- The advisory fluoroscopic angle output is not vendor-validated and should be treated as planning guidance only.
- The assisted annulus fit is a convenience overlay derived from the captured contour, not a replacement for clinical review.
- The calcium assist and Agatston-like score are based on the captured contour slice, not full 3D segmentation.
- The plugin does not attempt device sizing, access-route planning, PDF reporting, or helper-app workflows.
