// Android arka ucu: AAudio ile mikrofon, giriş ön ayarı VOICE_COMMUNICATION (platformun yankı engelleyicisi ve
// gürültü bastırması bu ön ayara bağlıdır). AAudio çalışma anında açılır (dlopen): Android 8 öncesinde ya da
// başarısızlıkta false döner, oyun Godot'nun kendi mikrofonunu kullanır. Çıkış Godot'da kalır.
#if defined(__ANDROID__)
#include "arka.h"
#include <aaudio/AAudio.h>
#include <android/api-level.h>
#include <dlfcn.h>
#include <vector>

namespace {
typedef aaudio_result_t (*f_create)(AAudioStreamBuilder **);
typedef void (*f_b_int)(AAudioStreamBuilder *, int32_t);
typedef void (*f_b_cb)(AAudioStreamBuilder *, AAudioStream_dataCallback, void *);
typedef void (*f_b_ecb)(AAudioStreamBuilder *, AAudioStream_errorCallback, void *);
typedef aaudio_result_t (*f_open)(AAudioStreamBuilder *, AAudioStream **);
typedef aaudio_result_t (*f_b_del)(AAudioStreamBuilder *);
typedef aaudio_result_t (*f_s)(AAudioStream *);
typedef int32_t (*f_s_int)(AAudioStream *);

void *lib = nullptr;
f_create p_create;
f_b_int p_dir, p_rate, p_ch, p_fmt, p_perf, p_share, p_preset;
f_b_cb p_cb;
f_b_ecb p_ecb;
f_open p_open;
f_b_del p_del;
f_s p_start, p_stop, p_close;
f_s_int p_getrate;

AAudioStream *akis = nullptr;
Arka *A = nullptr;
Donusturucu cevir;
std::vector<float> ara;
bool acik = false;
bool onayar = false;

template <typename T>
bool bul(T &p, const char *ad) {
	p = (T)dlsym(lib, ad);
	return p != nullptr;
}

aaudio_data_callback_result_t veri_geldi(AAudioStream *s, void *u, void *veri, int32_t n) {
	const float *g = (const float *)veri;
	if (cevir.gerekli()) {
		ara.clear();
		cevir.isle(g, (size_t)n, ara);
		A->giris->yaz(ara.data(), ara.size());
	} else {
		A->giris->yaz(g, (size_t)n);
	}
	return AAUDIO_CALLBACK_RESULT_CONTINUE;
}

void hata(AAudioStream *s, void *u, aaudio_result_t e) {
	// akış koptu (kulaklık, arama): oyun tarafı durumu görür ve yeniden başlatır
	acik = false;
}
} // namespace

bool arka_baslat(Arka &a) {
	A = &a;
	if (!lib)
		lib = dlopen("libaaudio.so", RTLD_NOW);
	if (!lib) {
		a.durum = "aaudio yok";
		return false;
	}
	bool tamam = bul(p_create, "AAudio_createStreamBuilder") && bul(p_dir, "AAudioStreamBuilder_setDirection") &&
			bul(p_rate, "AAudioStreamBuilder_setSampleRate") && bul(p_ch, "AAudioStreamBuilder_setChannelCount") &&
			bul(p_fmt, "AAudioStreamBuilder_setFormat") && bul(p_perf, "AAudioStreamBuilder_setPerformanceMode") &&
			bul(p_share, "AAudioStreamBuilder_setSharingMode") && bul(p_cb, "AAudioStreamBuilder_setDataCallback") &&
			bul(p_ecb, "AAudioStreamBuilder_setErrorCallback") && bul(p_open, "AAudioStreamBuilder_openStream") &&
			bul(p_del, "AAudioStreamBuilder_delete") && bul(p_start, "AAudioStream_requestStart") &&
			bul(p_stop, "AAudioStream_requestStop") && bul(p_close, "AAudioStream_close") &&
			bul(p_getrate, "AAudioStream_getSampleRate");
	if (!tamam) {
		a.durum = "aaudio islevleri eksik";
		return false;
	}
	onayar = bul(p_preset, "AAudioStreamBuilder_setInputPreset"); // Android 9+
	if (!onayar) {
		a.durum = "giris on ayari yok (android 9 oncesi)";
		return false; // yankı engelleme olmadan bu yolun yararı yok: Godot'nun mikrofonu kullanılsın
	}
	AAudioStreamBuilder *b = nullptr;
	if (p_create(&b) != AAUDIO_OK || !b) {
		a.durum = "aaudio kurucu yok";
		return false;
	}
	p_dir(b, AAUDIO_DIRECTION_INPUT);
	p_rate(b, a.oran);
	p_ch(b, 1);
	p_fmt(b, AAUDIO_FORMAT_PCM_FLOAT);
	// düşük gecikme kipi ses işlemeyi (yankı engelleme) atlayabilir: varsayılan kip
	p_perf(b, AAUDIO_PERFORMANCE_MODE_NONE);
	p_share(b, AAUDIO_SHARING_MODE_SHARED);
	p_preset(b, AAUDIO_INPUT_PRESET_VOICE_COMMUNICATION);
	p_cb(b, veri_geldi, nullptr);
	p_ecb(b, hata, nullptr);
	aaudio_result_t r = p_open(b, &akis);
	p_del(b);
	if (r != AAUDIO_OK || !akis) {
		a.durum = "aaudio acilamadi " + std::to_string((int)r);
		akis = nullptr;
		return false;
	}
	const int gercek = p_getrate(akis);
	cevir.kur((double)(gercek > 0 ? gercek : a.oran), (double)a.oran);
	if (p_start(akis) != AAUDIO_OK) {
		p_close(akis);
		akis = nullptr;
		a.durum = "aaudio baslamadi";
		return false;
	}
	acik = true;
	a.durum = "android sesli iletisim girisi (yanki engelleme) acik, oran " + std::to_string(gercek);
	return true;
}

void arka_durdur() {
	if (akis) {
		p_stop(akis);
		p_close(akis);
		akis = nullptr;
	}
	acik = false;
}

bool arka_cikis_var() { return false; }
bool arka_yanki_engelleme() { return acik; }
#endif
