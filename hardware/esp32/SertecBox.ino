#include <Arduino.h>
#include <SPI.h>
#include <Wire.h>
#include <Adafruit_MAX31865.h>
#include <Adafruit_SHT31.h>

#include <BLEDevice.h>
#include <BLEUtils.h>
#include <BLEServer.h>
#include <BLE2902.h>

// ================= CONFIG BLE =================
#define DEVICE_NAME        "SertecBox-001"

#define SERVICE_UUID        "12345678-1234-1234-1234-123456789abc"
#define CHARACTERISTIC_UUID "abcd1234-5678-90ab-cdef-123456789abc"

// ================= BLE =================
BLECharacteristic *pCharacteristic;
BLEServer *pServer;
bool deviceConnected = false;

// ================= PT100 =================
#define MAX31865_CS 5
Adafruit_MAX31865 pt100 = Adafruit_MAX31865(MAX31865_CS);

// ================= SHT31 =================
Adafruit_SHT31 sht31 = Adafruit_SHT31();

// ================= PRESSÃO =================
#define PRESSURE_PIN 34

// ================= CONFIG SENSOR =================
#define RREF      430.0
#define RNOMINAL  100.0

// ================= TIMING =================
unsigned long lastSend = 0;
const int interval = 1000; // ms

// ================= CALLBACK =================
class MyServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer* pServer) {
    deviceConnected = true;
    Serial.println("Cliente conectado");
  }

  void onDisconnect(BLEServer* pServer) {
    deviceConnected = false;
    Serial.println("Cliente desconectado");

    delay(100);
    BLEDevice::startAdvertising();
    Serial.println("Advertising reiniciado");
  }
};

// ================= SETUP =================
void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\nInicializando SertecBox...");

  // ===== PT100 =====
  if (!pt100.begin(MAX31865_3WIRE)) {
    Serial.println("ERRO: MAX31865 nao encontrado");
  } else {
    Serial.println("MAX31865 OK");
  }

  // ===== SHT31 =====
  if (!sht31.begin(0x44)) {
    Serial.println("AVISO: SHT31 nao encontrado");
  } else {
    Serial.println("SHT31 OK");
  }

  // ===== BLE INIT =====
  BLEDevice::init(DEVICE_NAME);

  pServer = BLEDevice::createServer();
  pServer->setCallbacks(new MyServerCallbacks());

  BLEService *pService = pServer->createService(SERVICE_UUID);

  pCharacteristic = pService->createCharacteristic(
    CHARACTERISTIC_UUID,
    BLECharacteristic::PROPERTY_READ |
    BLECharacteristic::PROPERTY_NOTIFY
  );

  // Necessário para NOTIFY funcionar no Android e iOS
  pCharacteristic->addDescriptor(new BLE2902());

  pService->start();

  // ===== ADVERTISING =====
  BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();

  pAdvertising->addServiceUUID(SERVICE_UUID); // Necessário para match por UUID
  pAdvertising->setScanResponse(true);
  // CORRIGIDO: era setMinPreferred(0x12) — deve ser setMaxPreferred
  pAdvertising->setMinPreferred(0x06);
  pAdvertising->setMaxPreferred(0x12);

  BLEDevice::startAdvertising();

  Serial.println("BLE pronto. Aguardando conexao...");
  Serial.print("Nome do dispositivo: ");
  Serial.println(DEVICE_NAME);
  Serial.print("Service UUID: ");
  Serial.println(SERVICE_UUID);
}

// ================= LOOP =================
void loop() {

  if (millis() - lastSend >= interval) {
    lastSend = millis();

    // ===== PT100 (temperatura da solda) =====
    float temperature = pt100.temperature(RNOMINAL, RREF);

    // ===== SHT31 (ambiente) =====
    float temp_env = sht31.readTemperature();
    float humidity  = sht31.readHumidity();

    // ===== PRESSÃO (sensor 4-20mA, 0-250 bar, shunt 165Ω) =====
    int   raw        = analogRead(PRESSURE_PIN);
    float voltage    = raw * (3.3 / 4095.0);
    float current_mA = (voltage / 165.0) * 1000.0;
    float pressure   = (current_mA - 4.0) * (250.0 / 16.0);
    if (pressure < 0) pressure = 0;

    // ===== JSON =====
    String data = "{";
    data += "\"v\":1,";
    data += "\"temp\":"     + String(temperature, 2) + ",";
    data += "\"temp_env\":" + String(temp_env, 2)    + ",";
    data += "\"humidity\":" + String(humidity, 2)    + ",";
    data += "\"pressure\":" + String(pressure, 2);
    data += "}";

    Serial.println(data);

    // ===== BLE SEND =====
    if (deviceConnected) {
      pCharacteristic->setValue(data.c_str());
      pCharacteristic->notify();
    }
  }
}
