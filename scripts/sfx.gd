# Oyundaki sesleri dosya kullanmadan, koddan üretir.
extends RefCounted

const RATE := 22050


static func _wav(samples: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in samples.size():
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = samples.size()
	return w


# Eski tip zil: iki kısa çınlama, sonra sessizlik (3 saniyede bir tekrar).
static func ring() -> AudioStreamWAV:
	var n := int(RATE * 3.0)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var on := (t < 0.45) or (t > 0.6 and t < 1.05)
		if not on:
			s[i] = 0.0
			continue
		var since := fmod(t, 1.0 / 22.0)
		var env := exp(-since * 35.0)
		s[i] = (sin(TAU * 920.0 * t) * 0.55 + sin(TAU * 1380.0 * t) * 0.35) * env * 0.8
	return _wav(s, true)


static func click() -> AudioStreamWAV:
	var n := int(RATE * 0.12)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (randf() * 2.0 - 1.0) * exp(-t * 60.0) * 0.7 + sin(TAU * 180.0 * t) * exp(-t * 40.0) * 0.5
	return _wav(s)


# Ağır çelik kapı: gıcırtı + tok vuruş.
static func door(opening: bool) -> AudioStreamWAV:
	var n := int(RATE * 1.0)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		if opening and t < 0.7:
			var f := 260.0 + 180.0 * t + sin(t * 37.0) * 25.0
			phase += TAU * f / RATE
			var a := sin(PI * t / 0.7) * 0.25
			v += (sin(phase) + 0.4 * sin(phase * 2.03)) * a * (0.7 + 0.3 * randf())
		var hit_t := t - (0.75 if opening else 0.05)
		if hit_t > 0.0:
			v += sin(TAU * 65.0 * hit_t) * exp(-hit_t * 9.0) * 0.8
			v += (randf() * 2.0 - 1.0) * exp(-hit_t * 30.0) * 0.4
		s[i] = v
	return _wav(s)
