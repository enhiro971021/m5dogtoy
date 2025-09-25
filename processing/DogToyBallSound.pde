import oscP5.*;
import netP5.*;
import processing.serial.*;
import ddf.minim.*;

OscP5 oscP5;
Minim minim;

// Audio assets
AudioPlayer collarRunLoop;
AudioPlayer ballRollingLoop;
AudioSample collarBigMotionSample;
AudioSample collarRelativeBurstSample;
AudioSample ballStopSample;
AudioSample ballCollisionSample;

boolean audioReady = false;
String audioStatusMessage = "";

// Serial input
Serial m5Serial;
boolean useSerialInput = true;
boolean serialReady = false;
boolean serialHasPacket = false;
float lastSerialDataMillis = 0;
String serialStatusMessage = "";
int serialPortIndex = 0;
String serialPortKeyword = "";

// Sensor values
float[] acc = new float[3];
float[] gyro = new float[3];
float accelMagnitude = 0;
float gyroMagnitude = 0;
float accelWithoutGravity = 0;

// Derived motion metrics
float accelMean = 0;
float accelHP = 0;
float accelHPInstant = 0;
float accelHPPrev = 0;
float gyroMean = 0;
float gyroHP = 0;
float gyroHPInstant = 0;
float runEnergy = 0;
float shakeEnergy = 0;
float collarMotionScore = 0;
float ballMotionScore = 0;
float lastUpdateMillis = 0;

// Mode management
final int MODE_COLLAR = 0;
final int MODE_BALL = 1;
int soundMode = MODE_COLLAR;

// Master controls
float masterVolume = 0.8;
boolean panicMute = false;

// Collar settings
boolean collarRunLoopEnabled = true;
float collarRunThreshold = 0.55;
float collarRunVolume = 0.9;
float collarRunAboveSince = -1;
float collarRunBelowSince = -1;
boolean collarRunActive = false;
float collarRunLoopAmp = 0;
FloatList collarRunPeaks = new FloatList();
float collarRunPeakHoldMs = 2200;
float collarRunPeakCooldownMs = 160;
float lastRunPeakMillis = 0;

boolean collarBigMotionEnabled = true;
float collarBigMotionThreshold = 1.3;
float collarStillStart = -1;
boolean collarStillFlag = false;

boolean collarRelativeEnabled = true;
float collarRelativeMargin = 0.3;
float collarRelativeMean = 0;
float collarRelativeVar = 0;
boolean collarRelativeLatched = false;
float collarRelativeLastValue = 0;

// Ball settings
boolean ballRollingEnabled = true;
float ballRollSensitivity = 0.5; // 0.0 (hard) to 1.0 (soft)
float ballRollAboveSince = -1;
float ballRollBelowSince = -1;
boolean ballRollingActive = false;
float ballRollingLoopAmp = 0;

boolean ballStopEnabled = true;
float ballStopSeconds = 7.0;
float ballStopStart = -1;

boolean ballCollisionEnabled = true;
float ballCollisionThreshold = 1.4;
float lastCollisionMillis = 0;
float collisionCooldownMs = 220;

// UI state
ToggleControl collarRunToggle;
ToggleControl collarBigMotionToggle;
ToggleControl collarRelativeToggle;
ToggleControl ballRollingToggle;
ToggleControl ballStopToggle;
ToggleControl ballCollisionToggle;
ToggleControl panicToggle;

SliderControl masterVolumeSlider;
SliderControl collarRunThresholdSlider;
SliderControl collarRunVolumeSlider;
SliderControl collarBigMotionSlider;
SliderControl collarRelativeMarginSlider;
SliderControl ballRollSensitivitySlider;
SliderControl ballStopSecondsSlider;
SliderControl ballCollisionSlider;

SegmentControl modeSwitch;

PresetButton[] presetButtons;
TestSoundButton[] testButtons;

SliderControl activeSlider = null;

// Connection indicator states (placeholder for now)
final int STATUS_OK = 2;
final int STATUS_RECONNECTING = 1;
final int STATUS_OFF = 0;
int mqttStatus = STATUS_OFF;
int m5Status = STATUS_OFF;
int obnizStatus = STATUS_OFF;

void setup() {
  size(940, 640);
  oscP5 = new OscP5(this, 8000);
  textFont(createFont("Arial", 16));

  if (useSerialInput) {
    initSerialInput();
  } else {
    serialStatusMessage = "Serial disabled";
  }

  minim = new Minim(this);
  loadAudioAssets();
  initUi();
}

