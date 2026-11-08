#include "hatses.h"

#include <godot_cpp/core/class_db.hpp>
#include <opus.h>
#include <cstring>
#include <vector>

using namespace godot;

// ---------------- HatSes ----------------

static bool calisan_var = false; // platform yolu tektir

HatSes::HatSes() {}

HatSes::~HatSes() { durdur(); }

bool HatSes::baslat(int oran) {
	if (acik)
		return true;
	if (calisan_var) {
		arka.durum = "baska bir HatSes calisiyor";
		return false;
	}
	giris.kur((size_t)oran * 2); // 2 sn
	cikis.kur((size_t)oran * 2); // stereo 1 sn
	arka.giris = &giris;
	arka.cikis = &cikis;
	arka.oran = oran;
	acik = arka_baslat(arka);
	calisan_var = acik;
	return acik;
}

void HatSes::durdur() {
	if (!acik)
		return;
	arka_durdur();
	acik = false;
	calisan_var = false;
}

bool HatSes::cikis_var() const { return acik && arka_cikis_var(); }

bool HatSes::yanki_engelleme() const { return acik && arka_yanki_engelleme(); }

PackedFloat32Array HatSes::oku() {
	PackedFloat32Array p;
	const size_t n = giris.dolu();
	if (n == 0)
		return p;
	p.resize((int64_t)n);
	const size_t okunan = giris.oku(p.ptrw(), n);
	if (okunan < n)
		p.resize((int64_t)okunan);
	return p;
}

void HatSes::yaz(const PackedVector2Array &v) {
	if (!acik || v.is_empty())
		return;
	std::vector<float> ara((size_t)v.size() * 2);
	const Vector2 *r = v.ptr();
	for (int64_t i = 0; i < v.size(); i++) {
		ara[(size_t)i * 2] = r[i].x;
		ara[(size_t)i * 2 + 1] = r[i].y;
	}
	cikis.yaz(ara.data(), ara.size());
}

int HatSes::bos_yer() const { return (int)(cikis.bos() / 2); }

int HatSes::bekleyen() const { return (int)(cikis.dolu() / 2); }

String HatSes::durum() const { return String::utf8(arka.durum.c_str()); }

void HatSes::_bind_methods() {
	ClassDB::bind_method(D_METHOD("baslat", "oran"), &HatSes::baslat);
	ClassDB::bind_method(D_METHOD("durdur"), &HatSes::durdur);
	ClassDB::bind_method(D_METHOD("calisiyor"), &HatSes::calisiyor);
	ClassDB::bind_method(D_METHOD("cikis_var"), &HatSes::cikis_var);
	ClassDB::bind_method(D_METHOD("yanki_engelleme"), &HatSes::yanki_engelleme);
	ClassDB::bind_method(D_METHOD("oku"), &HatSes::oku);
	ClassDB::bind_method(D_METHOD("yaz", "kareler"), &HatSes::yaz);
	ClassDB::bind_method(D_METHOD("bos_yer"), &HatSes::bos_yer);
	ClassDB::bind_method(D_METHOD("bekleyen"), &HatSes::bekleyen);
	ClassDB::bind_method(D_METHOD("durum"), &HatSes::durum);
}

// ---------------- Opus ----------------

HatOpusKodlayici::~HatOpusKodlayici() {
	if (k)
		opus_encoder_destroy(k);
}

bool HatOpusKodlayici::kur(int oran, int bit_hizi) {
	if (k) {
		opus_encoder_destroy(k);
		k = nullptr;
	}
	int e = 0;
	k = opus_encoder_create(oran, 1, OPUS_APPLICATION_VOIP, &e);
	if (e != OPUS_OK || !k) {
		k = nullptr;
		return false;
	}
	opus_encoder_ctl(k, OPUS_SET_BITRATE(bit_hizi));
	opus_encoder_ctl(k, OPUS_SET_VBR(1));
	opus_encoder_ctl(k, OPUS_SET_COMPLEXITY(8));
	opus_encoder_ctl(k, OPUS_SET_SIGNAL(OPUS_SIGNAL_VOICE));
	opus_encoder_ctl(k, OPUS_SET_DTX(0));
	return true;
}

PackedByteArray HatOpusKodlayici::kodla(const PackedFloat32Array &pcm) {
	PackedByteArray out;
	if (!k || pcm.is_empty())
		return out;
	unsigned char tampon[1500];
	const opus_int32 n = opus_encode_float(k, pcm.ptr(), (int)pcm.size(), tampon, (opus_int32)sizeof(tampon));
	if (n <= 0)
		return out;
	out.resize(n);
	memcpy(out.ptrw(), tampon, (size_t)n);
	return out;
}

void HatOpusKodlayici::_bind_methods() {
	ClassDB::bind_method(D_METHOD("kur", "oran", "bit_hizi"), &HatOpusKodlayici::kur);
	ClassDB::bind_method(D_METHOD("kodla", "pcm"), &HatOpusKodlayici::kodla);
}

HatOpusCozucu::~HatOpusCozucu() {
	if (c)
		opus_decoder_destroy(c);
}

bool HatOpusCozucu::kur(int o) {
	if (c) {
		opus_decoder_destroy(c);
		c = nullptr;
	}
	oran = o;
	int e = 0;
	c = opus_decoder_create(oran, 1, &e);
	if (e != OPUS_OK || !c) {
		c = nullptr;
		return false;
	}
	return true;
}

PackedFloat32Array HatOpusCozucu::coz(const PackedByteArray &paket) {
	PackedFloat32Array out;
	if (!c || paket.is_empty())
		return out;
	const int azami = oran * 120 / 1000; // en uzun Opus karesi 120 ms
	out.resize(azami);
	const int n = opus_decode_float(c, paket.ptr(), (opus_int32)paket.size(), out.ptrw(), azami, 0);
	if (n <= 0) {
		out.resize(0);
		return out;
	}
	out.resize(n);
	return out;
}

PackedFloat32Array HatOpusCozucu::kayip(int ornek) {
	PackedFloat32Array out;
	if (!c || ornek <= 0)
		return out;
	out.resize(ornek);
	const int n = opus_decode_float(c, nullptr, 0, out.ptrw(), ornek, 0);
	out.resize(n > 0 ? n : 0);
	return out;
}

void HatOpusCozucu::_bind_methods() {
	ClassDB::bind_method(D_METHOD("kur", "oran"), &HatOpusCozucu::kur);
	ClassDB::bind_method(D_METHOD("coz", "paket"), &HatOpusCozucu::coz);
	ClassDB::bind_method(D_METHOD("kayip", "ornek"), &HatOpusCozucu::kayip);
}
