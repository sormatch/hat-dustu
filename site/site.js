// Hat Düştü: küçük dokunuşlar (telefon, oyun kartları, fragman, kaydırınca belirme)
(function () {
  var azHareket = window.matchMedia && matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Çalan telefon: dokununca ahize kalkar, baloncukta bir söz çıkar
  var tel = document.querySelector('.telefon');
  if (tel) {
    var balon = tel.querySelector('.balon');
    var sozler = (tel.getAttribute('data-sozler') || '').split('|');
    var son = -1, kapat, cal;
    tel.addEventListener('click', function () {
      clearTimeout(kapat); clearTimeout(cal);
      var i;
      do { i = Math.floor(Math.random() * sozler.length); } while (sozler.length > 1 && i === son);
      son = i;
      balon.textContent = sozler[i];
      tel.classList.remove('caliyor');
      tel.classList.add('acik');
      kapat = setTimeout(function () { tel.classList.remove('acik'); }, 3200);
      cal = setTimeout(function () { tel.classList.add('caliyor'); }, 12000);
    });
  }

  // Mini oyun kartları: dokununca kısa bir tepki
  document.querySelectorAll('.oyun').forEach(function (kart) {
    var damga = kart.querySelector('.tepki');
    var sure;
    kart.addEventListener('click', function () {
      if (kart.getAttribute('data-oyun') === 'ortalama') {
        damga.textContent = Math.floor(Math.random() * 50 + 1) + '?';
      }
      kart.classList.remove('tepkili');
      void kart.offsetWidth;
      kart.classList.add('tepkili');
      clearTimeout(sure);
      sure = setTimeout(function () { kart.classList.remove('tepkili'); }, azHareket ? 1400 : 1050);
    });
  });

  // Fragman oynarken "KAYIT" etiketi kaybolur
  var video = document.getElementById('fragman');
  if (video) {
    var ekran = video.closest('.ekran');
    video.addEventListener('play', function () { ekran.classList.add('oynuyor'); });
    video.addEventListener('pause', function () { ekran.classList.remove('oynuyor'); });
    video.addEventListener('ended', function () { ekran.classList.remove('oynuyor'); });
  }

  // Kaydırınca belirme
  var parcalar = document.querySelectorAll('.belir');
  if (!('IntersectionObserver' in window) || azHareket) {
    parcalar.forEach(function (p) { p.classList.add('gorundu'); });
  } else {
    var gozcu = new IntersectionObserver(function (girdiler) {
      girdiler.forEach(function (g) {
        if (g.isIntersecting) { g.target.classList.add('gorundu'); gozcu.unobserve(g.target); }
      });
    }, { rootMargin: '0px 0px -8% 0px' });
    parcalar.forEach(function (p) { gozcu.observe(p); });
  }
})();