void initUi() {
  modeSwitch = new SegmentControl(20, 20, 220, 38, new String[] {"Collar", "Ball"});
  modeSwitch.selectedIndex = soundMode;

  panicToggle = new ToggleControl("Panic Mute", 260, 20, 130, 38);
  panicToggle.value = panicMute;

  masterVolumeSlider = new SliderControl("Master", 410, 24, 180, 0.0, 1.0, masterVolume, 2);

  presetButtons = new PresetButton[] {
    new PresetButton("小型犬", 610, 20, 86, 38),
    new PresetButton("中型犬", 700, 20, 86, 38),
    new PresetButton("大型犬", 790, 20, 86, 38),
    new PresetButton("室内球", 880, 20, 86, 38)
  };

  collarRunToggle = new ToggleControl("走行ループ", 20, 120, 200, 36);
  collarRunToggle.value = collarRunLoopEnabled;
  collarRunThresholdSlider = new SliderControl("走行しきい値", 240, 124, 220, 0.2, 1.8, collarRunThreshold, 2);
  collarRunVolumeSlider = new SliderControl("音量", 480, 124, 200, 0.3, 1.4, collarRunVolume, 2);

  collarBigMotionToggle = new ToggleControl("長静止→大動作", 20, 180, 200, 36);
  collarBigMotionToggle.value = collarBigMotionEnabled;
  collarBigMotionSlider = new SliderControl("大動作しきい値", 240, 184, 220, 0.6, 2.5, collarBigMotionThreshold, 2);

  collarRelativeToggle = new ToggleControl("相対バースト", 20, 240, 200, 36);
  collarRelativeToggle.value = collarRelativeEnabled;
  collarRelativeMarginSlider = new SliderControl("マージン", 240, 244, 220, 0.05, 0.8, collarRelativeMargin, 2);

  ballRollingToggle = new ToggleControl("転がりループ", 20, 360, 200, 36);
  ballRollingToggle.value = ballRollingEnabled;
  ballRollSensitivitySlider = new SliderControl("反応度", 240, 364, 220, 0.05, 1.0, ballRollSensitivity, 2);

  ballStopToggle = new ToggleControl("長停止→一度きり", 20, 420, 200, 36);
  ballStopToggle.value = ballStopEnabled;
  ballStopSecondsSlider = new SliderControl("停止秒数", 240, 424, 220, 4.0, 12.0, ballStopSeconds, 1);

  ballCollisionToggle = new ToggleControl("衝突ワンショット", 20, 480, 200, 36);
  ballCollisionToggle.value = ballCollisionEnabled;
  ballCollisionSlider = new SliderControl("感度", 240, 484, 220, 0.6, 2.4, ballCollisionThreshold, 2);

  testButtons = new TestSoundButton[] {
    new TestSoundButton("Collar run loop", 610, 120, 170, 36, TestSoundButton.TYPE_LOOP, collarRunLoop),
    new TestSoundButton("Collar burst", 610, 170, 170, 36, TestSoundButton.TYPE_SAMPLE, collarRelativeBurstSample),
    new TestSoundButton("Collar big motion", 610, 220, 170, 36, TestSoundButton.TYPE_SAMPLE, collarBigMotionSample),
    new TestSoundButton("Ball rolling loop", 610, 360, 170, 36, TestSoundButton.TYPE_LOOP, ballRollingLoop),
    new TestSoundButton("Ball stop", 610, 410, 170, 36, TestSoundButton.TYPE_SAMPLE, ballStopSample),
    new TestSoundButton("Ball collision", 610, 460, 170, 36, TestSoundButton.TYPE_SAMPLE, ballCollisionSample)
  };
}

