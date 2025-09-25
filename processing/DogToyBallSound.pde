import oscP5.*;
import netP5.*;
import processing.sound.*;

OscP5 oscP5;
// 基本音源
SinOsc sine1, sine2, sine3;
TriOsc bellOsc;
SinOsc chirp2;
PinkNoise rustleNoise;
BandPass runNoiseFilter;

// エンベロープ
Env runNoiseEnv, runToneEnv;

float[] acc = new float[3];   // 加速度 [x, y, z]
float[] gyro = new float[3];  // ジャイロ [x, y, z]

float accelMagnitude = 0;     // 加速度の大きさ
float gyroMagnitude = 0;      // ジャイロの大きさ
float accelWithoutGravity = 0;

// 状態管理
final int STATE_IDLE = 0;
final int STATE_RUNNING = 1;
final int STATE_SHAKE = 2;
final int STATE_STILL = 3;

int motionState = STATE_IDLE;
int previousState = STATE_IDLE;

// フィルタ値とスコア
float accelMean = 0;
float accelHP = 0;
float accelHPInstant = 0;
float gyroMean = 0;
float gyroHP = 0;
float gyroHPInstant = 0;
float runEnergy = 0;
float shakeEnergy = 0;

// ステップ検出
boolean stepArmed = true;
float lastStepTime = 0;

// 静止判定
float stillCandidateSince = 0;

// 音量スムージング
float runningBedAmp = 0;
float shakeBellAmp = 0;
float idlePadAmp = 0;
float shakeChirpAmp = 0;


void setup() {
  size(400, 450);
  oscP5 = new OscP5(this, 8000);
  textSize(16);

  sine1 = new SinOsc(this);
  sine2 = new SinOsc(this);
  sine3 = new SinOsc(this);
  bellOsc = new TriOsc(this);
  chirp2 = new SinOsc(this);
  rustleNoise = new PinkNoise(this);

  runNoiseFilter = new BandPass(this);
  runNoiseFilter.process(rustleNoise);
  runNoiseFilter.freq(2500);
  runNoiseFilter.bw(1400);

  runNoiseEnv = new Env(this);
  runToneEnv = new Env(this);

  rustleNoise.play();
  rustleNoise.amp(0);

  sine1.amp(0); sine1.play();
  sine2.amp(0); sine2.play();
  sine3.amp(0); sine3.play();
  bellOsc.amp(0); bellOsc.play();
  chirp2.amp(0); chirp2.play();
}

void draw() {
  background(50);
  fill(255);

  text("🐕 Motion Reactive Soundboard", 20, 30);

  accelMagnitude = sqrt(acc[0]*acc[0] + acc[1]*acc[1] + acc[2]*acc[2]);
  gyroMagnitude = sqrt(gyro[0]*gyro[0] + gyro[1]*gyro[1] + gyro[2]*gyro[2]);

  updateMotionEstimates();
  updateStateAudio();
  drawStatus();
}

void updateMotionEstimates() {
  accelWithoutGravity = max(0, accelMagnitude - 1.0);
  float accelAlpha = 0.18;
  accelMean = lerp(accelMean, accelWithoutGravity, accelAlpha);
  accelHPInstant = accelWithoutGravity - accelMean;
  float accelPulse = abs(accelHPInstant);
  accelHP = lerp(accelHP, accelPulse, 0.25);

  float gyroAlpha = 0.12;
  gyroMean = lerp(gyroMean, gyroMagnitude, gyroAlpha);
  gyroHPInstant = gyroMagnitude - gyroMean;
  float gyroPulse = abs(gyroHPInstant);
  gyroHP = lerp(gyroHP, gyroPulse, 0.3);

  runEnergy = lerp(runEnergy, accelPulse, 0.15);
  shakeEnergy = lerp(shakeEnergy, gyroPulse, 0.2);

  if (gyroMagnitude < 25 && accelWithoutGravity < 0.2) {
    if (stillCandidateSince == 0) {
      stillCandidateSince = millis();
    }
  } else {
    stillCandidateSince = 0;
  }

  evaluateMotionState(accelPulse, gyroMagnitude, gyroPulse);
}

void evaluateMotionState(float accelPulse, float gyroMag, float gyroPulse) {
  int newState = motionState;

  boolean shakeDetected = (gyroMag > 180 && gyroPulse > 90) || gyroPulse > 140;
  if (shakeDetected) {
    newState = STATE_SHAKE;
  } else if (accelPulse > 0.45 && gyroMag > 35) {
    newState = STATE_RUNNING;
  } else if (stillCandidateSince > 0 && millis() - stillCandidateSince > 1200) {
    newState = STATE_STILL;
  } else {
    newState = STATE_IDLE;
  }

  if (newState != motionState) {
    previousState = motionState;
    motionState = newState;
    onMotionStateChange(motionState, previousState);
  }
}

void onMotionStateChange(int newState, int oldState) {
  if (newState != STATE_RUNNING) {
    stepArmed = true;
  }

  if (newState == STATE_SHAKE) {
    // シェイク音はすぐに立ち上げる
    shakeBellAmp = max(shakeBellAmp, 0.12);
    shakeChirpAmp = max(shakeChirpAmp, 0.08);
  }

  if (newState == STATE_STILL) {
    idlePadAmp = max(idlePadAmp, 0.1);
  }
}

