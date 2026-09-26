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
    """Extract numeric truck ID from TRUCK_XXX format"""
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
            print("⚠️ No truck_id in payload")
            return

        truck_id = extract_truck_id(truck_raw)

        # ================= DATA =================
        temp = safe_float(payload.get("temperature"))
        hum = safe_float(payload.get("humidity"))

        mq135_alert = bool(payload.get("mq135_gas_alert"))
        mq9_alert = bool(payload.get("mq9_gas_alert"))

        door_status = payload.get("door_status", "CLOSED")
        if door_status == "مفتوح":
            door_status = "OPEN"
        elif door_status == "مغلق":
            door_status = "CLOSED"

        lat = safe_float(payload.get("latitude"))
        lng = safe_float(payload.get("longitude"))

        # ================= FIND ACTIVE TRIP =================
        # In normalized schema, we need to find active trip through user_trucks
        Trips = models.Base.classes.trips
        UserTrucks = models.Base.classes.user_trucks

        # Find active trip for this truck
        active_trip = db.query(Trips).join(
            UserTrucks, Trips.user_truck_id == UserTrucks.ID
        ).filter(
            UserTrucks.truck_id == truck_id,
            Trips.status == "active"
        ).first()

        if not active_trip:
            print(f"⚠️ No active trip found for truck {truck_id}")
            # Still save to a default shipment
            shipment_number = f"AUTO-MQTT-{truck_id}"
        else:
            shipment_number = active_trip.shipment_number

        # ================= SAVE REPORT =================
        Reports = models.Base.classes.reports

        report = Reports(
            shipment_number=shipment_number,
            temperature=temp if temp is not None else 0.0,
            humidity=hum if hum is not None else 0.0,
            mq135_gas=safe_float(payload.get("mq135_gas")),
            mq9_gas=safe_float(payload.get("mq9_gas")),
            door_condition=door_status,
            latitude=lat if lat is not None else 0.0,
            longitude=lng if lng is not None else 0.0,
            full_date=datetime.now()
        )

        db.add(report)
        db.commit()
        print(f"✅ Report saved for shipment: {shipment_number}")

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

        if door_status == "OPEN":
            door_open_counter.labels(str(truck_id)).inc()

        # ================= CHECK FOR ALERTS =================
        if active_trip and (mq135_alert or mq9_alert):
            Alerts = models.Base.classes.alerts

            if mq135_alert and mq9_alert:
                reason = "تسرب غاز من الحساسين (MQ9 & MQ135)"
            elif mq135_alert:
                reason = "تسرب غاز من حساس MQ135"
            else:
                reason = "تسرب غاز من حساس MQ9"

            alert = Alerts(
                shipment_number=shipment_number,
                alert_reason=reason,
                duration=None,  # Ongoing alert
                latitude=lat,
                longitude=lng,
                full_date=datetime.now()
            )

            db.add(alert)
            db.commit()

            print(f"⚠️ ALERT saved: {reason}")

        # ================= CHECK TEMPERATURE VIOLATIONS =================
        if active_trip and temp is not None:
            SecurityLimits = models.Base.classes.security_limits
            
            limits = db.query(SecurityLimits).filter(
                SecurityLimits.shipment_number == shipment_number
            ).first()
            
            if limits:
                if temp < limits.min_temperature or temp > limits.max_temperature:
                    Alerts = models.Base.classes.alerts
                    
                    if temp < limits.min_temperature:
                        reason = f"انخفاض الحرارة عن الحد الأدنى ({temp}°C < {limits.min_temperature}°C)"
                    else:
                        reason = f"تجاوز الحرارة الحد الأقصى ({temp}°C > {limits.max_temperature}°C)"
                    
                    alert = Alerts(
                        shipment_number=shipment_number,
                        alert_reason=reason,
                        duration=None,
                        latitude=lat,
                        longitude=lng,
                        full_date=datetime.now()
                    )
                    
                    db.add(alert)
                    db.commit()
                    print(f"⚠️ Temperature Alert: {reason}")

        # ================= CHECK HUMIDITY VIOLATIONS =================
        if active_trip and hum is not None:
            SecurityLimits = models.Base.classes.security_limits
            
            limits = db.query(SecurityLimits).filter(
                SecurityLimits.shipment_number == shipment_number
            ).first()
            
            if limits:
                if hum < limits.min_humidity or hum > limits.max_humidity:
                    Alerts = models.Base.classes.alerts
                    
                    if hum < limits.min_humidity:
                        reason = f"انخفاض الرطوبة عن الحد الأدنى ({hum}% < {limits.min_humidity}%)"
                    else:
                        reason = f"تجاوز الرطوبة الحد الأقصى ({hum}% > {limits.max_humidity}%)"
                    
                    alert = Alerts(
                        shipment_number=shipment_number,
                        alert_reason=reason,
                        duration=None,
                        latitude=lat,
                        longitude=lng,
                        full_date=datetime.now()
                    )
                    
                    db.add(alert)
                    db.commit()
                    print(f"⚠️ Humidity Alert: {reason}")

    except Exception as e:
        print(f"❌ MQTT ERROR: {e}")
        import traceback
        traceback.print_exc()
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
        print(f"📡 Subscribed to topic: {MQTT_TOPIC}")
        client.loop_forever()

    except Exception as e:
        print(f"❌ MQTT Connection Failed: {e}")

# ============================================================
# 🚀 RUN THREAD
# ============================================================
def run_mqtt_listener():
    thread = threading.Thread(target=start_mqtt_listener, daemon=True)
    thread.start()
    print("🚀 MQTT Listener thread started")
    return thread