void loadAudioAssets() {
  int availableCount = 0;
  String missingList = "";

  collarRunLoop = loadLoopSafe("collar_run_loop.wav");
  if (collarRunLoop != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "collar_run_loop.wav");
  }

  ballRollingLoop = loadLoopSafe("ball_rolling_loop.wav");
  if (ballRollingLoop != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "ball_rolling_loop.wav");
  }

  collarBigMotionSample = loadSampleSafe("collar_big_motion.wav");
  if (collarBigMotionSample != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "collar_big_motion.wav");
  }

  collarRelativeBurstSample = loadSampleSafe("collar_relative_burst.wav");
  if (collarRelativeBurstSample != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "collar_relative_burst.wav");
  }

  ballStopSample = loadSampleSafe("ball_stop_once.wav");
  if (ballStopSample != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "ball_stop_once.wav");
  }

  ballCollisionSample = loadSampleSafe("ball_collision.wav");
  if (ballCollisionSample != null) {
    availableCount++;
  } else {
    missingList = appendMissing(missingList, "ball_collision.wav");
  }

  audioReady = availableCount > 0;
  if (!audioReady) {
    audioStatusMessage = "Audio files not found";
  } else if (missingList.length() == 0) {
    audioStatusMessage = "Audio ready";
  } else {
    audioStatusMessage = "Loaded " + availableCount + ", missing: " + missingList;
  }
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

String appendMissing(String current, String name) {
  if (current == null || current.length() == 0) {
    return name;
  }
  return current + ", " + name;
}

void draw() {
  background(30);

  updateMotionMetrics();
  updateConnectionStatus();
  updateSoundLogic();
  drawUi();

  accelHPPrev = accelHPInstant;
  collarRelativeLastValue = collarMotionScore;
}

void updateMotionMetrics() {
  accelMagnitude = sqrt(acc[0]*acc[0] + acc[1]*acc[1] + acc[2]*acc[2]);
  gyroMagnitude = sqrt(gyro[0]*gyro[0] + gyro[1]*gyro[1] + gyro[2]*gyro[2]);

  accelWithoutGravity = max(0, accelMagnitude - 1.0);
  accelMean = lerp(accelMean, accelWithoutGravity, 0.16);
  accelHPInstant = accelWithoutGravity - accelMean;
  float accelPulse = abs(accelHPInstant);
  accelHP = lerp(accelHP, accelPulse, 0.25);

  gyroMean = lerp(gyroMean, gyroMagnitude, 0.12);
  gyroHPInstant = gyroMagnitude - gyroMean;
  float gyroPulse = abs(gyroHPInstant);
  gyroHP = lerp(gyroHP, gyroPulse, 0.3);

  runEnergy = lerp(runEnergy, accelPulse, 0.2);
  shakeEnergy = lerp(shakeEnergy, gyroPulse, 0.22);

  float composite = max(accelPulse, gyroPulse * 0.7);
  collarMotionScore = lerp(collarMotionScore, composite, 0.28);
  ballMotionScore = lerp(ballMotionScore, max(accelWithoutGravity * 0.7, gyroMagnitude * 0.012), 0.18);

  int nowMs = millis();
  if (lastUpdateMillis == 0) {
    lastUpdateMillis = nowMs;
  }
}

void updateConnectionStatus() {
  if (!useSerialInput) {
    m5Status = STATUS_OFF;
    return;
  }

  if (!serialReady) {
    m5Status = STATUS_OFF;
  } else if (!serialHasPacket || millis() - lastSerialDataMillis > 1500) {
    m5Status = STATUS_RECONNECTING;
  } else {
    m5Status = STATUS_OK;
  }
}

void updateSoundLogic() {
  panicMute = panicToggle.value;
  masterVolume = masterVolumeSlider.value;

  soundMode = modeSwitch.selectedIndex;

  collarRunLoopEnabled = collarRunToggle.value;
  collarBigMotionEnabled = collarBigMotionToggle.value;
  collarRelativeEnabled = collarRelativeToggle.value;
  ballRollingEnabled = ballRollingToggle.value;
  ballStopEnabled = ballStopToggle.value;
  ballCollisionEnabled = ballCollisionToggle.value;

  collarRunThreshold = collarRunThresholdSlider.value;
  collarRunVolume = collarRunVolumeSlider.value;
  collarBigMotionThreshold = collarBigMotionSlider.value;
  collarRelativeMargin = collarRelativeMarginSlider.value;
  ballRollSensitivity = ballRollSensitivitySlider.value;
  ballStopSeconds = ballStopSecondsSlider.value;
  ballCollisionThreshold = ballCollisionSlider.value;

  if (soundMode == MODE_COLLAR) {
    updateCollarRunLoop();
    updateCollarBigMotion();
    updateCollarRelativeBurst();
    fadeLoop(ballRollingLoop, 0);
    ballRollingActive = false;
    ballRollingLoopAmp = 0;
  } else {
    updateBallRollingLoop();
    updateBallStopShot();
    updateBallCollisionShot();
    fadeLoop(collarRunLoop, 0);
    collarRunActive = false;
    collarRunLoopAmp = 0;
  }
}

