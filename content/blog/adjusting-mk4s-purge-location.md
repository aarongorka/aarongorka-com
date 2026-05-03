---
title: "Adjusting Prusa MK4S Purge (Clean) Location"
date: 2026-05-03T12:40:15+10:00
featuredImage: "/blog/adjusting-prusa-mk4s-purge-clean-location/purge.jpg"
---

I've printed enough on my Prusa MK4S 3D printer that the location for the initial purge to clean the nozzle has ripped a layer off the bed. The fix is pretty simple but requires changing the G-code for your printer.

<!--more-->

# How to

![custom g-code settings in PrusaSlicer](prusaslicer.png)

Under Printers -> Custom G-code -> Start G-code, if you scroll down a bit, you'll find the "Extrude purge line" section. Here I've updated it to shift 30mm to the right (leaving in the original lines as comments for reference):

```gcode
;
; Extrude purge line
;
G92 E0 ; reset extruder position
G1 E{(filament_type[0] == "FLEX" ? 4 : 2)} F2400 ; deretraction after the initial one before nozzle cleaning
; G0 E7 X15 Z0.2 F500 ; purge
G0 E7 X45 Z0.2 F500 ; NOTE: values updated 30mm to the right to avoid worn spot
; G0 X25 E4 F500 ; purge
G0 X55 E4 F500 ; purge
; G0 X35 E4 F650 ; purge
G0 X65 E4 F650 ; purge
; G0 X45 E4 F800 ; purge
G0 X75 E4 F800 ; purge
; G0 X48 Z0.05 F8000 ; wipe, move close to the bed
G0 X78 Z0.05 F8000 ; wipe, move close to the bed
; G0 X51 Z0.2 F8000 ; wipe, move quickly away from the bed
G0 X81 Z0.2 F8000 ; wipe, move quickly away from the bed
```

So, initial location of `X15` -> `X45`, and so on.

# Result

And now I don't need to buy a whole new plate:

![purge line no longer created in the worn spot](purge.jpg)
