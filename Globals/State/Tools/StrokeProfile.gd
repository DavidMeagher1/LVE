extends RefCounted


static var enabled := false
static var finish_us := 0
static var finish_seq := 0


static func mark_us() -> int:
	return Time.get_ticks_usec() if enabled else 0


static func publish(started_us: int) -> void:
	if not enabled:
		return
	finish_us = Time.get_ticks_usec() - started_us
	finish_seq += 1
