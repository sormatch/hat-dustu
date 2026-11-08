#pragma once
#include "arka.h"
#include "halka.h"

#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float32_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/string.hpp>

struct OpusEncoder;
struct OpusDecoder;

namespace godot {

// Telefonun sesli görüşme yolu (yankı engelleme). Aynı anda tek bir tane çalışır.
//   baslat(oran) -> bool   oku() -> mono PackedFloat32Array   yaz(PackedVector2Array) (yalnız cikis_var() ise)
class HatSes : public RefCounted {
	GDCLASS(HatSes, RefCounted)

public:
	HatSes();
	~HatSes();
	bool baslat(int oran);
	void durdur();
	bool calisiyor() const { return acik; }
	bool cikis_var() const;
	bool yanki_engelleme() const;
	PackedFloat32Array oku();
	void yaz(const PackedVector2Array &v);
	int bos_yer() const; // çıkış tamponunda kaç stereo kare yer var
	int bekleyen() const; // çıkış tamponunda kaç stereo kare çalınmayı bekliyor
	String durum() const;

protected:
	static void _bind_methods();

private:
	Arka arka;
	Halka giris{ 1 };
	Halka cikis{ 1 };
	bool acik = false;
};

// Opus sıkıştırıcı (konuşma). kur(oran, bit_hizi) ; kodla(40 ms mono) -> paket
class HatOpusKodlayici : public RefCounted {
	GDCLASS(HatOpusKodlayici, RefCounted)

public:
	~HatOpusKodlayici();
	bool kur(int oran, int bit_hizi);
	PackedByteArray kodla(const PackedFloat32Array &pcm);

protected:
	static void _bind_methods();

private:
	OpusEncoder *k = nullptr;
};

// Opus çözücü (konuşan başına bir tane). coz(paket) -> mono ; kayip(örnek) -> kayıp gizleme (PLC)
class HatOpusCozucu : public RefCounted {
	GDCLASS(HatOpusCozucu, RefCounted)

public:
	~HatOpusCozucu();
	bool kur(int oran);
	PackedFloat32Array coz(const PackedByteArray &paket);
	PackedFloat32Array kayip(int ornek);

protected:
	static void _bind_methods();

private:
	OpusDecoder *c = nullptr;
	int oran = 24000;
};

} // namespace godot