void updateCollarRunLoop() {
  if (!collarRunLoopEnabled) {
    fadeLoop(collarRunLoop, 0);
    collarRunActive = false;
    collarRunAboveSince = -1;
    collarRunBelowSince = -1;
    return;
  }

  float now = millis();
  boolean above = collarMotionScore > collarRunThreshold;

  updateRunPeaks(now);
  boolean hasRepeating = collarRunPeaks.size() >= 3;

  if (above) {
    if (collarRunAboveSince < 0) {
      collarRunAboveSince = now;
    }
    collarRunBelowSince = -1;
  } else {
    collarRunAboveSince = -1;
    if (collarRunActive) {
      if (collarRunBelowSince < 0) {
        collarRunBelowSince = now;
      }
    } else {
      collarRunBelowSince = -1;
    }
  }

  if (!collarRunActive && above && collarRunAboveSince > 0 && now - collarRunAboveSince > 1000 && hasRepeating) {
    collarRunActive = true;
  }

  if (collarRunActive && collarRunBelowSince > 0 && now - collarRunBelowSince > 1000) {
    collarRunActive = false;
  }

  float targetAmp = 0;
  if (collarRunActive) {
    float dynamic = map(collarMotionScore, collarRunThreshold, collarRunThreshold * 2.2, 0.6, 1.25);
    targetAmp = collarRunVolume * constrain(dynamic, 0.5, 1.3);
  }

  collarRunLoopAmp = lerp(collarRunLoopAmp, targetAmp, 0.12);
  fadeLoop(collarRunLoop, collarRunLoopAmp);
}

void updateRunPeaks(float now) {
  boolean rising = accelHPInstant > collarRunThreshold && accelHPPrev <= collarRunThreshold;
  if (rising && now - lastRunPeakMillis > collarRunPeakCooldownMs) {
    collarRunPeaks.append(now);
    lastRunPeakMillis = now;
  }

  for (int i = collarRunPeaks.size() - 1; i >= 0; i--) {
    if (now - collarRunPeaks.get(i) > collarRunPeakHoldMs) {
      collarRunPeaks.remove(i);
    }
  }
}

void updateCollarBigMotion() {
  float now = millis();
  boolean lowMotion = accelWithoutGravity < 0.18 && gyroMagnitude < 28;

  if (lowMotion) {
    if (collarStillStart < 0) {
      collarStillStart = now;
    }
    if (!collarStillFlag && now - collarStillStart > 10000) {
      collarStillFlag = true;
    }
  } else {
    collarStillStart = -1;
    collarStillFlag = false;
  }

  if (!collarBigMotionEnabled) {
    collarStillFlag = false;
    return;
  }

  boolean rising = accelHPInstant > collarBigMotionThreshold && accelHPPrev <= collarBigMotionThreshold;
  if (collarStillFlag && rising) {
    triggerSample(collarBigMotionSample, map(accelHPInstant, collarBigMotionThreshold, collarBigMotionThreshold * 2.2, 0.6, 1.2));
    collarStillFlag = false;
    collarStillStart = -1;
  }
}

void updateCollarRelativeBurst() {
  if (!collarRelativeEnabled) {
    collarRelativeLatched = false;
    return;
  }

  float sample = collarMotionScore;
  float diff = sample - collarRelativeMean;
  collarRelativeMean = lerp(collarRelativeMean, sample, 0.08);
  collarRelativeVar = lerp(collarRelativeVar, diff * diff, 0.08);
  float std = sqrt(max(0.0001, collarRelativeVar));

  float dynamicThreshold = collarRelativeMean + collarRelativeMargin + std;
  boolean rising = sample > dynamicThreshold && collarRelativeLastValue <= dynamicThreshold;

  if (!collarRelativeLatched && rising) {
    triggerSample(collarRelativeBurstSample, constrain(map(diff, collarRelativeMargin, collarRelativeMargin + std * 2.0, 0.4, 1.1), 0.3, 1.2));
    collarRelativeLatched = true;
  }

  if (sample < collarRelativeMean + max(0.05, collarRelativeMargin * 0.5)) {
    collarRelativeLatched = false;
  }
}

