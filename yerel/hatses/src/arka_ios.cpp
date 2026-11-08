// iOS arka ucu (Objective-C++; SConstruct bu dosyayı iOS'ta "-x objective-c++" ile derler).
#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#if defined(__APPLE__) && TARGET_OS_IPHONE
#import <AVFoundation/AVFoundation.h>
#include "arka.h"
#include <vector>

static AVAudioEngine *motor = nil;
static AVAudioSourceNode *kaynak = nil;
static AVAudioConverter *cevir = nil;
static id gozcu = nil;
static Arka *A = nullptr;
static bool vp_acik = false;
static bool cikis_acik = false;

static bool kur_ve_baslat() {
	NSError *e = nil;
	AVAudioSession *s = [AVAudioSession sharedInstance];
	// sesli görüşme modu: hoparlör varsayılan (kulaklık yerine), bluetooth serbest, oyunun müziğiyle karışır
	[s setCategory:AVAudioSessionCategoryPlayAndRecord
				mode:AVAudioSessionModeVoiceChat
			 options:(AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionAllowBluetooth |
							 AVAudioSessionCategoryOptionAllowBluetoothA2DP | AVAudioSessionCategoryOptionMixWithOthers)
			   error:&e];
	[s setPreferredIOBufferDuration:0.01 error:nil];
	[s setActive:YES error:nil];

	motor = [[AVAudioEngine alloc] init];
	AVAudioInputNode *giris = motor.inputNode;
	e = nil;
	vp_acik = [giris setVoiceProcessingEnabled:YES error:&e];
	if (!vp_acik) {
		A->durum = "ses isleme acilamadi";
		motor = nil;
		return false;
	}
	// oyunun müziği ve efektleri sesli görüşmede kısılmasın
	if (@available(iOS 17.0, *)) {
		AVAudioVoiceProcessingOtherAudioDuckingConfiguration c;
		c.enableAdvancedDucking = NO;
		c.duckingLevel = AVAudioVoiceProcessingOtherAudioDuckingLevelMin;
		giris.voiceProcessingOtherAudioDuckingConfiguration = c;
	}
	// otomatik kazanç Apple'da (bizimki de çalışır; ikisi birlikte aşırıya kaçmasın diye sınır oyun tarafında)
	AVAudioFormat *donanim = [giris outputFormatForBus:0];
	if (donanim.sampleRate <= 0 || donanim.channelCount == 0) {
		A->durum = "mikrofon bicimi yok";
		motor = nil;
		return false;
	}
	AVAudioFormat *hedef = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatFloat32 sampleRate:A->oran channels:1 interleaved:NO];
	cevir = [[AVAudioConverter alloc] initFromFormat:donanim toFormat:hedef];
	const double oranKat = (double)A->oran / donanim.sampleRate;
	[giris installTapOnBus:0
				bufferSize:512
					format:donanim
					 block:^(AVAudioPCMBuffer *buf, AVAudioTime *when) {
						 if (!A || !cevir)
							 return;
						 AVAudioFrameCount cap = (AVAudioFrameCount)(buf.frameLength * oranKat) + 32;
						 AVAudioPCMBuffer *cik = [[AVAudioPCMBuffer alloc] initWithPCMFormat:hedef frameCapacity:cap];
						 __block BOOL verildi = NO;
						 NSError *ce = nil;
						 [cevir convertToBuffer:cik
										  error:&ce
							 withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount n, AVAudioConverterInputStatus *st) {
								 if (verildi) {
									 *st = AVAudioConverterInputStatus_NoDataNow;
									 return nil;
								 }
								 verildi = YES;
								 *st = AVAudioConverterInputStatus_HaveData;
								 return buf;
							 }];
						 if (cik.frameLength > 0 && cik.floatChannelData)
							 A->giris->yaz(cik.floatChannelData[0], cik.frameLength);
					 }];

	// gelen konuşma: oyun oranında stereo; motor donanıma kendi dönüştürür. Yankı engelleyici bunu referans alır.
	AVAudioFormat *cf = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:A->oran channels:2];
	kaynak = [[AVAudioSourceNode alloc] initWithFormat:cf
										   renderBlock:^OSStatus(BOOL *sessiz, const AudioTimeStamp *ts, AVAudioFrameCount n, AudioBufferList *abl) {
											   float *l = (float *)abl->mBuffers[0].mData;
											   float *r = abl->mNumberBuffers > 1 ? (float *)abl->mBuffers[1].mData : nullptr;
											   static thread_local std::vector<float> ara;
											   ara.resize((size_t)n * 2);
											   size_t okunan = A && A->cikis ? A->cikis->oku(ara.data(), (size_t)n * 2) / 2 : 0;
											   for (size_t i = 0; i < n; i++) {
												   float x = i < okunan ? ara[i * 2] : 0.0f;
												   float y = i < okunan ? ara[i * 2 + 1] : 0.0f;
												   l[i] = x;
												   if (r)
													   r[i] = y;
											   }
											   *sessiz = okunan == 0;
											   return noErr;
										   }];
	[motor attachNode:kaynak];
	[motor connect:kaynak to:motor.mainMixerNode format:cf];
	[motor prepare];
	e = nil;
	if (![motor startAndReturnError:&e]) {
		A->durum = std::string("motor baslamadi: ") + (e ? e.localizedDescription.UTF8String : "?");
		[giris removeTapOnBus:0];
		motor = nil;
		return false;
	}
	cikis_acik = true;
	A->durum = "ios ses isleme (yanki engelleme) acik";
	return true;
}

bool arka_baslat(Arka &a) {
	A = &a;
	if (!kur_ve_baslat())
		return false;
	// kulaklık takılınca / bluetooth değişince motor durur: yeniden başlat
	gozcu = [[NSNotificationCenter defaultCenter] addObserverForName:AVAudioEngineConfigurationChangeNotification
															  object:motor
															   queue:[NSOperationQueue mainQueue]
														  usingBlock:^(NSNotification *n) {
															  if (motor && !motor.isRunning) {
																  [motor prepare];
																  [motor startAndReturnError:nil];
															  }
														  }];
	return true;
}

void arka_durdur() {
	if (gozcu) {
		[[NSNotificationCenter defaultCenter] removeObserver:gozcu];
		gozcu = nil;
	}
	if (motor) {
		[motor.inputNode removeTapOnBus:0];
		[motor stop];
		motor = nil;
	}
	kaynak = nil;
	cevir = nil;
	cikis_acik = false;
	vp_acik = false;
}

bool arka_cikis_var() { return cikis_acik; }
bool arka_yanki_engelleme() { return vp_acik; }
#endif
