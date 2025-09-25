import oscP5.*;
import netP5.*;
import processing.serial.*;
import ddf.minim.*;

OscP5 oscP5;
Minim minim;
AudioSample runStepSample;
AudioSample shakeHitSample;
AudioPlayer runningLoop;
AudioPlayer idleLoop;
AudioPlayer shakeLoop;
boolean audioReady = false;
String audioStatusMessage = "";

// シリアル入力
Serial m5Serial;
boolean useSerialInput = true;       // USB直結でテストする場合は true
boolean serialReady = false;
boolean serialHasPacket = false;
float lastSerialDataMillis = 0;
String serialStatusMessage = "";
int serialPortIndex = 0;             // Serial.list() の何番目を使うか（自動検出が外れたら変更）
String serialPortKeyword = "";      // ポート名に含まれるキーワード（例: "usb"、"COM"）。空なら index を優先

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

float lastShakeHitTime = 0;


void setup() {
  size(400, 450);
  oscP5 = new OscP5(this, 8000);
  textSize(16);

  if (useSerialInput) {
    initSerialInput();
  } else {
    serialStatusMessage = "Serial disabled";
  }

  minim = new Minim(this);
  loadAudioAssets();
}

void loadAudioAssets() {
  int availableCount = 0;
  String missingList = "";

  runStepSample = loadSampleSafe("run_step.wav");
  if (runStepSample != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "run_step.wav");
  }

  shakeHitSample = loadSampleSafe("shake_hit.wav");
  if (shakeHitSample != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "shake_hit.wav");
  }

  runningLoop = loadLoopSafe("running_loop.wav");
  if (runningLoop != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "running_loop.wav");
  }

  idleLoop = loadLoopSafe("idle_pad.wav");
  if (idleLoop != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "idle_pad.wav");
  }

  shakeLoop = loadLoopSafe("shake_loop.wav");
  if (shakeLoop != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "shake_loop.wav");
  }

  audioReady = availableCount > 0;
  if (!audioReady) {
    audioStatusMessage = "Audio files not found";
  } else if (missingList.length() == 0) {
    audioStatusMessage = "Audio ready (5/5)";
  } else {
    audioStatusMessage = "Loaded " + availableCount + "/5, missing: " + missingList;
  }
}

String appendMissing(String current, String name) {
  if (current == null || current.length() == 0) {
    return name;
  }
  return current + ", " + name;
}

AudioSample loadSampleSafe(String fileName) {
  try {
    AudioSample sample = minim.loadSample(fileName, 1024);
    if (sample == null) {
      println("Audio sample missing -> " + fileName);
    }
    return sample;
  } catch (Exception e) {
    println("Failed to load sample " + fileName);
    e.printStackTrace();
    return null;
  }
}

AudioPlayer loadLoopSafe(String fileName) {
  try {
    AudioPlayer player = minim.loadFile(fileName, 2048);
    if (player == null) {
      println("Audio loop missing -> " + fileName);
      return null;
    }
    player.loop();
    player.setGain(-80);
    return player;
  } catch (Exception e) {
    println("Failed to load loop " + fileName);
    e.printStackTrace();
    return null;
  }
}

void closeSample(AudioSample sample) {
  if (sample != null) {
    sample.close();
  }
}

void closePlayer(AudioPlayer player) {
  if (player != null) {
    player.close();
  }
}

void initSerialInput() {
  String[] ports = Serial.list();
  println("=== Serial ports ===");
  if (ports.length == 0) {
    println("(none)");
    serialReady = false;
    serialHasPacket = false;
    serialStatusMessage = "Serial: no ports found";
    return;
  }

  for (int i = 0; i < ports.length; i++) {
    println(i + ": " + ports[i]);
  }

  int resolvedIndex = resolveSerialPortIndex(ports);
  resolvedIndex = constrain(resolvedIndex, 0, ports.length - 1);

  try {
    m5Serial = new Serial(this, ports[resolvedIndex], 115200);
    m5Serial.clear();
    m5Serial.bufferUntil('\n');
    serialReady = true;
    serialHasPacket = false;
    serialStatusMessage = "Serial: " + ports[resolvedIndex];
    println("Opening serial port -> " + ports[resolvedIndex]);
  } catch (Exception e) {
    e.printStackTrace();
    serialReady = false;
    serialHasPacket = false;
    serialStatusMessage = "Serial open failed";
  }
}

int resolveSerialPortIndex(String[] ports) {
  if (serialPortKeyword != null && serialPortKeyword.length() > 0) {
    String keyword = serialPortKeyword.toLowerCase();
    for (int i = 0; i < ports.length; i++) {
      if (ports[i].toLowerCase().indexOf(keyword) >= 0) {
        return i;
      }
    }
  }

  int preferredByUsb = findPreferredUsbPort(ports);
  if (preferredByUsb >= 0) {
    return preferredByUsb;
  }

  int preferredByCom = findHighestComPort(ports);
  if (preferredByCom >= 0) {
    return preferredByCom;
  }

  if (serialPortIndex >= 0 && serialPortIndex < ports.length) {
    return serialPortIndex;
  }

  return constrain(serialPortIndex, 0, ports.length - 1);
}

int findPreferredUsbPort(String[] ports) {
  String[] usbKeywords = {
    "usbmodem",
    "usbserial",
    "tty.usb",
    "ttyusb",
    "ttyacm",
    "wchusb",
    "silabs"
  };

  for (String keyword : usbKeywords) {
    for (int i = 0; i < ports.length; i++) {
      if (ports[i].toLowerCase().indexOf(keyword) >= 0) {
        return i;
      }
    }
  }
  return -1;
}