void updateBallRollingLoop() {
  if (!ballRollingEnabled) {
    fadeLoop(ballRollingLoop, 0);
    ballRollingActive = false;
    ballRollAboveSince = -1;
    ballRollBelowSince = -1;
    return;
  }

  float enterThreshold = map(ballRollSensitivity, 0.05, 1.0, 150, 35);
  float exitThreshold = enterThreshold * 0.7;

  float now = millis();
  boolean above = gyroMagnitude > enterThreshold;

  if (above) {
    if (ballRollAboveSince < 0) {
      ballRollAboveSince = now;
    }
    ballRollBelowSince = -1;
  } else {
    ballRollAboveSince = -1;
    if (ballRollingActive) {
      if (gyroMagnitude < exitThreshold) {
        if (ballRollBelowSince < 0) {
          ballRollBelowSince = now;
        }
      } else {
        ballRollBelowSince = -1;
      }
    }
  }

  if (!ballRollingActive && above && ballRollAboveSince > 0 && now - ballRollAboveSince > 500) {
    ballRollingActive = true;
  }

  if (ballRollingActive && ballRollBelowSince > 0 && now - ballRollBelowSince > 800) {
    ballRollingActive = false;
  }

  float targetAmp = 0;
  if (ballRollingActive) {
    float intensity = map(gyroMagnitude, exitThreshold, enterThreshold * 1.7, 0.4, 1.3);
    targetAmp = constrain(intensity, 0.3, 1.3);
  }

  ballRollingLoopAmp = lerp(ballRollingLoopAmp, targetAmp, 0.14);
  fadeLoop(ballRollingLoop, ballRollingLoopAmp);
}

void updateBallStopShot() {
  if (!ballStopEnabled) {
    ballStopStart = -1;
    return;
  }

  float now = millis();
  boolean still = accelWithoutGravity < 0.12 && abs(gyroMagnitude) < 22;

  if (still) {
    if (ballStopStart < 0) {
      ballStopStart = now;
    }
    if (now - ballStopStart > ballStopSeconds * 1000.0) {
      triggerSample(ballStopSample, 0.9);
      ballStopStart = now; // immediate reset per spec
    }
  } else {
    ballStopStart = -1;
  }
}

void updateBallCollisionShot() {
  if (!ballCollisionEnabled) {
    return;
  }

  float now = millis();
  boolean rising = accelHPInstant > ballCollisionThreshold && accelHPPrev <= ballCollisionThreshold;
  if (rising && now - lastCollisionMillis > collisionCooldownMs) {
    float amp = constrain(map(accelHPInstant, ballCollisionThreshold, ballCollisionThreshold * 2.5, 0.4, 1.2), 0.35, 1.3);
    triggerSample(ballCollisionSample, amp);
    lastCollisionMillis = now;
  }
}

void fadeLoop(AudioPlayer player, float amp) {
  if (player == null) {
    return;
  }
  float scaled = applyMaster(amp);
  float gainDb = ampToGainDb(scaled);
  player.setGain(gainDb);
}

float applyMaster(float amp) {
  if (panicMute) {
    return 0;
  }
  return constrain(amp * masterVolume, 0, 1.5);
}

void triggerSample(AudioSample sample, float amp) {
  if (sample == null) {
    return;
  }
  float scaled = applyMaster(amp);
  sample.setGain(ampToGainDb(scaled));
  sample.trigger();
}

float ampToGainDb(float amp) {
  if (amp <= 0.0001) {
    return -80;
  }
  float mapped = map(constrain(amp, 0, 1.4), 0, 1.4, -60, -4);
  return constrain(mapped, -80, 6);
}

void drawUi() {
  drawModeSection();
  drawConnectionIndicators();
  drawPresetSection();
  drawCollarSection();
  drawBallSection();
  drawSensorDebug();
  drawAudioStatus();
}

void drawModeSection() {
  modeSwitch.draw();
  panicToggle.draw();
  masterVolumeSlider.draw();
}

void drawConnectionIndicators() {
  int y = 80;
  drawConnectionLights(20, y, "MQTT", mqttStatus);
  drawConnectionLights(120, y, "M5", m5Status);
  drawConnectionLights(200, y, "obniz", obnizStatus);
}

void drawConnectionLights(float x, float y, String label, int status) {
  fill(connectionColor(status));
  stroke(0);
  ellipseMode(CENTER);
  ellipse(x, y, 18, 18);
  noStroke();
  fill(230);
  text(label, x - 28, y + 28);
}

