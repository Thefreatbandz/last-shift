class_name OverlayMixer
extends RefCounted
## Additive animation-overlay mixer with interrupt blending.
##
## Each frame the visual reads its LIVE base-pose channel values, computes
## pure envelope offsets (zero at both ends of an action), and mix() returns
## base + offsets + decaying residue from any interrupted action.
##
## Why this design: every write derives from the live base, so values can
## never go stale (no snapshot pop when the base kept moving), can never
## accumulate (offsets are absolute per frame, not +=), and interrupting an
## action crossfades its in-flight offsets out over RELEASE_TIME instead of
## snapping. Envelope offsets must be 0 at t=0 and t=1; residue handles the
## rest.

const RELEASE_TIME := 0.2

var _residue := {}
var _residue_t := 99.0
var _last_total := {}


## An action was interrupted (or superseded): carry the offsets that were
## actually written last frame and decay them out smoothly. Only call this
## when an action is genuinely in flight; otherwise stale totals leak in.
func interrupt() -> void:
	_residue = _last_total.duplicate()
	_residue_t = 0.0
	_last_total = {}


func has_residue() -> bool:
	return not _residue.is_empty() and _residue_t < RELEASE_TIME


## base: live channel values AFTER the base pose ran this frame.
## offsets: this frame's pure envelope offsets (0 at both envelope ends).
## Returns the final channel values to write.
func mix(delta: float, base: Dictionary, offsets: Dictionary) -> Dictionary:
	_residue_t += delta
	var rd := 1.0 - smoothstep(0.0, RELEASE_TIME, _residue_t)
	var out := {}
	_last_total = {}
	for ch in base:
		var r: float = float(_residue.get(ch, 0.0)) * rd
		var o: float = float(offsets.get(ch, 0.0))
		out[ch] = float(base[ch]) + o + r
		_last_total[ch] = o + r
	if rd <= 0.0 and not _residue.is_empty():
		_residue.clear()
	return out
