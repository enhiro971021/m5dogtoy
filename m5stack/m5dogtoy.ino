#include <M5Unified.h>
#include <WiFi.h>
#include <ArduinoOSCWiFi.h>

// --- 動作モード設定 ---
const bool kEnableWiFi = false;        // ルーターがない場合は false のままで USB 経由のみ
const uint32_t kWiFiTimeoutMs = 8000;  // Wi-Fi 接続の待ち時間上限

// --- WiFi設定 ---
const char* ssid = "prototype-001";         // ← ご自身のSSID
const char* password = "prototype-001G";    // ← ご自身のパスワード

// --- OSC送信先設定 ---
const char* host = "192.168.11.3";  // 送信先（PCなど）のIPアドレス
const int port = 8000;               // OSC受信用ポート番号

// --- IMUデータ用 ---
float accX, accY, accZ;
float gyroX, gyroY, gyroZ;

bool wifiConnected = false;

void setup() {
  auto cfg = M5.config();
  M5.begin(cfg);
  Serial.begin(115200);

  M5.Lcd.setRotation(3);
  M5.Lcd.setTextSize(2);
  M5.Lcd.fillScreen(BLACK);
  M5.Lcd.setCursor(0, 0);

  if (kEnableWiFi) {
    M5.Lcd.println("Connecting WiFi...");
    WiFi.begin(ssid, password);

    uint32_t start = millis();
    while (WiFi.status() != WL_CONNECTED && (millis() - start) < kWiFiTimeoutMs) {
      delay(250);
      M5.Lcd.print(".");
    }

    if (WiFi.status() == WL_CONNECTED) {
      wifiConnected = true;
      M5.Lcd.println("\nWiFi connected!");
      M5.Lcd.println(WiFi.localIP());
    } else {
      wifiConnected = false;
      M5.Lcd.println("\nWiFi timeout");
      M5.Lcd.println("USB serial only");
      WiFi.disconnect(true);
    }
  } else {
    wifiConnected = false;
    M5.Lcd.println("WiFi disabled");
    M5.Lcd.println("USB serial streaming");
  }

  M5.Lcd.println("IMU streaming...");
}

void loop() {
  M5.update();

  if (!M5.Imu.isEnabled()) {
    delay(50);
    return;
  }

  M5.Imu.getAccel(&accX, &accY, &accZ);
  M5.Imu.getGyro(&gyroX, &gyroY, &gyroZ);

  if (wifiConnected) {
    OscWiFi.send(host, port, "/imu/accel", accX, accY, accZ);
    OscWiFi.send(host, port, "/imu/gyro", gyroX, gyroY, gyroZ);
  }

  Serial.printf("IMU,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f\n", accX, accY, accZ, gyroX, gyroY, gyroZ);

  M5.Lcd.setCursor(0, 80);
  M5.Lcd.printf("ACC: %.2f %.2f %.2f\n", accX, accY, accZ);
  M5.Lcd.printf("GYR: %.1f %.1f %.1f\n", gyroX, gyroY, gyroZ);

  delay(50);  // 約20Hzで送信
}