void updateStateAudio() {
  updateRunningSound();
  updateShakeSound();
  updateIdleSound();
}

void updateRunningSound() {
  float targetBed = (motionState == STATE_RUNNING) ? constrain(0.12 + runEnergy * 0.08, 0.12, 0.24) : 0;
  runningBedAmp = lerp(runningBedAmp, targetBed, 0.1);

  float shimmerFreq = 420 + min(gyroMagnitude, 260) * 1.5;
  sine3.freq(shimmerFreq + sin(millis() * 0.01) * 20);
  sine3.amp(runningBedAmp);

  if (motionState == STATE_RUNNING) {
    float highThreshold = 0.7;
    float resetThreshold = 0.3;
    float intensity = constrain(map(abs(accelHPInstant), 0.4, 2.0, 0.6, 1.4), 0.6, 1.4);

    if (accelHPInstant > highThreshold && stepArmed && millis() - lastStepTime > 110) {
      triggerRunStep(intensity);
      stepArmed = false;
      lastStepTime = millis();
    }

    if (abs(accelHPInstant) < resetThreshold) {
      stepArmed = true;
    }
  }
}

void triggerRunStep(float intensity) {
  float noiseLevel = constrain(0.08 * intensity, 0.06, 0.22);
  runNoiseEnv.play(rustleNoise, 0.004, 0.05, noiseLevel, 0.12);

  float toneFreq = constrain(900 + (intensity - 0.6) * 400 + random(-40, 40), 650, 1500);
  sine2.freq(toneFreq);
  float toneLevel = constrain(0.1 * intensity, 0.05, 0.2);
  runToneEnv.play(sine2, 0.008, 0.04, toneLevel, 0.09);
}

void updateShakeSound() {
  float targetBell = (motionState == STATE_SHAKE) ? constrain(map(shakeEnergy, 60, 180, 0.14, 0.3), 0.14, 0.3) : 0;
  float targetChirp = (motionState == STATE_SHAKE) ? constrain(map(shakeEnergy, 60, 180, 0.08, 0.18), 0.08, 0.18) : 0;

  shakeBellAmp = lerp(shakeBellAmp, targetBell, 0.12);
  shakeChirpAmp = lerp(shakeChirpAmp, targetChirp, 0.12);

  float baseFreq = constrain(map(gyroMagnitude, 100, 320, 900, 1700), 900, 1700);
  float wobble = sin(millis() * 0.04) * 120;
  bellOsc.freq(baseFreq + wobble);
  bellOsc.amp(shakeBellAmp);

  chirp2.freq((baseFreq * 1.25) + wobble * 0.5);
  chirp2.amp(shakeChirpAmp);
}

void updateIdleSound() {
  float targetAmp = 0;
  if (motionState == STATE_STILL) {
    targetAmp = 0.14;
  } else if (motionState == STATE_IDLE) {
    targetAmp = 0.05;
  }

  idlePadAmp = lerp(idlePadAmp, targetAmp, 0.05);
  float padFreq = 180 + sin(millis() * 0.002) * 12 + runEnergy * 20;
  sine1.freq(padFreq);
  sine1.amp(idlePadAmp);
}

void drawStatus() {
  fill(255, 200, 100);
  text("Acceleration:", 20, 70);
  fill(255);
  text("X:" + nf(acc[0],1,2) + " Y:" + nf(acc[1],1,2) + " Z:" + nf(acc[2],1,2), 20, 90);
  text("|a|:" + nf(accelMagnitude, 1, 2) + "  |a|-g:" + nf(accelWithoutGravity, 1, 2), 20, 110);

  fill(100, 200, 255);
  text("Gyroscope:", 20, 150);
  fill(255);
  text("X:" + nf(gyro[0],1,2) + " Y:" + nf(gyro[1],1,2) + " Z:" + nf(gyro[2],1,2), 20, 170);
  text("|ω|:" + nf(gyroMagnitude, 1, 2) + " deg/s", 20, 190);

  fill(220);
  text("State: " + stateName(motionState), 20, 230);
  text("Run energy:" + nf(runEnergy,1,2) + "  Shake energy:" + nf(shakeEnergy,1,2), 20, 250);
  text("HP accel:" + nf(accelHP,1,2) + "  HP gyro:" + nf(gyroHP,1,2), 20, 270);

  if (stillCandidateSince > 0 && motionState != STATE_STILL) {
    float countdown = max(0, 1.2 - (millis() - stillCandidateSince) / 1000.0);
    fill(200, 220, 255);
    text("Still latch in " + nf(countdown, 1, 2) + " s", 20, 300);
  }

  fill(180);
  text("Running: paw taps + collar shimmer", 20, 350);
  text("Shake: collar jingle bursts", 20, 370);
  text("Stop: calm pad with gentle wobble", 20, 390);
}

String stateName(int state) {
  switch(state) {
    case STATE_RUNNING:
      return "RUNNING";
    case STATE_SHAKE:
      return "SHAKE";
    case STATE_STILL:
      return "STILL";
    default:
      return "IDLE";
  }
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
  sine1.stop();
  sine2.stop();
  sine3.stop();
  bellOsc.stop();
  chirp2.stop();
  rustleNoise.stop();
  super.exit();
}
