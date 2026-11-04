# Bilgisayar sürümünün exe dosyasına oyunun simgesini koyar (rcedit gerekmez; Windows'un UpdateResource API'si).
# Kullanım:  powershell -NoProfile -ExecutionPolicy Bypass -File tools\exe_ikon.ps1 -Exe build\pc\HatDustu\HatDustu.exe [-Png assets\ui\uretim\uygulama_ikonu.png]
# PNG'den 16..256 px boyutlarında PNG gömülü bir .ico üretilir; exe'deki eski simgeler silinip yenisi yazılır.
param(
	[Parameter(Mandatory = $true)][string]$Exe,
	[string]$Png = "assets\ui\uretim\uygulama_ikonu.png"
)
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class ExeIkon {
	[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
	static extern IntPtr BeginUpdateResource(string file, bool deleteExisting);
	[DllImport("kernel32.dll", SetLastError = true)]
	static extern bool UpdateResource(IntPtr h, IntPtr type, IntPtr name, ushort lang, byte[] data, uint size);
	[DllImport("kernel32.dll", SetLastError = true)]
	static extern bool EndUpdateResource(IntPtr h, bool discard);
	[DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
	static extern IntPtr LoadLibraryEx(string file, IntPtr h, uint flags);
	[DllImport("kernel32.dll")] static extern bool FreeLibrary(IntPtr h);
	delegate bool EnumName(IntPtr m, IntPtr type, IntPtr name, IntPtr p);
	delegate bool EnumLang(IntPtr m, IntPtr type, IntPtr name, ushort lang, IntPtr p);
	[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool EnumResourceNames(IntPtr m, IntPtr type, EnumName cb, IntPtr p);
	[DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern bool EnumResourceLanguages(IntPtr m, IntPtr type, IntPtr name, EnumLang cb, IntPtr p);
	const int RT_ICON = 3, RT_GROUP_ICON = 14;

	// [tür, ad (sayı ya da metin), dil] listesi
	static List<object[]> Liste(string exe, int tur) {
		var l = new List<object[]>();
		IntPtr m = LoadLibraryEx(exe, IntPtr.Zero, 0x2); // LOAD_LIBRARY_AS_DATAFILE
		if (m == IntPtr.Zero) throw new Exception("exe açılamadı: " + Marshal.GetLastWin32Error());
		EnumResourceNames(m, (IntPtr)tur, (mm, t, n, p) => {
			object ad = ((long)n >> 16) == 0 ? (object)(int)(long)n : Marshal.PtrToStringUni(n);
			EnumResourceLanguages(mm, t, n, (m2, t2, n2, lang, p2) => { l.Add(new object[] { ad, lang }); return true; }, IntPtr.Zero);
			return true;
		}, IntPtr.Zero);
		FreeLibrary(m);
		return l;
	}

	static bool Yaz(IntPtr h, int tur, object ad, ushort lang, byte[] veri) {
		if (ad is int) return UpdateResource(h, (IntPtr)tur, (IntPtr)(int)ad, lang, veri, veri == null ? 0u : (uint)veri.Length);
		IntPtr s = Marshal.StringToHGlobalUni((string)ad);
		try { return UpdateResource(h, (IntPtr)tur, s, lang, veri, veri == null ? 0u : (uint)veri.Length); }
		finally { Marshal.FreeHGlobal(s); }
	}

	// resimler: her boyut için PNG baytları; boyutlar: piksel
	public static string Koy(string exe, byte[][] resimler, int[] boyutlar) {
		var gruplar = Liste(exe, RT_GROUP_ICON);
		var ikonlar = Liste(exe, RT_ICON);
		object grupAd = gruplar.Count > 0 ? gruplar[0][0] : (object)1;
		ushort dil = gruplar.Count > 0 ? (ushort)gruplar[0][1] : (ushort)1033;
		IntPtr h = BeginUpdateResource(exe, false);
		if (h == IntPtr.Zero) throw new Exception("BeginUpdateResource: " + Marshal.GetLastWin32Error());
		// aynı ad + dildeki kaynak üzerine yazılır (önce silip aynısını eklemek 1359 hatası veriyor);
		// yalnız kullanılmayacak eski kaynaklar silinir
		for (int g = 1; g < gruplar.Count; g++) Yaz(h, RT_GROUP_ICON, gruplar[g][0], (ushort)gruplar[g][1], null);
		foreach (var i in ikonlar) {
			bool ust = (i[0] is int) && (int)i[0] >= 1 && (int)i[0] <= resimler.Length && (ushort)i[1] == dil;
			if (!ust) Yaz(h, RT_ICON, i[0], (ushort)i[1], null);
		}
		// GRPICONDIR: 6 bayt başlık + her simge için 14 bayt
		var grp = new byte[6 + 14 * resimler.Length];
		grp[2] = 1; grp[4] = (byte)resimler.Length;
		for (int k = 0; k < resimler.Length; k++) {
			int id = k + 1;
			if (!Yaz(h, RT_ICON, id, dil, resimler[k])) throw new Exception("RT_ICON yazılamadı: " + Marshal.GetLastWin32Error());
			int o = 6 + 14 * k;
			int b = boyutlar[k];
			grp[o] = (byte)(b >= 256 ? 0 : b); grp[o + 1] = (byte)(b >= 256 ? 0 : b);
			grp[o + 4] = 1; grp[o + 6] = 32; // düzlem, bit derinliği
			BitConverter.GetBytes((uint)resimler[k].Length).CopyTo(grp, o + 8);
			BitConverter.GetBytes((ushort)id).CopyTo(grp, o + 12);
		}
		if (!Yaz(h, RT_GROUP_ICON, grupAd, dil, grp)) throw new Exception("RT_GROUP_ICON yazılamadı: " + Marshal.GetLastWin32Error());
		if (!EndUpdateResource(h, false)) throw new Exception("EndUpdateResource: " + Marshal.GetLastWin32Error());
		return "eski grup " + gruplar.Count + ", eski simge " + ikonlar.Count + " -> yeni " + resimler.Length + " simge (grup " + grupAd + ", dil " + dil + ")";
	}
}
"@

$exeYol = (Resolve-Path $Exe).Path
$kaynak = [System.Drawing.Image]::FromFile((Resolve-Path $Png).Path)
$boyutlar = @(16, 24, 32, 48, 64, 128, 256)
$resimler = New-Object 'System.Collections.Generic.List[byte[]]'
foreach ($b in $boyutlar) {
	$bmp = New-Object System.Drawing.Bitmap $b, $b, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
	$g = [System.Drawing.Graphics]::FromImage($bmp)
	$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
	$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
	$g.DrawImage($kaynak, 0, 0, $b, $b)
	$g.Dispose()
	$ms = New-Object System.IO.MemoryStream
	$bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
	$resimler.Add($ms.ToArray())
	$bmp.Dispose()
}
$kaynak.Dispose()
[ExeIkon]::Koy($exeYol, $resimler.ToArray(), [int[]]$boyutlar)