int connectionColor(int status) {
  if (status == STATUS_OK) {
    return color(80, 230, 120);
  }
  if (status == STATUS_RECONNECTING) {
    return color(240, 200, 80);
  }
  return color(220, 80, 80);
}

void drawPresetSection() {
  for (int i = 0; i < presetButtons.length; i++) {
    presetButtons[i].draw();
  }
}

void drawCollarSection() {
  fill(200);
  textAlign(LEFT, BASELINE);
  text("装着モード", 20, 104);

  collarRunToggle.draw();
  collarRunThresholdSlider.draw();
  collarRunVolumeSlider.draw();

  collarBigMotionToggle.draw();
  collarBigMotionSlider.draw();

  collarRelativeToggle.draw();
  collarRelativeMarginSlider.draw();

  fill(190);
  if (soundMode == MODE_COLLAR) {
    String runStatus = collarRunActive ? "RUN LOOP: ON" : "RUN LOOP: idle";
    String stillStatus = collarStillFlag ? "静止フラグ: ON" : "静止フラグ: OFF";
    String relStatus = collarRelativeLatched ? "相対: LATCHED" : "相対: ARMED";
    text(runStatus + "  " + stillStatus + "  " + relStatus, 20, 322);
  }

  for (TestSoundButton btn : testButtons) {
    if (btn.label.startsWith("Collar")) {
      btn.draw();
    }
  }
}

void drawBallSection() {
  fill(200);
  text("ボールモード", 20, 344);

  ballRollingToggle.draw();
  ballRollSensitivitySlider.draw();

  ballStopToggle.draw();
  ballStopSecondsSlider.draw();

  ballCollisionToggle.draw();
  ballCollisionSlider.draw();

  fill(190);
  if (soundMode == MODE_BALL) {
    String rollStatus = ballRollingActive ? "ROLLING: ON" : "ROLLING: idle";
    String stopStatus = ballStopStart > 0 ? "停止検出中" : "停止計測待ち";
    text(rollStatus + "  " + stopStatus, 20, 544);
  }

  for (TestSoundButton btn : testButtons) {
    if (btn.label.startsWith("Ball")) {
      btn.draw();
    }
  }
}

void drawSensorDebug() {
  int x = 610;
  int y = 260;
  fill(210);
  text("センサー", x, y);
  fill(230);
  text("加速度:" + nf(acc[0],1,2) + "," + nf(acc[1],1,2) + "," + nf(acc[2],1,2), x, y + 24);
  text("|a|:" + nf(accelMagnitude,1,2) + " |a|-g:" + nf(accelWithoutGravity,1,2), x, y + 46);
  text("ジャイロ:" + nf(gyro[0],1,1) + "," + nf(gyro[1],1,1) + "," + nf(gyro[2],1,1), x, y + 70);
  text("|ω|:" + nf(gyroMagnitude,1,1), x, y + 92);

  fill(200);
  text("score:" + nf(collarMotionScore,1,2) + " hp:" + nf(accelHP,1,2) + " gyroHP:" + nf(gyroHP,1,2), x, y + 122);
}

void drawAudioStatus() {
  fill(200);
  String serialLine;
  if (!useSerialInput) {
    serialLine = "Serial: disabled";
  } else if (!serialReady) {
    serialLine = "Serial: waiting for device";
  } else if (!serialHasPacket) {
    serialLine = "Serial: waiting for data";
  } else {
    serialLine = "Serial: OK (" + nf((millis() - lastSerialDataMillis)/1000.0, 1, 2) + "s)";
  }
  text(serialStatusMessage, 610, 420);
  text(serialLine, 610, 442);

  if (audioStatusMessage != null && audioStatusMessage.length() > 0) {
    text("Audio: " + audioStatusMessage, 610, 470);
  }
}

void mousePressed() {
  if (modeSwitch.handleClick(mouseX, mouseY)) {
    return;
  }

  ToggleControl[] toggles = {
    panicToggle,
    collarRunToggle,
    collarBigMotionToggle,
    collarRelativeToggle,
    ballRollingToggle,
    ballStopToggle,
    ballCollisionToggle
  };

  for (int i = 0; i < toggles.length; i++) {
    if (toggles[i] != null && toggles[i].handleClick(mouseX, mouseY)) {
      return;
    }
  }

  SliderControl[] sliders = {
    masterVolumeSlider,
    collarRunThresholdSlider,
    collarRunVolumeSlider,
    collarBigMotionSlider,
    collarRelativeMarginSlider,
    ballRollSensitivitySlider,
    ballStopSecondsSlider,
    ballCollisionSlider
  };

  for (int i = 0; i < sliders.length; i++) {
    SliderControl s = sliders[i];
    if (s != null && s.handlePress(mouseX, mouseY)) {
      activeSlider = s;
      return;
    }
  }

  for (int i = 0; i < presetButtons.length; i++) {
    if (presetButtons[i].handleClick(mouseX, mouseY)) {
      applyPreset(i);
      return;
    }
  }

  for (int i = 0; i < testButtons.length; i++) {
    if (testButtons[i].handleClick(mouseX, mouseY)) {
      return;
    }
  }
}

