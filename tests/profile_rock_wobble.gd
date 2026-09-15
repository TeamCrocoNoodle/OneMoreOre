extends "res://tests/profile_extreme_mining.gd"
## Same physical 4,736-stone workload, with the live recoil transform included.
## The old stress harness held Main._process, so it never exercised this motion.
var _motion_previous_usec := 0
var _motion_cpu: Array[float] = []
var _peak_angle := 0.0
var _peak_speed := 0.0

func _maintenance() -> void:
	super._maintenance()
	var now := Time.get_ticks_usec()
	var delta := (now-_motion_previous_usec)/1000000.0 if _motion_previous_usec > 0 else 0.0
	_motion_previous_usec = now
	_peak_speed = maxf(_peak_speed,game.wobble_velocity.length())
	var started := Time.get_ticks_usec()
	game._advance_rock_wobble(delta)
	_motion_cpu.append((Time.get_ticks_usec()-started)/1000.0)
	_peak_angle = maxf(_peak_angle,game.wobble.length())
	_check(game.wobble.is_finite() and game.wobble.length() <= deg_to_rad(6.01),"Recoil remains bounded while physical stones render, react and retire")

func _finish() -> void:
	if finished: return
	results["recoil"] = {"peak_degrees":rad_to_deg(_peak_angle),"peak_speed":_peak_speed,"cpu_ms":_stats(_motion_cpu),"includes_child_transform_updates":true}
	super._finish()
