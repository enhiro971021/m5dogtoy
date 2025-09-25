import oscP5.*;
import netP5.*;
import processing.sound.*;

OscP5 oscP5;
// 加速度用の音（前のバージョンから復活）
SinOsc sine1, sine2, sine3;
TriOsc squeakOsc;
PinkNoise rustleNoise;
// ジャイロ用の音（種類を増やす）
SinOsc chirp1, chirp2;
TriOsc bellOsc;
SawOsc dogBark1, dogBark2;
// エフェクト
Env envelope, squeakEnv, chirpEnv, barkEnv;
BandPass bandPass;
LowPass dogFilter;

float[] acc = new float[3];  // 加速度 [x, y, z]
float[] gyro = new float[3]; // ジャイロ [x, y, z]

float accelMagnitude = 0;    // 加速度の大きさ
float gyroMagnitude = 0;     // ジャイロの大きさ
float prevAccelMag = 0;      // 前フレームの加速度
float soundThreshold = 2.0;   // 加速度音の閾値
float gyroThreshold = 60.0;   // ジャイロ音の閾値

boolean isThrown = false;     // 投球中フラグ
boolean isSqueaking = false;  // キュッキュッ音フラグ
boolean isPlayingGyroSound = false;   // ジャイロ音フラグ
float throwTimer = 0;         
float squeakTimer = 0;
float gyroSoundTimer = 0;
float lastGyroSoundTime = 0;
int currentGyroSound = 0;     // 現在のジャイロ音の種類

void setup() {
  size(400, 450);
  oscP5 = new OscP5(this, 8000);
  textSize(16);
  
  // 加速度用サウンドの初期化
  sine1 = new SinOsc(this);
  sine2 = new SinOsc(this);
  sine3 = new SinOsc(this);
  squeakOsc = new TriOsc(this);
  rustleNoise = new PinkNoise(this);
  
  // ジャイロ用サウンドの初期化
  chirp1 = new SinOsc(this);
  chirp2 = new SinOsc(this);
  bellOsc = new TriOsc(this);
  dogBark1 = new SawOsc(this);
  dogBark2 = new SawOsc(this);
  
  // エフェクトの初期化
  envelope = new Env(this);
  squeakEnv = new Env(this);
  chirpEnv = new Env(this);
  barkEnv = new Env(this);
  bandPass = new BandPass(this);
  dogFilter = new LowPass(this);
  
  // ノイズ設定
  rustleNoise.play();
  bandPass.process(rustleNoise);
  bandPass.freq(3000);
  bandPass.bw(1000);
  rustleNoise.amp(0);
  
  // 犬の鳴き声フィルター
  dogFilter.process(dogBark1);
  dogFilter.freq(1000);
  
  // すべての音源を初期化
  sine1.amp(0); sine1.play();
  sine2.amp(0); sine2.play();
  sine3.amp(0); sine3.play();
  squeakOsc.amp(0); squeakOsc.play();
  chirp1.amp(0); chirp1.play();
  chirp2.amp(0); chirp2.play();
  bellOsc.amp(0); bellOsc.play();
  dogBark1.amp(0); dogBark1.play();
  dogBark2.amp(0); dogBark2.play();
}

