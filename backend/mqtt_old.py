import os
import json
import threading
import paho.mqtt.client as mqtt
from datetime import datetime

from prometheus_client import Gauge, Counter
from database import SessionLocal
import models

# ============================================================
# 📊 Prometheus Metrics
# ============================================================
truck_temperature = Gauge(
    'truck_temperature_celsius',
    'Truck temperature',
    ['truck_id']
)

truck_humidity = Gauge(
    'truck_humidity_percent',
    'Truck humidity',
    ['truck_id']
)

gas_alert_counter = Counter(
    'truck_gas_alerts_total',
    'Gas alerts',
    ['truck_id', 'gas_type']
)

door_open_counter = Counter(
    'truck_door_open_total',
    'Door open events',
    ['truck_id']
)

mqtt_msg_counter = Counter(
    'mqtt_messages_received_total',
    'MQTT messages received'
)

# ============================================================
# ⚙️ CONFIG
# ============================================================
MQTT_BROKER = os.getenv("MQTT_BROKER", "localhost")
MQTT_TOPIC = "safechain/+/sensors"

# ============================================================
# 🔧 Helper parsing
# ============================================================
def safe_float(value):
    try:
        return float(value)
    except:
        return None


def extract_truck_id(raw_id: str):
    try:
        return int(raw_id.replace("TRUCK_", ""))
    except:
        return 1

# ============================================================
# 📩 MQTT Handler
# ============================================================
def on_message(client, userdata, msg):
    db = SessionLocal()

    try:
        payload = json.loads(msg.payload.decode())
        print(f"📩 MQTT: {payload}")

        truck_raw = payload.get("truck_id")
        if not truck_raw:
            return

        truck_id = extract_truck_id(truck_raw)

        # ================= DATA =================
        temp = safe_float(payload.get("temperature"))
        hum = safe_float(payload.get("humidity"))

        mq135_alert = bool(payload.get("mq135_gas_alert"))
        mq9_alert = bool(payload.get("mq9_gas_alert"))

        door_status = payload.get("door_status", "مغلق")

        lat = safe_float(payload.get("latitude"))
        lng = safe_float(payload.get("longitude"))

        # ================= TRIP =================
        Trips = models.Base.classes.trips

        active_trip = db.query(Trips).filter(
            Trips.truck_id == truck_id,
            Trips.status == "active"
        ).first()

        shipment_number = active_trip.shipment_number if active_trip else "AUTO-MQTT"
        user_id = active_trip.user_id if active_trip else 1

        # ================= REPORT =================
        Reports = models.Base.classes.reports

        report = Reports(
            truck_id=truck_id,
            shipment_number=shipment_number,
            temperature=temp,
            humidity=hum,
            mq135_Gas="غير طبيعي" if mq135_alert else "طبيعي",
            mq9_Gas="غير طبيعي" if mq9_alert else "طبيعي",
            Door_condition=door_status,
            latitude=lat,
            longitude=lng,
            full_date=datetime.now()
        )

        db.add(report)
        db.commit()

        # ================= PROMETHEUS =================
        mqtt_msg_counter.inc()

        if temp is not None:
            truck_temperature.labels(str(truck_id)).set(temp)

        if hum is not None:
            truck_humidity.labels(str(truck_id)).set(hum)

        if mq135_alert:
            gas_alert_counter.labels(str(truck_id), "mq135").inc()

        if mq9_alert:
            gas_alert_counter.labels(str(truck_id), "mq9").inc()

        if door_status == "مفتوح":
            door_open_counter.labels(str(truck_id)).inc()

        # ================= ALERTS =================
        if mq135_alert or mq9_alert:
            Alerts = models.Base.classes.alerts

            if mq135_alert and mq9_alert:
                reason = "تسرب غاز من الحساسين"
            elif mq135_alert:
                reason = "تسرب من MQ135"
            else:
                reason = "تسرب من MQ9"

            alert = Alerts(
                shipment_number=shipment_number,
                alert_reason=reason,
                user_id=user_id,
                full_date=datetime.now(),
                latitude=lat,
                longitude=lng
            )

            db.add(alert)
            db.commit()

            print(f"⚠️ ALERT saved: {reason}")

    except Exception as e:
        print(f"❌ MQTT ERROR: {e}")
        db.rollback()

    finally:
        db.close()

# ============================================================
# 🔌 MQTT START
# ============================================================
def start_mqtt_listener():
    client = mqtt.Client()
    client.on_message = on_message

    try:
        client.connect(MQTT_BROKER, 1883, 60)
        client.subscribe(MQTT_TOPIC)

        print(f"🔗 MQTT Connected to {MQTT_BROKER}")
        client.loop_forever()

    except Exception as e:
        print(f"❌ MQTT Connection Failed: {e}")

# ============================================================
# 🚀 RUN THREAD
# ============================================================
def run_mqtt_listener():
    thread = threading.Thread(target=start_mqtt_listener, daemon=True)
    thread.start()
    return thread