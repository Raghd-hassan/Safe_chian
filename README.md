# Safe Chain

**An Intelligent Food Safety Monitoring System Using IoT**

Safe Chain is an IoT-based system for real-time monitoring and safety assurance of food during transport and storage. It integrates environmental sensors with a cloud platform and mobile app to reduce food spoilage, improve cold-chain transparency, and enable instant intervention when unsafe conditions occur.

> Graduation project — Department of Computing, College of Engineering and Computing at Al-Qunfudhah, Umm Al-Qura University, KSA (2025–2026)

---

##  The Problem

Food spoilage during transport and storage causes significant economic loss and health risks, especially when temperature, humidity, or gas conditions exceed safe limits without anyone noticing in time. Existing commercial cold-chain monitoring systems are often costly, complex, or lack real-time alerting suited to smaller transport companies and restaurants.

##  What Safe Chain Does

- Continuously monitors **temperature**, **humidity**, **gas emissions**, and **truck door status** using onboard sensors
- Transmits live sensor data from a **Raspberry Pi** device to a cloud database
- Sends **instant alerts** when readings exceed predefined safety thresholds
- Provides a **dashboard** (web/mobile) for live monitoring, historical reports, and trend analysis
- Supports **user roles**, device pairing, and account–device binding for multi-truck fleets

**Target users:** food transport & distribution companies, restaurants and food storage facilities, regulatory authorities, and consumers.

##  System Architecture

The system follows a 3-layer architecture:

1. **Presentation Layer** — Mobile app (user interface)
2. **Business Logic Layer** — Data processing, threshold checks, and notifications
3. **Data Layer** — Storage and synchronization

```
[Sensors] → [Raspberry Pi 4] → [FastAPI Backend] → [MySQL Database]
                                        ↓
                              [Flutter Mobile App]
                                        ↓
                        [Prometheus + Grafana Monitoring]
```

##  Tech Stack

### Hardware
| Component | Purpose |
|---|---|
| Raspberry Pi 4 | Main IoT controller |
| SHT31 | Temperature & humidity sensor |
| MQ-135 | Gas sensor (air quality) |
| MQ-9 | Gas sensor (CO / combustible gases) |
| NEO-6M | GPS module |
| Magnetic Reed Switch | Truck door status |

### Connectivity
Wi-Fi · 4G LTE · LoRaWAN

### Software
| Layer | Technology |
|---|---|
| Mobile App | Flutter |
| Backend / API | FastAPI |
| Database | MySQL (via SQLAlchemy) |
| Monitoring | Prometheus |
| Visualization | Grafana |
| IDE | Visual Studio Code |

### Methodology
Developed using **Scrum (Agile)**.

##  Features

- User login, registration, OTP verification, and password reset
- Real-time sensor data monitoring dashboard
- Instant alert system with configurable safety thresholds
- Historical records, filtering, and report generation/export
- Admin panel: user management, truck assignment, device pairing/unpairing
- Role-based access control (RBAC)

##  Database Schema (MySQL)

Key tables include: `Users`, `Trucks`, `User_Trucks`, `Groups`, `Products`, `Trips`, `Trip_Counter`, `Reports`, `Alerts`, `Sensors`, `Security_Limits`, `Updates`.

##  Getting Started

### Prerequisites
- Python 3.x
- Flutter SDK
- MySQL Server
- Raspberry Pi 4 (for hardware deployment) with the listed sensors

### Backend Setup
```bash
# Clone the repository
git clone https://github.com/Raghd-hassan/safe-chain-Project.git
cd safe-chain/backend

# Install dependencies
pip install -r requirements.txt

# Configure environment variables (DB credentials, etc.)
cp .env.example .env

# Run the FastAPI server
uvicorn main:app --reload
```

### Mobile App Setup
```bash
cd safe-chain/mobile
flutter pub get
flutter run
```

### Database
```bash
mysql -u <user> -p < database/init_script.sql
```

##  Testing

The project was validated through functional, UI/usability, design, operational, performance, and security testing, along with unit tests covering core modules.

##  Security & Privacy

- Role-Based Access Control (RBAC)
- Two-Factor Authentication (OTP)
- Encrypted data transmission (TLS/SSL)

##  Future Work

- Expanding sensor coverage for additional food categories
- Enhancing predictive analytics for spoilage risk
- Broader fleet-scale deployment and integration with regulatory reporting systems

##  Authors

| Name | ID |
|---|---|
| Shatha Mohammed Al-Montashery | 444007872 |
| Wajdan Atiyeh Al-Zahrani | 444004760 |
| Reema Al-Rashdi | 444004209 |
| Raghad Hassan Al-Masaari | 444001447 |
| Aryam Aqeel Al-Zubaidi | 444002164 |

Supervisor: Dr. Ali Abdulaziz Al-Zubaidi — Dept. of Computing, College of Engineering and Computing at Al-Qunfudhah, Umm Al-Qura University
##  License

This project is submitted in partial fulfillment of the Bachelor's degree requirements in Computer Science at Umm Al-Qura University. It is the intellectual property of Umm Al-Qura University and the respective supervisor; use for extension, product development, or commercial purposes requires university and supervisor permission.

---

*Built with ❤️ to make the food supply chain safer, one sensor at a time.*