void draw() {
  background(50);
  fill(255);

  text("🐕 Dog Toy Ball Sound 🎾", 20, 30);

  // 加速度表示
  fill(255, 200, 100);
  text("Acceleration (Throw sounds):", 20, 70);
  fill(255);
  text("X:" + nf(acc[0],1,2) + " Y:" + nf(acc[1],1,2) + " Z:" + nf(acc[2],1,2), 20, 90);
  text("Magnitude: " + nf(accelMagnitude, 1, 2), 20, 110);

  // ジャイロ表示
  fill(100, 200, 255);
  text("Gyroscope (Various sounds):", 20, 150);
  fill(255);
  text("X:" + nf(gyro[0],1,2) + " Y:" + nf(gyro[1],1,2) + " Z:" + nf(gyro[2],1,2), 20, 170);
  text("Magnitude: " + nf(gyroMagnitude, 1, 2) + " deg/s", 20, 190);
  
  // 前フレームの加速度を保存
  prevAccelMag = accelMagnitude;
  
  // 加速度とジャイロの大きさを計算
  accelMagnitude = sqrt(acc[0]*acc[0] + acc[1]*acc[1] + acc[2]*acc[2]);
  gyroMagnitude = sqrt(gyro[0]*gyro[0] + gyro[1]*gyro[1] + gyro[2]*gyro[2]);
  
  // 急な動きを検出
  float accelChange = abs(accelMagnitude - prevAccelMag);
  
  // === 加速度による音の制御（前のバージョンの音）===
  if (accelMagnitude > soundThreshold && !isThrown) {
    isThrown = true;
    throwTimer = millis();
    playDogExcitingSound(accelMagnitude);
  }
  
  if (accelChange > 1.5 && !isSqueaking) {
    isSqueaking = true;
    squeakTimer = millis();
    playSqueak();
  }
  
  // === ジャイロによる音の制御（1秒に1回チェック）===
  if (gyroMagnitude > gyroThreshold && !isPlayingGyroSound && 
      millis() - lastGyroSoundTime > 1000) {
    isPlayingGyroSound = true;
    gyroSoundTimer = millis();
    lastGyroSoundTime = millis();
    
    // ランダムに音を選択
    currentGyroSound = int(random(4));
    playGyroSound(currentGyroSound);
  }
  
  // 投球音の処理
  if (isThrown) {
    updateThrowSound();
  }
  
  // キュッキュッ音の処理
  if (isSqueaking) {
    float elapsed = millis() - squeakTimer;
    if (elapsed > 300) {
      isSqueaking = false;
      squeakOsc.amp(0);
    }
  }
  
  // ジャイロ音の処理
  if (isPlayingGyroSound) {
    updateGyroSound();
  }
  
  // 状態表示
  drawStatus();
}

void updateThrowSound() {
  float elapsed = millis() - throwTimer;
  
  // ウォブル効果
  float wobble = sin(elapsed * 0.02) * 200;
  
  sine1.freq(2000 + wobble);
  sine2.freq(2500 - wobble);
  sine3.freq(3000 + wobble * 0.5);
  
  // カサカサ音
  float rustleAmp = map(accelMagnitude, 0, 15, 0, 0.2);
  rustleNoise.amp(rustleAmp * 0.3);
  
  // 音量の変化
  float amp = map(elapsed, 0, 800, 0.3, 0);
  amp = constrain(amp, 0, 0.3);
  
  sine1.amp(amp * 0.4);
  sine2.amp(amp * 0.3);
  sine3.amp(amp * 0.2);
  
  if (elapsed > 800) {
    isThrown = false;
    sine1.amp(0);
    sine2.amp(0);
    sine3.amp(0);
    rustleNoise.amp(0);
  }
}

void updateGyroSound() {
  float elapsed = millis() - gyroSoundTimer;
  
  switch(currentGyroSound) {
    case 0: // ぴよぴよ音
      updateChirpSound(elapsed);
      break;
    case 1: // ベル音
      updateBellSound(elapsed);
      break;
    case 2: // 犬の鳴き声
      updateDogBarkSound(elapsed);
      break;
    case 3: // ランダムな効果音
      updateRandomSound(elapsed);
      break;
  }
  
  if (elapsed > 1500) {
    stopAllGyroSounds();
    isPlayingGyroSound = false;
  }
}

void updateChirpSound(float elapsed) {
  float chirpPattern = sin(elapsed * 0.01) * 0.5 + 0.5;
  float freq1 = 2500 + chirpPattern * 1000;
  float freq2 = 3000 + chirpPattern * 800;
  
  chirp1.freq(freq1);
  chirp2.freq(freq2);
  chirp1.amp(chirpPattern * 0.2);
  chirp2.amp(chirpPattern * 0.15);
}

void updateBellSound(float elapsed) {
  float bellFreq = 1000 + sin(elapsed * 0.005) * 100;
  bellOsc.freq(bellFreq);
  float amp = map(elapsed, 0, 1000, 0.25, 0);
  bellOsc.amp(constrain(amp, 0, 0.25));
}