int findHighestComPort(String[] ports) {
  int bestIndex = -1;
  int bestNumber = -1;

  for (int i = 0; i < ports.length; i++) {
    String port = ports[i].toLowerCase();
    if (!port.startsWith("com")) {
      continue;
    }

    String digits = port.replaceAll("[^0-9]", "");
    if (digits.length() == 0) {
      continue;
    }

    int value;
    try {
      value = Integer.parseInt(digits);
    } catch (NumberFormatException e) {
      continue;
    }

    if (value > bestNumber) {
      bestNumber = value;
      bestIndex = i;
    }
  }

  return bestIndex;
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
    shakeBellAmp = max(shakeBellAmp, 0.9);
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
  float targetBed = (motionState == STATE_RUNNING) ? constrain(0.45 + runEnergy * 0.6, 0.45, 1.2) : 0;
  runningBedAmp = lerp(runningBedAmp, targetBed, 0.15);
  setLoopGain(runningLoop, runningBedAmp);

  if (motionState == STATE_RUNNING) {
    float highThreshold = 0.55;
    float resetThreshold = 0.25;
    float intensity = constrain(map(abs(accelHPInstant), 0.35, 1.8, 0.6, 1.6), 0.6, 1.6);

    if (accelHPInstant > highThreshold && stepArmed && millis() - lastStepTime > 120) {
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
  float amp = constrain(0.35 + (intensity - 0.6) * 0.5, 0.2, 1.3);
  triggerSample(runStepSample, amp);
}

void updateShakeSound() {
  float targetBell = (motionState == STATE_SHAKE) ? constrain(map(shakeEnergy, 40, 220, 0.5, 1.3), 0.4, 1.4) : 0;
  shakeBellAmp = lerp(shakeBellAmp, targetBell, 0.18);
  setLoopGain(shakeLoop, shakeBellAmp);

  if (motionState == STATE_SHAKE) {
    if (gyroHPInstant > 80 && millis() - lastShakeHitTime > 160) {
      float hitAmp = constrain(map(gyroHPInstant, 80, 200, 0.35, 1.2), 0.3, 1.3);
      triggerSample(shakeHitSample, hitAmp);
      lastShakeHitTime = millis();
    }
  }
}

void updateIdleSound() {
  float targetAmp = 0;
  if (motionState == STATE_STILL) {
    targetAmp = 0.6;
  } else if (motionState == STATE_IDLE) {
    targetAmp = 0.35;
  }

  idlePadAmp = lerp(idlePadAmp, targetAmp, 0.05);
  setLoopGain(idleLoop, idlePadAmp);
}

void triggerSample(AudioSample sample, float amp) {
  if (sample == null) {
    return;
  }

  float scaled = constrain(amp, 0.1, 1.0);
  sample.trigger(scaled);
}

void setLoopGain(AudioPlayer player, float amp) {
  if (player == null) {
    return;
  }

  float gainDb = ampToGainDb(amp);
  player.setGain(gainDb);
}

float ampToGainDb(float amp) {
  if (amp <= 0.0001) {
    return -80;
  }
  float mapped = map(constrain(amp, 0, 1.4), 0, 1.4, -60, -4);
  return constrain(mapped, -80, 6);
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

  fill(200);
  String serialLine = "";
  if (!useSerialInput) {
    serialLine = "Serial: disabled";
  } else if (!serialReady) {
    serialLine = "Serial: waiting for device";
  } else if (!serialHasPacket) {
    serialLine = "Serial: waiting for data";
  } else {
    serialLine = "Serial: OK (" + nf((millis() - lastSerialDataMillis)/1000.0, 1, 2) + "s ago)";
  }
  if (serialStatusMessage != null && serialStatusMessage.length() > 0) {
    text(serialStatusMessage, 20, 320);
    text(serialLine, 20, 340);
  } else {
    text(serialLine, 20, 320);
  }

  fill(190);
  if (audioStatusMessage != null && audioStatusMessage.length() > 0) {
    text("Audio: " + audioStatusMessage, 20, 360);
  }

  fill(180);
  text("Running: step thumps + low layer", 20, 380);
  text("Shake: layered rattles", 20, 400);
  text("Stop: ambient tail", 20, 420);
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

void serialEvent(Serial which) {
  if (!useSerialInput) {
    return;
  }
  if (which != m5Serial) {
    return;
  }

  String line = which.readStringUntil('\n');
  if (line == null) {
    return;
  }
  parseSerialLine(line);
}

void parseSerialLine(String raw) {
  raw = trim(raw);
  if (raw.length() == 0) {
    return;
  }

  if (!raw.startsWith("IMU")) {
    return;
  }

  String[] parts = split(raw, ',');
  if (parts.length < 7) {
    return;
  }

  float ax = parseFloat(parts[1]);
  float ay = parseFloat(parts[2]);
  float az = parseFloat(parts[3]);
  float gx = parseFloat(parts[4]);
  float gy = parseFloat(parts[5]);
  float gz = parseFloat(parts[6]);

  if (Float.isNaN(ax) || Float.isNaN(ay) || Float.isNaN(az) ||
      Float.isNaN(gx) || Float.isNaN(gy) || Float.isNaN(gz)) {
    return;
  }

  acc[0] = ax;
  acc[1] = ay;
  acc[2] = az;
  gyro[0] = gx;
  gyro[1] = gy;
  gyro[2] = gz;

  serialReady = true;
  serialHasPacket = true;
  lastSerialDataMillis = millis();
}

void exit() {
  closeSample(runStepSample);
  closeSample(shakeHitSample);
  closePlayer(runningLoop);
  closePlayer(idleLoop);
  closePlayer(shakeLoop);
  if (minim != null) {
    minim.stop();
  }
  super.exit();
}
