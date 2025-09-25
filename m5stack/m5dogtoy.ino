#include <M5Unified.h>
#include <WiFi.h>
#include <ArduinoOSCWiFi.h>

// --- WiFi設定 ---
const char* ssid = "prototype-001";         // ← ご自身のSSID
const char* password = "prototype-001G"; // ← ご自身のパスワード

// --- OSC送信先設定 ---
const char* host = "192.168.11.3";  // 送信先（PCなど）のIPアドレス
const int port = 8000;               // OSC受信用ポート番号

// --- IMUデータ用 ---
float accX, accY, accZ;
float gyroX, gyroY, gyroZ;

void setup() {
  // M5初期化
  auto cfg = M5.config();
  M5.begin(cfg);
  M5.Lcd.setRotation(3);
  M5.Lcd.setTextSize(2);
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setCursor(0, 0);
  M5.Lcd.println("Connecting WiFi...");

  // WiFi接続
  WiFi.begin(ssid, password);
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }

  M5.Lcd.println("WiFi connected!");
  M5.Lcd.println(WiFi.localIP());

  // OSC送信確認表示
  M5.Lcd.println("Sending IMU via OSC...");
}

void loop() {
  M5.update();

  // IMUのデータ取得
  if (M5.Imu.isEnabled()) {
    M5.Imu.getAccel(&accX, &accY, &accZ);
    M5.Imu.getGyro(&gyroX, &gyroY, &gyroZ);

    // OSC送信
    OscWiFi.send(host, port, "/imu/accel", accX, accY, accZ);
    OscWiFi.send(host, port, "/imu/gyro", gyroX, gyroY, gyroZ);

    // LCDに表示（デバッグ用）
    M5.Lcd.setCursor(0, 80);
    M5.Lcd.printf("ACC: %.2f %.2f %.2f\n", accX, accY, accZ);
    M5.Lcd.printf("GYR: %.2f %.2f %.2f\n", gyroX, gyroY, gyroZ);
  }

  delay(100); // 送信間隔（10Hz）
}
