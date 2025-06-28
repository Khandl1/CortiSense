#include <Wire.h>
#include "Adafruit_TCS34725.h"
#include <Adafruit_Sensor.h>

#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEService.h>
#include <BLECharacteristic.h>
#include <BLEAdvertising.h>

// I2C Pins for ESP32
#define SDA_PIN 21
#define SCL_PIN 22

// BLE UUIDs (must match with your Flutter app)
#define SERVICE_UUID        "e0e0f0f0-0000-1000-8000-00805f9b34fb"
#define CHARACTERISTIC_UUID "e0e0f0f1-0000-1000-8000-00805f9b34fb"

// Initialize TCS34725 sensor
Adafruit_TCS34725 tcs = Adafruit_TCS34725(TCS34725_INTEGRATIONTIME_600MS, TCS34725_GAIN_60X);

BLEServer* pServer = NULL;
BLECharacteristic* rgbCharacteristic = NULL;
bool deviceConnected = false;

// BLE connection callback
class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Client Connected");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Client Disconnected");
    pServer->startAdvertising();
    Serial.println("Restarted advertising...");
  }
};

void setup() {
  Serial.begin(115200);
  Wire.begin(SDA_PIN, SCL_PIN); // Use custom I2C pins

  if (!tcs.begin()) {
    Serial.println("TCS34725 not found. Check connections.");
    while (1);
  }
  Serial.println("TCS34725 sensor initialized.");

  // BLE setup
  BLEDevice::init("ESP32_Cortisol_Sensor");
  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  rgbCharacteristic = pService->createCharacteristic(
                        CHARACTERISTIC_UUID,
                        BLECharacteristic::PROPERTY_READ |
                        BLECharacteristic::PROPERTY_NOTIFY
                      );

  pService->start();

  BLEAdvertising *pAdvertising = pServer->getAdvertising();
  pAdvertising->addServiceUUID(SERVICE_UUID);
  pAdvertising->setScanResponse(true);
  pServer->startAdvertising();

  Serial.println("BLE advertising started.");
}

void loop() {
  uint16_t r, g, b, c;
  tcs.getRawData(&r, &g, &b, &c);

  Serial.print("Raw R: "); Serial.print(r);
  Serial.print(" G: "); Serial.print(g);
  Serial.print(" B: "); Serial.print(b);
  Serial.print(" Clear: "); Serial.println(c);

  if (c == 0) {
    Serial.println("Clear channel is 0, skipping...");
    delay(1000);
    return;
  }

  // Normalize RGB to 0–255
  uint8_t red = (uint8_t)((float)r / c * 255.0);
  uint8_t green = (uint8_t)((float)g / c * 255.0);
  uint8_t blue = (uint8_t)((float)b / c * 255.0);

  Serial.print("Normalized R: "); Serial.print(red);
  Serial.print(" G: "); Serial.print(green);
  Serial.print(" B: "); Serial.println(blue);

  // Send RGB data over BLE
  uint8_t rgb[3] = { red, green, blue };
  rgbCharacteristic->setValue(rgb, 3);

  if (deviceConnected) {
    rgbCharacteristic->notify();
    Serial.println("Sent RGB values via BLE.");
  }

  delay(1000); // 1 second delay between readings
}