void mouseDragged() {
  if (activeSlider != null) {
    activeSlider.handleDrag(mouseX);
  }
}

void mouseReleased() {
  activeSlider = null;
}

void applyPreset(int index) {
  if (index == 0) { // small dog collar focus
    collarRunThresholdSlider.setValue(0.48);
    collarRunVolumeSlider.setValue(0.85);
    collarBigMotionSlider.setValue(1.1);
    collarRelativeMarginSlider.setValue(0.22);
    ballRollSensitivitySlider.setValue(0.8);
    ballStopSecondsSlider.setValue(6.0);
    ballCollisionSlider.setValue(1.2);
    masterVolumeSlider.setValue(0.75);
  } else if (index == 1) { // medium dog
    collarRunThresholdSlider.setValue(0.6);
    collarRunVolumeSlider.setValue(1.0);
    collarBigMotionSlider.setValue(1.4);
    collarRelativeMarginSlider.setValue(0.3);
    ballRollSensitivitySlider.setValue(0.6);
    ballStopSecondsSlider.setValue(7.5);
    ballCollisionSlider.setValue(1.4);
    masterVolumeSlider.setValue(0.82);
  } else if (index == 2) { // large dog
    collarRunThresholdSlider.setValue(0.75);
    collarRunVolumeSlider.setValue(1.1);
    collarBigMotionSlider.setValue(1.7);
    collarRelativeMarginSlider.setValue(0.36);
    ballRollSensitivitySlider.setValue(0.45);
    ballStopSecondsSlider.setValue(8.5);
    ballCollisionSlider.setValue(1.55);
    masterVolumeSlider.setValue(0.88);
  } else if (index == 3) { // indoor ball preset
    soundMode = MODE_BALL;
    modeSwitch.selectedIndex = MODE_BALL;
    collarRunThresholdSlider.setValue(0.58);
    collarRunVolumeSlider.setValue(0.9);
    collarBigMotionSlider.setValue(1.3);
    collarRelativeMarginSlider.setValue(0.28);
    ballRollSensitivitySlider.setValue(0.9);
    ballStopSecondsSlider.setValue(5.5);
    ballCollisionSlider.setValue(1.0);
    masterVolumeSlider.setValue(0.7);
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

void oscEvent(OscMessage msg) {
  if (msg.checkAddrPattern("/imu/accel")) {
    if (msg.checkTypetag("fff")) {
      acc[0] = msg.get(0).floatValue();
      acc[1] = msg.get(1).floatValue();
      acc[2] = msg.get(2).floatValue();
    }
  } else if (msg.checkAddrPattern("/imu/gyro")) {
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
  closeSample(collarBigMotionSample);
  closeSample(collarRelativeBurstSample);
  closeSample(ballStopSample);
  closeSample(ballCollisionSample);
  closePlayer(collarRunLoop);
  closePlayer(ballRollingLoop);
  if (minim != null) {
    minim.stop();
  }
  super.exit();
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

// --- UI helper classes ---

class ToggleControl {
  String label;
  float x, y, w, h;
  boolean value = false;

  ToggleControl(String label, float x, float y, float w, float h) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  void draw() {
    stroke(60);
    if (value) {
      fill(90, 200, 120);
    } else {
      fill(70);
    }
    rect(x, y, w, h, 8);
    fill(240);
    textAlign(CENTER, CENTER);
    text(label + (value ? " ON" : " OFF"), x + w / 2, y + h / 2);
  }

  boolean handleClick(float mx, float my) {
    if (mx >= x && mx <= x + w && my >= y && my <= y + h) {
      value = !value;
      return true;
    }
    return false;
  }
}

class SliderControl {
  String label;
  float x, y, w;
  float minValue, maxValue;
  float value;
  int decimals;
  float handleRadius = 9;

  SliderControl(String label, float x, float y, float w, float minValue, float maxValue, float initialValue, int decimals) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.minValue = minValue;
    this.maxValue = maxValue;
    this.value = constrain(initialValue, minValue, maxValue);
    this.decimals = decimals;
  }

  void draw() {
    fill(220);
    textAlign(LEFT, BASELINE);
    text(label + ": " + nf(value, 1, decimals), x, y - 6);

    float trackY = y + 6;
    stroke(80);
    strokeWeight(2);
    line(x, trackY, x + w, trackY);

    float nx = norm(value, minValue, maxValue);
    float handleX = x + nx * w;

    noStroke();
    fill(120, 200, 255);
    circle(handleX, trackY, handleRadius * 2);
  }

  boolean handlePress(float mx, float my) {
    float trackY = y + 6;
    float nx = norm(value, minValue, maxValue);
    float handleX = x + nx * w;
    float d = dist(mx, my, handleX, trackY);
    if (d <= handleRadius * 1.6 || (mx >= x && mx <= x + w && abs(my - trackY) < 12)) {
      updateFromX(mx);
      return true;
    }
    return false;
  }

  void handleDrag(float mx) {
    updateFromX(mx);
  }

  void updateFromX(float mx) {
    float nx = constrain((mx - x) / w, 0, 1);
    value = lerp(minValue, maxValue, nx);
  }

  void setValue(float v) {
    value = constrain(v, minValue, maxValue);
  }
}

class SegmentControl {
  float x, y, w, h;
  String[] labels;
  int selectedIndex = 0;

  SegmentControl(float x, float y, float w, float h, String[] labels) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.labels = labels;
  }

  void draw() {
    stroke(60);
    fill(60);
    rect(x, y, w, h, 10);
    float segmentWidth = w / labels.length;
    textAlign(CENTER, CENTER);
    for (int i = 0; i < labels.length; i++) {
      if (i == selectedIndex) {
        fill(90, 140, 255);
      } else {
        fill(90);
      }
      rect(x + i * segmentWidth, y, segmentWidth, h, i == 0 ? 10 : 0, i == labels.length - 1 ? 10 : 0, i == labels.length - 1 ? 10 : 0, i == 0 ? 10 : 0);
      fill(240);
      text(labels[i], x + segmentWidth * i + segmentWidth / 2, y + h / 2);
    }
  }

  boolean handleClick(float mx, float my) {
    if (mx < x || mx > x + w || my < y || my > y + h) {
      return false;
    }
    int parts = labels.length;
    float segmentWidth = w / parts;
    int index = (int) ((mx - x) / segmentWidth);
    selectedIndex = constrain(index, 0, labels.length - 1);
    return true;
  }
}

class PresetButton {
  String label;
  float x, y, w, h;

  PresetButton(String label, float x, float y, float w, float h) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
  }

  void draw() {
    stroke(70);
    fill(60);
    rect(x, y, w, h, 6);
    fill(230);
    textAlign(CENTER, CENTER);
    text(label, x + w / 2, y + h / 2);
  }

  boolean handleClick(float mx, float my) {
    return mx >= x && mx <= x + w && my >= y && my <= y + h;
  }
}

class TestSoundButton {
  static final int TYPE_SAMPLE = 0;
  static final int TYPE_LOOP = 1;

  String label;
  float x, y, w, h;
  int type;
  AudioSample sample;
  AudioPlayer loop;

  TestSoundButton(String label, float x, float y, float w, float h, int type, AudioSample sample) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.type = type;
    this.sample = sample;
  }

  TestSoundButton(String label, float x, float y, float w, float h, int type, AudioPlayer loop) {
    this.label = label;
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.type = type;
    this.loop = loop;
  }

  void draw() {
    stroke(70);
    fill(80);
    rect(x, y, w, h, 6);
    fill(230);
    textAlign(CENTER, CENTER);
    text(label, x + w / 2, y + h / 2);
  }

  boolean handleClick(float mx, float my) {
    if (mx < x || mx > x + w || my < y || my > y + h) {
      return false;
    }
    if (type == TYPE_SAMPLE && sample != null) {
      triggerSample(sample, 0.9);
    } else if (type == TYPE_LOOP && loop != null) {
      float newAmp = applyMaster(1.0);
      loop.setGain(ampToGainDb(newAmp));
      loop.rewind();
      loop.play();
    }
    return true;
  }
}
