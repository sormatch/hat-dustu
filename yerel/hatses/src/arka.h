// Platform ses arka ucu: telefonun sesli görüşme yolu (yankı engelleme + gürültü bastırma).
//   iOS: AVAudioEngine + ses işleme (Voice Processing I/O): mikrofon ve gelen konuşma aynı birimden geçer,
//        Apple'ın yankı engelleyicisi hoparlöre gideni bilir ve mikrofondan çıkarır.
//   Android: AAudio, giriş ön ayarı VOICE_COMMUNICATION (platformun yankı engelleyicisi + gürültü bastırma).
//            Çıkış Godot'da kalır.
// Oyun tarafı örnek oranı (ör. 24000) sabittir; donanım farklıysa burada dönüştürülür.
#pragma once
#include "halka.h"
#include <string>

struct Arka {
	Halka *giris = nullptr; // mikrofon (mono, oyun oranında)
	Halka *cikis = nullptr; // hoparlöre gidecek konuşma (stereo, iç içe L R, oyun oranında); yalnız iOS
	int oran = 24000;
	std::string durum;
};

bool arka_baslat(Arka &a); // başarısızsa false (oyun Godot'nun kendi mikrofonuna döner)
void arka_durdur();
bool arka_cikis_var(); // gelen konuşma bu yoldan mı çalıyor (iOS: evet)
bool arka_yanki_engelleme(); // platform yankı engelleyici açık mı