void updateDogBarkSound(float elapsed) {
  // 犬の鳴き声パターン
  if (elapsed < 200) {
    dogBark1.freq(200 + random(-20, 20));
    dogBark2.freq(400 + random(-40, 40));
    dogFilter.freq(800 + random(-100, 100));
    dogBark1.amp(0.3);
    dogBark2.amp(0.2);
  } else if (elapsed < 300) {
    dogBark1.amp(0);
    dogBark2.amp(0);
  } else if (elapsed < 500) {
    dogBark1.freq(180 + random(-20, 20));
    dogBark2.freq(360 + random(-40, 40));
    dogFilter.freq(900 + random(-100, 100));
    dogBark1.amp(0.35);
    dogBark2.amp(0.25);
  } else {
    float fadeOut = map(elapsed, 500, 700, 0.3, 0);
    dogBark1.amp(constrain(fadeOut, 0, 0.3));
    dogBark2.amp(constrain(fadeOut * 0.7, 0, 0.2));
  }
}

void updateRandomSound(float elapsed) {
  // ランダムな楽しい音
  float freq = 1500 + sin(elapsed * 0.02) * 500 + random(-100, 100);
  sine2.freq(freq);
  sine2.amp(0.15);
}

void playDogExcitingSound(float magnitude) {
  float attackTime = 0.01;
  float sustainTime = 0.05;
  float releaseTime = 0.5;
  
  sine1.freq(2000);
  sine2.freq(2500);
  sine3.freq(3000);
  
  envelope.play(sine1, attackTime, sustainTime, 0.4, releaseTime);
}

void playSqueak() {
  float freq = random(1800, 3500);
  squeakOsc.freq(freq);
  squeakEnv.play(squeakOsc, 0.01, 0.05, 0.5, 0.2);
}

void playGyroSound(int type) {
  // 音の種類に応じて初期設定
  switch(type) {
    case 2: // 犬の鳴き声の場合は特別な処理
      println("Playing dog bark!");
      break;
  }
}

void stopAllGyroSounds() {
  chirp1.amp(0);
  chirp2.amp(0);
  bellOsc.amp(0);
  dogBark1.amp(0);
  dogBark2.amp(0);
}

void drawStatus() {
  textSize(20);
  
  float y = 250;
  if (isThrown) {
    fill(255, 200, 50);
    text("🎾 Wheee!", 20, y);
  } else if (isSqueaking) {
    fill(255, 100, 100);
    text("🦴 Squeak!", 20, y);
  }
  
  y = 280;
  if (isPlayingGyroSound) {
    switch(currentGyroSound) {
      case 0:
        fill(100, 200, 255);
        text("🐦 Chirp chirp!", 20, y);
        break;
      case 1:
        fill(255, 255, 100);
        text("🔔 Ding ding!", 20, y);
        break;
      case 2:
        fill(255, 100, 100);
        text("🐕 Woof woof!", 20, y);
        break;
      case 3:
        fill(200, 100, 255);
        text("✨ Boing!", 20, y);
        break;
    }
  }
  
  // 音の種類説明
  textSize(14);
  fill(200);
  text("Throw: Squeak + Exciting sounds", 20, 350);
  text("Rotate: Random from 4 different sounds", 20, 370);
  text("- Bird chirps, Bell, Dog bark, Random", 20, 390);
  text("Next sound in: " + nf((1000 - (millis() - lastGyroSoundTime))/1000.0, 0, 1) + "s", 20, 420);
}

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/imu/accel")) {
    if (msg.checkTypetag("fff")) {
      acc[0] = msg.get(0).floatValue();
      acc[1] = msg.get(1).floatValue();
      acc[2] = msg.get(2).floatValue();
    }
  }
  else if (msg.checkAddrPattern("/imu/gyro")) {
    if (msg.checkTypetag("fff")) {
      gyro[0] = msg.get(0).floatValue();
      gyro[1] = msg.get(1).floatValue();
      gyro[2] = msg.get(2).floatValue();
    }
  }
}

void exit() {
  sine1.stop(); sine2.stop(); sine3.stop();
  squeakOsc.stop(); rustleNoise.stop();
  chirp1.stop(); chirp2.stop();
  bellOsc.stop();
  dogBark1.stop(); dogBark2.stop();
  super.exit();
}
