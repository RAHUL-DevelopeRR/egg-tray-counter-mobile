# Capture frame restriction

Implemented for the LEFT / RIGHT / STRAIGHT mobile capture flow.

## Enforced now

- LEFT and RIGHT use mirrored trapezoid guides; STRAIGHT uses a rectangular guide.
- The guide is red until all framing confirmations pass, then turns green.
- Capture remains disabled until the operator confirms:
  1. exactly one physical stack is completely inside the guide;
  2. the stack top and base are visible, with the base aligned to the lower guide;
  3. the requested view angle matches the guide.
- Each new view resets the gate.
- Post-capture minimum resolution, blur, underexposure and overexposure checks still run.
- Retaking one view preserves the other accepted views.

## Deliberately not claimed

The current app does not yet run a compatible live `stack_face` model on camera
preview frames, so stack containment is operator-confirmed rather than
automatically detected. The grid standardizes acquisition; it does not prove the
count. Automatic containment, phone roll/pitch and ArUco lane identification are
future measurable gates and should not be represented as implemented.

The experimental V2 bridge is restricted to a single framed physical stack. It
never adds LEFT, RIGHT and STRAIGHT detections: two quality-approved views must
return the same positive `egg_tray` count, otherwise the API returns `RESCAN
REQUIRED`.
