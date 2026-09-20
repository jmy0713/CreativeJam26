extends SceneTree

func _initialize() -> void:
	var p: Node = load("res://scripts/prologue.gd").new()
	var s: AudioStreamWAV = p._make_voice()
	var d := s.data
	var peak := 0
	var nonzero := 0
	for i in range(0, d.size(), 2):
		var v: int = d.decode_s16(i)
		peak = maxi(peak, absi(v))
		if v != 0:
			nonzero += 1
	print("blip: %.3fs  %d samples  peak=%d  nonzero=%d  rate=%d" % [
		s.get_length(), d.size() / 2, peak, nonzero, s.mix_rate])
	p.free()
	quit()
