// Masaüstü vb.: platform sesli görüşme yolu yok; oyun Godot'nun mikrofonunu ve hoparlörünü kullanır.
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#if !defined(__ANDROID__) && !(defined(__APPLE__) && TARGET_OS_IPHONE)
#include "arka.h"

bool arka_baslat(Arka &a) {
	a.durum = "bu platformda yerel ses yolu yok";
	return false;
}
void arka_durdur() {}
bool arka_cikis_var() { return false; }
bool arka_yanki_engelleme() { return false; }
#endif
