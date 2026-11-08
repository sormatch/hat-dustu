// Tek üreten / tek tüketen kilitsiz halka tampon (ses iş parçacığı <-> oyun iş parçacığı).
#pragma once
#include <atomic>
#include <cstdint>
#include <vector>

class Halka {
public:
	explicit Halka(size_t kapasite = 1) { kur(kapasite); }

	void kur(size_t kapasite) {
		veri.assign(kapasite + 1, 0.0f);
		bas.store(0);
		son.store(0);
	}

	size_t dolu() const {
		const size_t b = bas.load(std::memory_order_acquire);
		const size_t s = son.load(std::memory_order_acquire);
		return s >= b ? s - b : veri.size() - b + s;
	}

	size_t bos() const { return veri.size() - 1 - dolu(); }

	// Yazar; yer yoksa en eski veriyi atar (ses gecikmesi büyümesin). Yalnız üretici çağırır.
	void yaz(const float *p, size_t n) {
		const size_t cap = veri.size();
		size_t s = son.load(std::memory_order_relaxed);
		for (size_t i = 0; i < n; i++) {
			veri[s] = p[i];
			s = (s + 1) % cap;
			if (s == bas.load(std::memory_order_acquire)) {
				// dolu: tüketicinin işi olan baş ilerletilmez; bu örnek atılır
				s = (s + cap - 1) % cap;
				break;
			}
		}
		son.store(s, std::memory_order_release);
	}

	// En çok n örnek okur, okunanı döndürür. Yalnız tüketici çağırır.
	size_t oku(float *p, size_t n) {
		const size_t cap = veri.size();
		size_t b = bas.load(std::memory_order_relaxed);
		const size_t s = son.load(std::memory_order_acquire);
		size_t i = 0;
		while (i < n && b != s) {
			p[i++] = veri[b];
			b = (b + 1) % cap;
		}
		bas.store(b, std::memory_order_release);
		return i;
	}

	// Tüketici tarafında hepsini atar
	void temizle() { bas.store(son.load(std::memory_order_acquire), std::memory_order_release); }

private:
	std::vector<float> veri;
	std::atomic<size_t> bas{ 0 };
	std::atomic<size_t> son{ 0 };
};

// Doğrusal örnek oranı dönüştürücü (konuşma için yeterli; giriş önceden alçak geçirenden geçmiş olmalı)
class Donusturucu {
public:
	void kur(double kaynak, double hedef) {
		adim = kaynak / hedef;
		konum = 0.0;
		onceki = 0.0f;
		lp = 0.0f;
		// aşağı örneklemede basit alçak geçiren (katlanma azalsın)
		alcak = hedef < kaynak;
		const double fc = hedef * 0.45;
		const double x = 2.0 * 3.14159265358979 * fc / kaynak;
		katsayi = (float)(x / (x + 1.0));
	}
	bool gerekli() const { return adim < 0.9999 || adim > 1.0001; }

	// giriş örneklerinden çıkış üretir, çıktıya ekler
	void isle(const float *g, size_t n, std::vector<float> &cikti) {
		for (size_t i = 0; i < n; i++) {
			float x = g[i];
			if (alcak) {
				lp += katsayi * (x - lp);
				x = lp;
			}
			// konum: [onceki, x] aralığında 0..1
			while (konum <= 1.0) {
				cikti.push_back(onceki + (x - onceki) * (float)konum);
				konum += adim;
			}
			konum -= 1.0;
			onceki = x;
		}
	}

private:
	double adim = 1.0;
	double konum = 0.0;
	float onceki = 0.0f;
	float lp = 0.0f;
	float katsayi = 1.0f;
	bool alcak = false;
};
