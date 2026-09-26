import os
import io
import json
from fastapi import FastAPI, Depends, HTTPException, status, Query, Request
from fastapi.security import OAuth2PasswordBearer, HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session
from sqlalchemy import func, and_, or_
from database import SessionLocal
import models
from passlib.context import CryptContext
from schemas import (
    UserCreate, UserLogin, ResetPassword, VerifyCode, UserUpdate, EmailRequest,
    UpdateRoleRequest, StartTripRequest, SecurityLimitsRequest, CreateReportRequest,
    CreateAlertRequest, TruckCreate, AssignTruckRequest
)
from datetime import datetime, timedelta, time
from jose import JWTError, jwt
import random
from pydantic import BaseModel
from typing import List, Optional
from fastapi.middleware.cors import CORSMiddleware
from collections import defaultdict
from threading import Lock
import openpyxl
from fastapi.responses import StreamingResponse
from fpdf import FPDF
import arabic_reshaper
from bidi.algorithm import get_display

# ============================================================
# ✅ الإعدادات الأساسية
# ============================================================
SECRET_KEY = os.getenv("SECRET_KEY", "s3cr3t_k3y_s4f3ch41n_2024_change_me")
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24 * 7  # 7 أيام

app = FastAPI(title="SafeChain API - Normalized", version="2.0.0")

# ============================================================
# ✅ CORS
# ============================================================
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============================================================
# ✅ الأمان
# ============================================================
pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="login", auto_error=False)
security = HTTPBearer(auto_error=False)

# ============================================================
# ✅ Rate Limiting
# ============================================================
rate_limit_storage = defaultdict(list)
rate_limit_lock = Lock()

def check_rate_limit(ip: str, max_attempts: int = 5, window_seconds: int = 60):
    now = datetime.now()
    with rate_limit_lock:
        rate_limit_storage[ip] = [
            t for t in rate_limit_storage[ip] if (now - t).total_seconds() < window_seconds
        ]
        if len(rate_limit_storage[ip]) >= max_attempts:
            raise HTTPException(status_code=429, detail="محاولات كثيرة جداً. حاول بعد قليل")
        rate_limit_storage[ip].append(now)

# ============================================================
# ✅ تخزين OTP المؤقت
# ============================================================
otp_storage: dict[str, dict] = {}

def store_otp(email: str, otp: str):
    otp_storage[email] = {"code": otp, "expires_at": datetime.now() + timedelta(minutes=10)}

def verify_otp(email: str, code: str) -> bool:
    entry = otp_storage.get(email)
    if not entry: return False
    if datetime.now() > entry["expires_at"]:
        otp_storage.pop(email, None)
        return False
    return entry["code"] == code

def clear_otp(email: str):
    otp_storage.pop(email, None)

# ============================================================
# ✅ اتصال قاعدة البيانات
# ============================================================
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

# ============================================================
# ✅ دوال JWT والأمان
# ============================================================
def create_access_token(data: dict, expires_delta: timedelta | None = None):
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)

async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security),
    db: Session = Depends(get_db)
):
    if not credentials:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="لم يتم توفير رمز المصادقة", headers={"WWW-Authenticate": "Bearer"})

    token = credentials.credentials
    credentials_exception = HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="رمز المصادقة غير صالح أو منتهي", headers={"WWW-Authenticate": "Bearer"})

    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
        user_id = payload.get("sub")
        if user_id is None: raise credentials_exception
        user_id = int(user_id)
    except JWTError as e:
        print(f"JWT Error: {e}")
        raise credentials_exception

    Users = models.Base.classes.users
    user = db.query(Users).filter(Users.ID == user_id).first()
    if user is None: raise credentials_exception

    jwt_role = payload.get("role")
    if jwt_role and jwt_role != user.role:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="تم تحديث صلاحياتك، سجّل دخولك مجدداً")

    return user

def require_admin(current_user=Depends(get_current_user)):
    if current_user.role != "admin":
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="غير مصرح لك بهذا الإجراء")
    return current_user

# ============================================================
# ✅ Helper Functions
# ============================================================
def reshape_arabic(text: str) -> str:
    if not text: return ""
    reshaped = arabic_reshaper.reshape(text)
    return get_display(reshaped)

def apply_filters(query, model, start_date, end_date, search):
    if start_date:
        try:
            start_dt = datetime.combine(datetime.strptime(start_date, "%Y-%m-%d").date(), time.min)
            query = query.filter(model.full_date >= start_dt)
        except Exception: pass
    if end_date:
        try:
            end_dt = datetime.combine(datetime.strptime(end_date, "%Y-%m-%d").date(), time.max)
            query = query.filter(model.full_date <= end_dt)
        except Exception: pass
    if search:
        # Trim whitespace from search term
        search = search.strip()
        print(f"🔍 Applying search filter: '{search}'")
        if hasattr(model, 'shipment_number'):
            # Use partial match - searches anywhere in shipment number
            query = query.filter(model.shipment_number.ilike(f"%{search}%"))
            print(f"✅ Search filter applied on shipment_number (partial match)")
        else:
            print(f"⚠️ Model has no shipment_number attribute")
    return query

def get_user_truck_ids(db: Session, user_id: int) -> List[int]:
    """Get list of truck IDs assigned to a user"""
    UserTrucks = models.Base.classes.user_trucks
    user_trucks = db.query(UserTrucks).filter(UserTrucks.user_id == user_id).all()
    return [ut.truck_id for ut in user_trucks]

def get_truck_from_user_truck_id(db: Session, user_truck_id: int):
    """Get truck details from user_truck_id"""
    UserTrucks = models.Base.classes.user_trucks
    Trucks = models.Base.classes.trucks
    
    user_truck = db.query(UserTrucks).filter(UserTrucks.ID == user_truck_id).first()
    if not user_truck:
        return None
    
    truck = db.query(Trucks).filter(Trucks.ID == user_truck.truck_id).first()
    return truck

# ============================================================
# ✅ Authentication Endpoints
# ============================================================
@app.get("/verify-token")
async def verify_token(current_user=Depends(get_current_user)):
    return {"valid": True, "user_id": current_user.ID, "role": current_user.role}

@app.post("/register")
def register_user(request: Request, user: UserCreate, db: Session = Depends(get_db)):
    check_rate_limit(request.client.host, max_attempts=3, window_seconds=60)
    Users = models.Base.classes.users
    exist = db.query(Users).filter(Users.email == user.email).first()
    if exist: raise HTTPException(status_code=400, detail="الإيميل مسجل مسبقاً")

    hashed_password = pwd_context.hash(user.password)
    new_user = Users(full_name=user.full_name, email=user.email, phone=user.phone, password=hashed_password, role="user")
    db.add(new_user)
    db.commit()
    db.refresh(new_user)

    otp = str(random.randint(1000, 9999))
    store_otp(user.email, otp)
    print(f"🔐 OTP for {user.email}: {otp}")
    return {"message": "تم إنشاء الحساب", "otp": otp}

@app.post("/send-reset-code")
def send_reset_code(request: Request, data: EmailRequest, db: Session = Depends(get_db)):
    check_rate_limit(request.client.host, max_attempts=3, window_seconds=60)
    Users = models.Base.classes.users
    user = db.query(Users).filter(Users.email == data.email).first()
    if not user: raise HTTPException(status_code=404, detail="الإيميل غير موجود")

    otp = str(random.randint(1000, 9999))
    store_otp(data.email, otp)
    print(f"🔐 RESET OTP for {data.email}: {otp}")
    return {"message": "تم إرسال رمز التحقق"}

@app.post("/verify-email")
def verify_email(data: VerifyCode):
    if not verify_otp(data.email, data.code): raise HTTPException(status_code=400, detail="رمز غير صحيح أو منتهي الصلاحية")
    clear_otp(data.email)
    return {"message": "تم التفعيل"}

@app.post("/login")
def login_user(request: Request, credentials: UserLogin, db: Session = Depends(get_db)):
    check_rate_limit(request.client.host, max_attempts=5, window_seconds=60)
    Users = models.Base.classes.users
    user = db.query(Users).filter(Users.email == credentials.email).first()
    if not user or not pwd_context.verify(credentials.password, user.password):
        raise HTTPException(status_code=401, detail="بيانات غير صحيحة")

    access_token = create_access_token(data={"sub": str(user.ID), "role": user.role})
    return {"access_token": access_token, "token_type": "bearer", "role": user.role, "user_id": user.ID, "full_name": user.full_name, "message": "تم تسجيل الدخول"}

@app.post("/reset-password")
def reset_password(data: ResetPassword, db: Session = Depends(get_db)):
    Users = models.Base.classes.users
    user = db.query(Users).filter(Users.email == data.email).first()
    if not user: raise HTTPException(status_code=404, detail="المستخدم غير موجود")
    if not verify_otp(data.email, data.code): raise HTTPException(status_code=400, detail="رمز غير صحيح أو منتهي الصلاحية")
    user.password = pwd_context.hash(data.new_password)
    db.commit()
    clear_otp(data.email)
    return {"message": "تم تغيير كلمة المرور"}

# ============================================================
# ✅ Profile Endpoints
# ============================================================
@app.get("/profile")
def get_user_profile(current_user=Depends(get_current_user)):
    return {"full_name": current_user.full_name, "email": current_user.email, "phone": current_user.phone, "role": current_user.role}

@app.put("/profile")
def update_profile(data: UserUpdate, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    Users = models.Base.classes.users
    user_in_db = db.query(Users).filter(Users.ID == current_user.ID).first()
    if not user_in_db: raise HTTPException(status_code=404, detail="المستخدم غير موجود")
    if data.full_name: user_in_db.full_name = data.full_name
    if data.email:
        email_exists = db.query(Users).filter(Users.email == data.email, Users.ID != current_user.ID).first()
        if email_exists: raise HTTPException(status_code=400, detail="الإيميل مستخدم من قبل شخص آخر")
        user_in_db.email = data.email
    if data.phone: user_in_db.phone = data.phone
    if data.password: user_in_db.password = pwd_context.hash(data.password)
    db.commit()
    return {"message": "تم تحديث البيانات بنجاح"}

@app.get("/user/active-trip")
def get_user_active_trip(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get current user's active trip if exists"""
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    # Get user's truck IDs
    user_truck_ids = [ut.ID for ut in db.query(UserTrucks).filter(UserTrucks.user_id == current_user.ID).all()]
    
    if not user_truck_ids:
        return {"shipment_number": None}
    
    # Find active trip
    active_trip = db.query(Trips).filter(
        Trips.user_truck_id.in_(user_truck_ids),
        Trips.status == "active"
    ).first()
    
    if active_trip:
        return {"shipment_number": active_trip.shipment_number}
    
    return {"shipment_number": None}

@app.get("/user/truck-path")
def get_user_truck_path(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get GPS path for user's last/active trip"""
    Trips = models.Base.classes.trips
    Reports = models.Base.classes.reports
    UserTrucks = models.Base.classes.user_trucks
    
    # Get user's truck IDs
    user_truck_ids = [ut.ID for ut in db.query(UserTrucks).filter(UserTrucks.user_id == current_user.ID).all()]
    
    if not user_truck_ids:
        return {"path": []}
    
    # Get most recent trip (active or completed)
    last_trip = db.query(Trips).filter(
        Trips.user_truck_id.in_(user_truck_ids)
    ).order_by(Trips.created_at.desc()).first()
    
    if not last_trip:
        return {"path": []}
    
    # Get all reports for this trip ordered by date (for path)
    reports = db.query(Reports).filter(
        Reports.shipment_number == last_trip.shipment_number
    ).filter(
        Reports.latitude.isnot(None),
        Reports.longitude.isnot(None)
    ).order_by(Reports.full_date.asc()).all()
    
    if not reports:
        return {"path": []}
    
    # Build GPS path
    path_points = [{
        "latitude": float(r.latitude),
        "longitude": float(r.longitude),
        "timestamp": r.full_date.strftime("%Y-%m-%d %H:%M:%S")
    } for r in reports]
    
    return {"path": path_points}

# ============================================================
# ✅ Trucks Endpoints
# ============================================================
@app.get("/trucks")
def get_trucks(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get all trucks assigned to the current user"""
    UserTrucks = models.Base.classes.user_trucks
    Trucks = models.Base.classes.trucks
    
    user_trucks = db.query(Trucks, UserTrucks).join(
        UserTrucks, UserTrucks.truck_id == Trucks.ID
    ).filter(UserTrucks.user_id == current_user.ID).all()
    
    return [{"id": truck.ID, "name": truck.name, "user_truck_id": ut.ID} for truck, ut in user_trucks]

# Alias for clarity
@app.get("/my-trucks")
def get_my_trucks(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get trucks assigned to current user (alias for /trucks)"""
    return get_trucks(db, current_user)

@app.post("/trucks")
def create_truck(data: TruckCreate, db: Session = Depends(get_db), current_user=Depends(require_admin)):
    """Admin only: Create a new truck"""
    Trucks = models.Base.classes.trucks
    new_truck = Trucks(name=data.name)
    db.add(new_truck)
    db.commit()
    db.refresh(new_truck)
    return {"message": "تم إنشاء الشاحنة", "truck_id": new_truck.ID}

@app.post("/assign-truck")
def assign_truck(data: AssignTruckRequest, db: Session = Depends(get_db), current_user=Depends(require_admin)):
    """Admin only: Assign a truck to a user"""
    UserTrucks = models.Base.classes.user_trucks
    
    # Check if already assigned
    existing = db.query(UserTrucks).filter(
        UserTrucks.user_id == data.user_id,
        UserTrucks.truck_id == data.truck_id
    ).first()
    
    if existing:
        raise HTTPException(status_code=400, detail="الشاحنة مسندة لهذا المستخدم بالفعل")
    
    assignment = UserTrucks(user_id=data.user_id, truck_id=data.truck_id)
    db.add(assignment)
    db.commit()
    
    # Auto-insert update record for truck assignment
    Updates = models.Base.classes.updates
    Trucks = models.Base.classes.trucks
    Users = models.Base.classes.users
    
    truck = db.query(Trucks).filter(Trucks.ID == data.truck_id).first()
    user = db.query(Users).filter(Users.ID == data.user_id).first()
    
    truck_name = truck.name if truck else f"شاحنة {data.truck_id}"
    user_name = user.full_name if user and user.full_name else (user.name if user else f"مستخدم {data.user_id}")
    
    update_record = Updates(
        truck_id=data.truck_id,
        admin_id=current_user.ID,
        item_name="إسناد شاحنة لمستخدم",
        description=f"تم إسناد الشاحنة {truck_name} للمستخدم {user_name} (ID: {data.user_id})"
    )
    db.add(update_record)
    db.commit()
    
    return {"message": "تم إسناد الشاحنة للمستخدم"}

@app.delete("/unassign-truck")
def unassign_truck(data: AssignTruckRequest, db: Session = Depends(get_db), current_user=Depends(require_admin)):
    """Admin only: Unassign a truck from a user"""
    UserTrucks = models.Base.classes.user_trucks
    
    assignment = db.query(UserTrucks).filter(
        UserTrucks.user_id == data.user_id,
        UserTrucks.truck_id == data.truck_id
    ).first()
    
    if not assignment:
        raise HTTPException(status_code=404, detail="الإسناد غير موجود")
    
    db.delete(assignment)
    db.commit()
    return {"message": "تم إلغاء إسناد الشاحنة"}

@app.get("/admin/user-trucks/{user_id}")
def get_user_trucks(user_id: int, db: Session = Depends(get_db), current_user=Depends(require_admin)):
    """Admin only: Get all trucks assigned to a specific user"""
    UserTrucks = models.Base.classes.user_trucks
    
    assignments = db.query(UserTrucks).filter(UserTrucks.user_id == user_id).all()
    truck_ids = [a.truck_id for a in assignments]
    
    return {"user_id": user_id, "truck_ids": truck_ids}

@app.get("/admin/trucks")
def admin_get_all_trucks(
    page: int = Query(1, ge=1),
    limit: int = Query(100, ge=1, le=500),
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get all trucks in the system"""
    Trucks = models.Base.classes.trucks
    
    query = db.query(Trucks)
    total = query.count()
    skip = (page - 1) * limit
    results = query.offset(skip).limit(limit).all()
    
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "data": [{"id": t.ID, "name": t.name} for t in results]
    }

# ============================================================
# ✅ Trips Endpoints
# ============================================================
@app.post("/start-trip")
def start_trip(trip_data: StartTripRequest, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Start a new trip - Users can select products during trip start"""
    TripCounter = models.Base.classes.trip_counter
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    # Check if user has access to this truck
    user_truck = db.query(UserTrucks).filter(
        UserTrucks.user_id == current_user.ID,
        UserTrucks.truck_id == trip_data.truck_id
    ).first()
    
    if not user_truck:
        raise HTTPException(status_code=404, detail="الشاحنة غير موجودة أو لا تخصك")
    
    # Check for active trips for this user_truck
    active_trip = db.query(Trips).filter(
        Trips.user_truck_id == user_truck.ID,
        Trips.status == "active"
    ).first()
    
    if active_trip:
        raise HTTPException(status_code=400, detail="توجد رحلة نشطة بالفعل لهذه الشاحنة")
    
    # Generate shipment number
    counter = db.query(TripCounter).filter(
        TripCounter.truck_id == trip_data.truck_id,
        TripCounter.user_id == current_user.ID
    ).first()
    
    if counter:
        counter.last_sequence += 1
    else:
        counter = TripCounter(truck_id=trip_data.truck_id, user_id=current_user.ID, last_sequence=1)
        db.add(counter)
    db.flush()
    
    seq = str(counter.last_sequence).zfill(4)
    shipment_number = f"SHP-{trip_data.truck_id}-{seq}"
    
    # Create trip with JSON product_ids (both users and admins can set products)
    product_ids_json = json.dumps(trip_data.product_ids) if trip_data.product_ids else None
    
    new_trip = Trips(
        user_truck_id=user_truck.ID,
        shipment_number=shipment_number,
        status="active",
        start_time=datetime.now(),
        product_ids=product_ids_json
    )
    
    try:
        db.add(new_trip)
        db.commit()
        db.refresh(new_trip)
        return {"status": "success", "shipment_number": shipment_number, "trip_id": new_trip.ID}
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/end-trip")
def end_trip(shipment_number: str = Query(..., description="رقم الشحنة"), db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """End an active trip"""
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    # Get trip with user validation
    trip = db.query(Trips).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(
        Trips.shipment_number == shipment_number,
        UserTrucks.user_id == current_user.ID
    ).first()
    
    if not trip:
        raise HTTPException(status_code=404, detail="الرحلة غير موجودة أو لا تخصك")
    
    if trip.status == "completed":
        raise HTTPException(status_code=400, detail="الرحلة منتهية مسبقاً")
    
    trip.status = "completed"
    trip.end_time = datetime.now()
    
    try:
        db.commit()
        return {
            "status": "success",
            "message": "تم إنهاء الرحلة بنجاح",
            "shipment_number": shipment_number,
            "end_time": trip.end_time.strftime("%Y-%m-%d %H:%M:%S")
        }
    except Exception as e:
        db.rollback()
        raise HTTPException(status_code=500, detail=f"حدث خطأ: {str(e)}")

@app.get("/trips")
def get_trips(
    status: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Get trips for current user"""
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    query = db.query(Trips).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(UserTrucks.user_id == current_user.ID)
    
    if status:
        query = query.filter(Trips.status == status)
    
    total = query.count()
    skip = (page - 1) * limit
    results = query.order_by(Trips.start_time.desc()).offset(skip).limit(limit).all()
    
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "data": [{
            "id": t.ID,
            "shipment_number": t.shipment_number,
            "status": t.status,
            "product_ids": json.loads(t.product_ids) if t.product_ids else [],
            "start_time": t.start_time.strftime("%Y-%m-%d %H:%M:%S"),
            "end_time": t.end_time.strftime("%Y-%m-%d %H:%M:%S") if t.end_time else None
        } for t in results]
    }

# ============================================================
# ✅ Security Limits Endpoints
# ============================================================
@app.post("/security-limits")
def save_security_limits(data: SecurityLimitsRequest, db: Session = Depends(get_db), current_user=Depends(require_admin)):
    """Admin only: Create or update security limits for a shipment (with products selection)"""
    SecurityLimits = models.Base.classes.security_limits
    Trips = models.Base.classes.trips
    
    # Admin can set limits for any shipment (no user validation needed)
    trip = db.query(Trips).filter(
        Trips.shipment_number == data.shipment_number
    ).first()
    
    if not trip:
        raise HTTPException(status_code=404, detail="رقم الشحنة غير موجود")
    
    # Validate limits
    if data.min_temperature >= data.max_temperature:
        raise HTTPException(status_code=400, detail="الحرارة الدنيا يجب أن تكون أقل من العليا")
    
    if data.min_humidity >= data.max_humidity:
        raise HTTPException(status_code=400, detail="الرطوبة الدنيا يجب أن تكون أقل من العليا")
    
    # Check if limits already exist
    existing = db.query(SecurityLimits).filter(
        SecurityLimits.shipment_number == data.shipment_number
    ).first()
    
    if existing:
        # Update existing
        existing.min_temperature = data.min_temperature
        existing.max_temperature = data.max_temperature
        existing.min_humidity = data.min_humidity
        existing.max_humidity = data.max_humidity
        existing.door_open_duration = data.door_open_duration
        existing.door_open_count = data.door_open_count
        action_type = "تحديث"
    else:
        # Create new
        new_limit = SecurityLimits(
            shipment_number=data.shipment_number,
            min_temperature=data.min_temperature,
            max_temperature=data.max_temperature,
            min_humidity=data.min_humidity,
            max_humidity=data.max_humidity,
            door_open_duration=data.door_open_duration,
            door_open_count=data.door_open_count
        )
        db.add(new_limit)
        action_type = "تعيين"
    
    db.commit()
    
    # Auto-insert update record for security limits
    Updates = models.Base.classes.updates
    Trucks = models.Base.classes.trucks
    UserTrucks = models.Base.classes.user_trucks
    
    # Get truck_id from trip via user_truck_id
    try:
        print(f"DEBUG: Attempting to insert update record for shipment {data.shipment_number}")
        print(f"DEBUG: trip.user_truck_id = {trip.user_truck_id}")
        
        user_truck = db.query(UserTrucks).filter(UserTrucks.ID == trip.user_truck_id).first()
        print(f"DEBUG: user_truck found = {user_truck is not None}")
        
        if user_truck:
            truck_id = user_truck.truck_id
            print(f"DEBUG: truck_id = {truck_id}")
            
            truck = db.query(Trucks).filter(Trucks.ID == truck_id).first()
            truck_name = truck.name if truck else f"شاحنة {truck_id}"
            print(f"DEBUG: truck_name = {truck_name}")
            print(f"DEBUG: admin_id = {current_user.ID}")
            
            update_record = Updates(
                truck_id=truck_id,
                admin_id=current_user.ID,
                item_name="تحديد حدود الأمان",
                description=f"تم {action_type} حدود الأمان للشحنة {data.shipment_number} - الحرارة: {data.min_temperature}°-{data.max_temperature}° - الرطوبة: {data.min_humidity}%-{data.max_humidity}%"
            )
            db.add(update_record)
            db.commit()
            print(f"DEBUG: Update record inserted successfully")
        else:
            print(f"ERROR: user_truck not found for user_truck_id {trip.user_truck_id}")
    except Exception as e:
        # Log the error but don't fail the main operation
        print(f"ERROR: Failed to insert update record: {e}")
        import traceback
        traceback.print_exc()
    
    return {"status": "success", "message": "تم حفظ حدود الأمان بنجاح"}

@app.get("/security-limits/{shipment_number}")
def get_security_limits(shipment_number: str, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get security limits for a shipment"""
    SecurityLimits = models.Base.classes.security_limits
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    # Admins can view any shipment's limits
    if current_user.role == "admin":
        trip = db.query(Trips).filter(
            Trips.shipment_number == shipment_number
        ).first()
    else:
        # Regular users can only view their own shipments
        trip = db.query(Trips).join(
            UserTrucks, Trips.user_truck_id == UserTrucks.ID
        ).filter(
            Trips.shipment_number == shipment_number,
            UserTrucks.user_id == current_user.ID
        ).first()
    
    if not trip:
        raise HTTPException(status_code=404, detail="رقم الشحنة غير موجود أو لا يخصك")
    
    limits = db.query(SecurityLimits).filter(
        SecurityLimits.shipment_number == shipment_number
    ).first()
    
    if not limits:
        raise HTTPException(status_code=404, detail="لا توجد حدود أمان لهذه الشحنة")
    
    return {
        "shipment_number": limits.shipment_number,
        "min_temperature": limits.min_temperature,
        "max_temperature": limits.max_temperature,
        "min_humidity": limits.min_humidity,
        "max_humidity": limits.max_humidity,
        "door_open_duration": limits.door_open_duration,
        "door_open_count": limits.door_open_count
    }

@app.put("/admin/trip-products/{shipment_number}")
def update_trip_products(
    shipment_number: str, 
    product_ids: List[int],
    db: Session = Depends(get_db), 
    current_user=Depends(require_admin)
):
    """Admin only: Update product_ids for a trip"""
    Trips = models.Base.classes.trips
    
    trip = db.query(Trips).filter(Trips.shipment_number == shipment_number).first()
    if not trip:
        raise HTTPException(status_code=404, detail="الرحلة غير موجودة")
    
    trip.product_ids = json.dumps(product_ids) if product_ids else None
    db.commit()
    
    return {
        "status": "success",
        "message": "تم تحديث المنتجات بنجاح",
        "shipment_number": shipment_number,
        "product_ids": product_ids
    }
        

# ============================================================
# ✅ Reports Endpoints
# ============================================================
@app.post("/reports")
def save_report(data: CreateReportRequest, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Save a new sensor report"""
    Trips = models.Base.classes.trips
    Reports = models.Base.classes.reports
    UserTrucks = models.Base.classes.user_trucks
    
    # Validate shipment and that it's active
    trip = db.query(Trips).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(
        Trips.shipment_number == data.shipment_number,
        UserTrucks.user_id == current_user.ID,
        Trips.status == "active"
    ).first()
    
    if not trip:
        raise HTTPException(status_code=404, detail="الرحلة غير موجودة أو منتهية")
    
    new_report = Reports(
        shipment_number=data.shipment_number,
        temperature=data.temperature,
        humidity=data.humidity,
        door_condition=data.door_condition,
        mq9_gas=data.mq9_gas,
        mq135_gas=data.mq135_gas,
        latitude=data.latitude or 0.0,
        longitude=data.longitude or 0.0,
        full_date=datetime.now()
    )
    
    db.add(new_report)
    db.commit()
    return {"status": "success", "message": "تم حفظ التقرير"}

@app.get("/reports")
def get_reports(
    shipment_number: str = Query(None),
    truck_id: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    start_date: str = Query(None),
    end_date: str = Query(None),
    search: str = Query(None),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Get reports for user's shipments"""
    Reports = models.Base.classes.reports
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    Trucks = models.Base.classes.trucks
    
    # Base query with user filtering
    query = db.query(Reports).join(
        Trips, Reports.shipment_number == Trips.shipment_number
    ).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).join(
        Trucks, UserTrucks.truck_id == Trucks.ID
    ).filter(UserTrucks.user_id == current_user.ID)
    
    # Filter by truck_id if provided (searches truck name)
    if truck_id:
        truck_id = truck_id.strip()  # Trim whitespace
        query = query.filter(Trucks.name.ilike(f"%{truck_id}%"))
        print(f"🚛 Filtering by truck name containing: {truck_id}")
    
    if shipment_number:
        shipment_number = shipment_number.strip()  # Trim whitespace
        query = query.filter(Reports.shipment_number == shipment_number)
    
    query = apply_filters(query, Reports, start_date, end_date, search)
    
    total = query.count()
    skip = (page - 1) * limit
    results = query.order_by(Reports.full_date.desc()).offset(skip).limit(limit).all()
    
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "data": [{
            "id": r.ID,
            "shipment_number": r.shipment_number,
            "temperature": r.temperature,
            "humidity": r.humidity,
            "door_condition": r.door_condition,
            "mq9_gas": r.mq9_gas,
            "mq135_gas": r.mq135_gas,
            "latitude": float(r.latitude) if r.latitude else None,
            "longitude": float(r.longitude) if r.longitude else None,
            "full_date": r.full_date.strftime("%Y-%m-%d %H:%M:%S")
        } for r in results]
    }

# ============================================================
# ✅ Alerts Endpoints
# ============================================================
@app.post("/alerts")
def save_alert(data: CreateAlertRequest, db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Save a new alert"""
    Alerts = models.Base.classes.alerts
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    # Validate shipment belongs to user
    trip = db.query(Trips).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(
        Trips.shipment_number == data.shipment_number,
        UserTrucks.user_id == current_user.ID
    ).first()
    
    if not trip:
        raise HTTPException(status_code=404, detail="رقم الشحنة غير موجود أو لا يخصك")
    
    # Check for duplicate alerts (within 60 seconds)
    existing_alert = db.query(Alerts).filter(
        Alerts.shipment_number == data.shipment_number
    ).order_by(Alerts.full_date.desc()).first()
    
    if existing_alert:
        if (datetime.now() - existing_alert.full_date).total_seconds() < 60:
            return {"status": "ignored", "message": "تم تجاهل التنبيه المكرر"}
    
    new_alert = Alerts(
        shipment_number=data.shipment_number,
        alert_reason=data.alert_reason,
        duration=data.duration,
        latitude=data.latitude,
        longitude=data.longitude,
        full_date=datetime.now()
    )
    
    db.add(new_alert)
    db.commit()
    return {"status": "success", "message": "تم حفظ التنبيه بنجاح"}

@app.get("/alerts")
def get_alerts(
    shipment_number: str = Query(None),
    start_date: str = Query(None),
    end_date: str = Query(None),
    search: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Get alerts for user's shipments"""
    Alerts = models.Base.classes.alerts
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    # Base query with user filtering
    query = db.query(Alerts).join(
        Trips, Alerts.shipment_number == Trips.shipment_number
    ).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(UserTrucks.user_id == current_user.ID)
    
    if shipment_number:
        query = query.filter(Alerts.shipment_number == shipment_number)
    
    query = apply_filters(query, Alerts, start_date, end_date, search)
    
    total = query.count()
    skip = (page - 1) * limit
    results = query.order_by(Alerts.full_date.desc()).offset(skip).limit(limit).all()
    
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "data": [{
            "id": r.ID,
            "shipment_number": r.shipment_number,
            "alert_reason": r.alert_reason,
            "duration": r.duration,
            "latitude": float(r.latitude) if r.latitude else None,
            "longitude": float(r.longitude) if r.longitude else None,
            "full_date": r.full_date.strftime("%Y-%m-%d %H:%M:%S")
        } for r in results]
    }

# ============================================================
# ✅ Products Endpoints
# ============================================================
@app.get("/products")
def get_products(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get all products with their group information"""
    Products = models.Base.classes.products
    Groups = models.Base.classes.groups
    
    results = db.query(Products, Groups).outerjoin(
        Groups, Groups.ID == Products.group_id
    ).all()
    
    return [{
        "id": p.ID,
        "product_name": p.product_name,
        "group_id": p.group_id or None,
        "group_min_temperature": g.min_temperature if g else None,
        "group_max_temperature": g.max_temperature if g else None,
        "group_min_humidity": g.min_humidity if g else None,
        "group_max_humidity": g.max_humidity if g else None
    } for p, g in results]

# ============================================================
# ✅ Dashboard Endpoints
# ============================================================
@app.get("/truck-live-data")
def get_truck_live_data(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get live sensor data from the most recent report for user's first truck"""
    Reports = models.Base.classes.reports
    UserTrucks = models.Base.classes.user_trucks
    Trips = models.Base.classes.trips
    SecurityLimits = models.Base.classes.security_limits
    
    # Get user's first truck
    user_truck = db.query(UserTrucks).filter(UserTrucks.user_id == current_user.ID).first()
    if not user_truck:
        return {}
    
    # Get the most recent report for any active trip of this truck
    report = db.query(Reports).join(
        Trips, Reports.shipment_number == Trips.shipment_number
    ).filter(
        Trips.user_truck_id == user_truck.ID
    ).order_by(Reports.full_date.desc()).first()
    
    if not report:
        return {}
    
    # Get security limits for this shipment
    limits = db.query(SecurityLimits).filter(
        SecurityLimits.shipment_number == report.shipment_number
    ).first()
    
    # Default limits if not set (using correct column names)
    min_temp = float(limits.min_temperature) if limits and hasattr(limits, 'min_temperature') and limits.min_temperature is not None else 0.0
    max_temp = float(limits.max_temperature) if limits and hasattr(limits, 'max_temperature') and limits.max_temperature is not None else 100.0
    min_hum = int(limits.min_humidity) if limits and hasattr(limits, 'min_humidity') and limits.min_humidity is not None else 0
    max_hum = int(limits.max_humidity) if limits and hasattr(limits, 'max_humidity') and limits.max_humidity is not None else 100
    max_door_open_time = int(limits.door_open_duration) if limits and hasattr(limits, 'door_open_duration') and limits.door_open_duration is not None else 0
    
    # Determine gas status based on values
    gas1_status = "غير طبيعي" if report.mq9_gas and report.mq9_gas > 1000 else "طبيعي"
    gas2_status = "غير طبيعي" if report.mq135_gas and report.mq135_gas > 1000 else "طبيعي"
    
    return {
        "shipment_number": report.shipment_number,
        "temperature": report.temperature,
        "humidity": report.humidity,
        "gas1_status": gas1_status,
        "gas2_status": gas2_status,
        "door_status": report.door_condition if report.door_condition else "مغلق",
        "latitude": float(report.latitude) if report.latitude else None,
        "longitude": float(report.longitude) if report.longitude else None,
        "last_updated": report.full_date.strftime("%Y-%m-%d %H:%M:%S") if report.full_date else "",
        # Security limits
        "min_temp": min_temp,
        "max_temp": max_temp,
        "min_hum": min_hum,
        "max_hum": max_hum,
        "max_door_open_time": max_door_open_time,
    }

# ============================================================
# ✅ Dashboard Endpoints
# ============================================================
@app.get("/dashboard")
def get_dashboard(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get dashboard statistics"""
    Trips = models.Base.classes.trips
    Reports = models.Base.classes.reports
    SecurityLimits = models.Base.classes.security_limits
    UserTrucks = models.Base.classes.user_trucks
    
    # Get user's trucks
    truck_ids = get_user_truck_ids(db, current_user.ID)
    total_trucks = len(truck_ids)
    
    if not truck_ids:
        return {"total_trucks": 0, "active_trips": 0, "compliant_shipments": 0, "non_compliant_shipments": 0}
    
    # Count active trips
    active_trips = db.query(Trips).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(
        UserTrucks.user_id == current_user.ID,
        Trips.status == "active"
    ).count()
    
    # Get all user's shipments with latest reports
    user_shipments = db.query(Trips.shipment_number).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(UserTrucks.user_id == current_user.ID).all()
    
    shipment_numbers = [s.shipment_number for s in user_shipments]
    
    if not shipment_numbers:
        return {"total_trucks": total_trucks, "active_trips": active_trips, "compliant_shipments": 0, "non_compliant_shipments": 0}
    
    compliant_count = 0
    non_compliant_count = 0
    
    for shipment_number in shipment_numbers:
        # Get security limits
        limits = db.query(SecurityLimits).filter(
            SecurityLimits.shipment_number == shipment_number
        ).first()
        
        if not limits:
            continue
        
        # Get latest report
        latest_report = db.query(Reports).filter(
            Reports.shipment_number == shipment_number
        ).order_by(Reports.full_date.desc()).first()
        
        if not latest_report:
            continue
        
        # Check compliance
        is_compliant = True
        
        if not (limits.min_temperature <= latest_report.temperature <= limits.max_temperature):
            is_compliant = False
        
        if not (limits.min_humidity <= latest_report.humidity <= limits.max_humidity):
            is_compliant = False
        
        if is_compliant:
            compliant_count += 1
        else:
            non_compliant_count += 1
    
    return {
        "total_trucks": total_trucks,
        "active_trips": active_trips,
        "compliant_shipments": compliant_count,
        "non_compliant_shipments": non_compliant_count
    }

# ============================================================
# ✅ Sensors Endpoint
# ============================================================
@app.get("/sensors")
def get_sensors(db: Session = Depends(get_db), current_user=Depends(get_current_user)):
    """Get all sensors for user's trucks"""
    Sensors = models.Base.classes.sensors
    UserTrucks = models.Base.classes.user_trucks
    Trucks = models.Base.classes.trucks
    
    truck_ids = get_user_truck_ids(db, current_user.ID)
    
    if not truck_ids:
        return []
    
    sensors = db.query(Sensors).filter(Sensors.truck_id.in_(truck_ids)).all()
    
    return [{
        "id": s.ID,
        "truck_id": s.truck_id,
        "serial_number": s.serial_number,
        "sensor_type": s.sensor_type,
        "status": s.status,
        "created_at": s.created_at.strftime("%Y-%m-%d %H:%M:%S")
    } for s in sensors]

# ============================================================
# ✅ Sensor History for Charts (fl_chart)
# ============================================================
@app.get("/sensor-history")
def get_sensor_history(
    range: str = Query("1h", description="Time range: 1h, 6h, 24h"),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Get historical sensor data for temperature and humidity charts"""
    from datetime import datetime, timedelta
    
    Reports = models.Base.classes.reports
    UserTrucks = models.Base.classes.user_trucks
    Trips = models.Base.classes.trips
    
    print(f"🔍 Fetching sensor history for user {current_user.ID}, range: {range}")
    
    # Get user's truck IDs through user_trucks table
    user_truck_ids = db.query(UserTrucks.ID).filter(
        UserTrucks.user_id == current_user.ID
    ).all()
    user_truck_ids = [ut[0] for ut in user_truck_ids]
    
    print(f"📦 User truck IDs: {user_truck_ids}")
    
    if not user_truck_ids:
        print("❌ No user trucks found")
        return {"history": []}
    
    # Get user's active or most recent trip
    trip = db.query(Trips).filter(
        Trips.user_truck_id.in_(user_truck_ids)
    ).order_by(Trips.created_at.desc()).first()
    
    if not trip:
        print("❌ No trips found")
        return {"history": []}
    
    print(f"✅ Found trip: {trip.shipment_number}")
    
    # Query ALL reports for this trip (for debugging - ignore time range)
    reports = db.query(Reports).filter(
        Reports.shipment_number == trip.shipment_number
    ).order_by(Reports.full_date.asc()).limit(100).all()
    
    print(f"📊 Found {len(reports)} reports")
    
    history = []
    for r in reports:
        if hasattr(r, 'temperature') and hasattr(r, 'humidity'):
            history.append({
                "timestamp": str(r.full_date) if hasattr(r, 'full_date') else None,
                "temperature": float(r.temperature) if r.temperature is not None else None,
                "humidity": float(r.humidity) if r.humidity is not None else None,
            })
    
    print(f"✅ Returning {len(history)} data points")
    
    return {"history": history}

# ============================================================
# ✅ Admin - Users Management
# ============================================================
@app.get("/admin/users")
def get_all_users(
    search: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get all users"""
    Users = models.Base.classes.users
    query = db.query(Users)
    
    if search:
        query = query.filter(
            or_(
                Users.full_name.ilike(f"%{search}%"),
                Users.email.ilike(f"%{search}%")
            )
        )
    
    total = query.count()
    skip = (page - 1) * limit
    users = query.offset(skip).limit(limit).all()
    
    return {
        "total": total,
        "page": page,
        "limit": limit,
        "data": [{
            "id": u.ID,
            "full_name": u.full_name,
            "email": u.email,
            "phone": u.phone,
            "role": u.role
        } for u in users]
    }

@app.delete("/admin/users/{user_id}")
def delete_user(user_id: int, db: Session = Depends(get_db), current_user=Depends(require_admin)):
    """Admin: Delete a user"""
    Users = models.Base.classes.users
    user = db.query(Users).filter(Users.ID == user_id).first()
    
    if not user:
        raise HTTPException(status_code=404, detail="المستخدم غير موجود")
    
    if user.ID == current_user.ID:
        raise HTTPException(status_code=400, detail="لا يمكنك حذف نفسك")
    
    db.delete(user)
    db.commit()
    return {"message": "تم حذف المستخدم"}

@app.put("/admin/users/{user_id}/role")
def update_user_role(
    user_id: int,
    data: UpdateRoleRequest,
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Update user role"""
    Users = models.Base.classes.users
    user = db.query(Users).filter(Users.ID == user_id).first()
    
    if not user:
        raise HTTPException(status_code=404, detail="المستخدم غير موجود")
    
    if data.role not in ["admin", "user"]:
        raise HTTPException(status_code=400, detail="قيمة role غير صحيحة")
    
    user.role = data.role
    db.commit()
    return {"message": "تم تحديث الصلاحية"}

# ============================================================
# ✅ Admin - Dashboard
# ============================================================
@app.get("/admin/truck-locations")
def admin_get_truck_locations(db: Session = Depends(get_db), current_user=Depends(require_admin)):
    """Admin: Get all truck locations with GPS paths for all trips (active and completed)"""
    Trucks = models.Base.classes.trucks
    Trips = models.Base.classes.trips
    Reports = models.Base.classes.reports
    UserTrucks = models.Base.classes.user_trucks
    Users = models.Base.classes.users
    
    truck_data = []
    
    # Get all trips (active and completed) with their latest data
    all_trips = db.query(Trips, Trucks, UserTrucks, Users).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).join(
        Trucks, UserTrucks.truck_id == Trucks.ID
    ).join(
        Users, UserTrucks.user_id == Users.ID
    ).all()
    
    for trip, truck, user_truck, user in all_trips:
        # Get all reports for this trip ordered by date (for path)
        reports = db.query(Reports).filter(
            Reports.shipment_number == trip.shipment_number
        ).filter(
            Reports.latitude.isnot(None),
            Reports.longitude.isnot(None)
        ).order_by(Reports.full_date.asc()).all()
        
        if reports:
            # Build GPS path from all reports
            path_points = [{
                "latitude": float(r.latitude),
                "longitude": float(r.longitude),
                "timestamp": r.full_date.strftime("%Y-%m-%d %H:%M:%S")
            } for r in reports]
            
            # Get latest report data
            latest_report = reports[-1]
            
            truck_data.append({
                "truck_id": truck.ID,
                "truck_name": truck.name,
                "driver_name": user.full_name,
                "shipment_number": trip.shipment_number,
                "trip_status": trip.status,  # "active" or "completed"
                "path": path_points,  # GPS path with all points
                "current_latitude": float(latest_report.latitude),
                "current_longitude": float(latest_report.longitude),
                "temperature": latest_report.temperature,
                "humidity": latest_report.humidity,
                "door_condition": latest_report.door_condition,
                "last_updated": latest_report.full_date.strftime("%Y-%m-%d %H:%M:%S")
            })
    
    return {"truck_locations": truck_data}

@app.get("/admin/dashboard")
def admin_dashboard(db: Session = Depends(get_db), current_user=Depends(require_admin)):
    """Admin: Get overall system dashboard with compliance statistics"""
    Users = models.Base.classes.users
    Trucks = models.Base.classes.trucks
    Trips = models.Base.classes.trips
    Reports = models.Base.classes.reports
    Alerts = models.Base.classes.alerts
    SecurityLimits = models.Base.classes.security_limits
    
    # Basic counts
    total_users = db.query(Users).count()
    total_trucks = db.query(Trucks).count()
    active_trips = db.query(Trips).filter(Trips.status == "active").count()
    total_reports = db.query(Reports).count()
    total_alerts = db.query(Alerts).count()
    
    # Calculate compliance statistics
    compliant_trucks = 0
    non_compliant_trucks = 0
    
    # Get all shipments (both active and completed)
    all_trips = db.query(Trips).all()
    
    for trip in all_trips:
        # Get security limits for this shipment
        limits = db.query(SecurityLimits).filter(
            SecurityLimits.shipment_number == trip.shipment_number
        ).first()
        
        if not limits:
            continue  # Skip if no limits set
        
        # Get latest report for this shipment
        latest_report = db.query(Reports).filter(
            Reports.shipment_number == trip.shipment_number
        ).order_by(Reports.full_date.desc()).first()
        
        if not latest_report:
            continue  # Skip if no reports yet
        
        # Check temperature compliance
        temp_compliant = (
            limits.min_temperature <= latest_report.temperature <= limits.max_temperature
        )
        
        # Check humidity compliance
        humidity_compliant = (
            limits.min_humidity <= latest_report.humidity <= limits.max_humidity
        )
        
        # Overall compliance
        is_compliant = temp_compliant and humidity_compliant
        
        if is_compliant:
            compliant_trucks += 1
        else:
            non_compliant_trucks += 1
    
    return {
        "total_users": total_users,
        "total_trucks": total_trucks,
        "active_trips": active_trips,
        "total_reports": total_reports,
        "total_alerts": total_alerts,
        "compliant_trucks": compliant_trucks,
        "non_compliant_trucks": non_compliant_trucks
    }

# ============================================================
# ✅ Admin - Reports, Alerts, Trips
# ============================================================
@app.get("/admin/reports")
def admin_get_reports(
    user_id: int = Query(None),
    truck_id: int = Query(None),
    shipment_number: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    start_date: str = Query(None),
    end_date: str = Query(None),
    search: str = Query(None),
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get all reports with truck information"""
    Reports = models.Base.classes.reports
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    # Join with trips to get truck_id
    query = db.query(Reports, Trips.user_truck_id).join(
        Trips, Reports.shipment_number == Trips.shipment_number
    )
    
    if user_id:
        query = query.join(
            UserTrucks, Trips.user_truck_id == UserTrucks.ID
        ).filter(UserTrucks.user_id == user_id)
    
    if truck_id:
        query = query.filter(Trips.user_truck_id == truck_id)
    
    if shipment_number:
        query = query.filter(Reports.shipment_number == shipment_number)
    
    # Apply date and search filters
    if start_date:
        query = query.filter(Reports.full_date >= start_date)
    if end_date:
        query = query.filter(Reports.full_date <= end_date)
    if search:
        query = query.filter(
            or_(
                Reports.shipment_number.ilike(f"%{search}%"),
                cast(Reports.temperature, String).ilike(f"%{search}%")
            )
        )
    
    total = query.count()
    skip = (page - 1) * limit
    results = query.order_by(Reports.full_date.desc()).offset(skip).limit(limit).all()
    
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "data": [{
            "id": r[0].ID,
            "truck_id": r[1],
            "shipment_number": r[0].shipment_number,
            "temperature": r[0].temperature,
            "humidity": r[0].humidity,
            "door_condition": r[0].door_condition,
            "mq9_gas": r[0].mq9_gas,
            "mq135_gas": r[0].mq135_gas,
            "latitude": float(r[0].latitude) if r[0].latitude else None,
            "longitude": float(r[0].longitude) if r[0].longitude else None,
            "full_date": r[0].full_date.strftime("%Y-%m-%d %H:%M:%S")
        } for r in results]
    }

@app.get("/admin/alerts")
def admin_get_alerts(
    user_id: int = Query(None),
    truck_id: int = Query(None),
    shipment_number: str = Query(None),
    start_date: str = Query(None),
    end_date: str = Query(None),
    search: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get all alerts with truck_id filtering"""
    Alerts = models.Base.classes.alerts
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    Trucks = models.Base.classes.trucks
    
    # Join with trips and user_trucks to get truck_id
    query = db.query(
        Alerts,
        UserTrucks.truck_id,
        Trucks.name.label('truck_name')
    ).join(
        Trips, Alerts.shipment_number == Trips.shipment_number
    ).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).join(
        Trucks, UserTrucks.truck_id == Trucks.ID
    )
    
    if user_id:
        query = query.filter(UserTrucks.user_id == user_id)
    
    if truck_id:
        query = query.filter(UserTrucks.truck_id == truck_id)
    
    if shipment_number:
        query = query.filter(Alerts.shipment_number == shipment_number)
    
    # Apply date and search filters on the Alerts object
    if start_date:
        try:
            query = query.filter(Alerts.full_date >= datetime.combine(
                datetime.strptime(start_date, "%Y-%m-%d").date(), time.min
            ))
        except: pass
    
    if end_date:
        try:
            query = query.filter(Alerts.full_date <= datetime.combine(
                datetime.strptime(end_date, "%Y-%m-%d").date(), time.max
            ))
        except: pass
    
    if search:
        query = query.filter(Alerts.shipment_number.ilike(f"%{search}%"))
    
    total = query.count()
    skip = (page - 1) * limit
    results = query.order_by(Alerts.full_date.desc()).offset(skip).limit(limit).all()
    
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "data": [{
            "id": r[0].ID,
            "shipment_number": r[0].shipment_number,
            "truck_id": r[1],
            "truck_name": r[2],
            "alert_reason": r[0].alert_reason,
            "duration": r[0].duration,
            "latitude": float(r[0].latitude) if r[0].latitude else None,
            "longitude": float(r[0].longitude) if r[0].longitude else None,
            "full_date": r[0].full_date.strftime("%Y-%m-%d %H:%M:%S")
        } for r in results]
    }

@app.get("/admin/trips")
def admin_get_trips(
    user_id: int = Query(None),
    status: str = Query(None),
    start_date: str = Query(None),
    end_date: str = Query(None),
    search: str = Query(None),
    page: int = Query(1, ge=1),
    limit: int = Query(20, ge=1, le=100),
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get all trips"""
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    query = db.query(Trips)
    
    if user_id:
        query = query.join(UserTrucks, Trips.user_truck_id == UserTrucks.ID).filter(
            UserTrucks.user_id == user_id
        )
    
    if status:
        query = query.filter(Trips.status == status)
    
    if search:
        query = query.filter(Trips.shipment_number.ilike(f"%{search}%"))
    
    if start_date:
        try:
            query = query.filter(Trips.start_time >= datetime.combine(
                datetime.strptime(start_date, "%Y-%m-%d").date(), time.min
            ))
        except: pass
    
    if end_date:
        try:
            query = query.filter(Trips.start_time <= datetime.combine(
                datetime.strptime(end_date, "%Y-%m-%d").date(), time.max
            ))
        except: pass
    
    total = query.count()
    skip = (page - 1) * limit
    results = query.order_by(Trips.start_time.desc()).offset(skip).limit(limit).all()
    
    return {
        "page": page,
        "limit": limit,
        "total": total,
        "data": [{
            "id": t.ID,
            "shipment_number": t.shipment_number,
            "status": t.status,
            "product_ids": json.loads(t.product_ids) if t.product_ids else [],
            "start_time": t.start_time.strftime("%Y-%m-%d %H:%M:%S"),
            "end_time": t.end_time.strftime("%Y-%m-%d %H:%M:%S") if t.end_time else None
        } for t in results]
    }

@app.get("/admin/sensors")
def admin_get_sensors(
    truck_id: int = Query(None),
    user_id: int = Query(None),
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get all sensors from the sensors table"""
    Sensors = models.Base.classes.sensors
    Trucks = models.Base.classes.trucks
    UserTrucks = models.Base.classes.user_trucks
    
    # Build query to get sensors with truck info
    # Use LEFT JOIN for user_trucks to include sensors even if truck has no user assigned
    query = db.query(
        Sensors,
        Trucks.ID.label('truck_id_col'),
        Trucks.name.label('truck_name'),
        UserTrucks.user_id
    ).join(
        Trucks, Sensors.truck_id == Trucks.ID
    ).outerjoin(
        UserTrucks, UserTrucks.truck_id == Trucks.ID
    )
    
    # Apply filters if provided
    if truck_id:
        query = query.filter(Sensors.truck_id == truck_id)
    
    if user_id:
        query = query.filter(UserTrucks.user_id == user_id)
    
    # Get distinct sensors to avoid duplicates if truck has multiple user assignments
    results = query.distinct().all()
    
    # Format response
    sensors_list = []
    for sensor, truck_id_val, truck_name_val, user_id_val in results:
        # Map database status to Arabic display status
        status_map = {
            'active': 'شغال',
            'inactive': 'غير معروف',
            'maintenance': 'تنبيه'
        }
        
        sensors_list.append({
            "id": sensor.ID,
            "truck_id": sensor.truck_id,
            "truck_name": truck_name_val,
            "user_id": user_id_val,
            "name": sensor.name,
            "serial_number": sensor.serial_number,
            "sensor_type": sensor.sensor_type,
            "status": status_map.get(sensor.status, 'غير معروف'),
            "created_at": sensor.created_at.isoformat() if hasattr(sensor.created_at, 'isoformat') else str(sensor.created_at),
            "updated_at": sensor.updated_at.isoformat() if hasattr(sensor.updated_at, 'isoformat') else str(sensor.updated_at)
        })
    
    return sensors_list

@app.post("/admin/sensors/record-check")
def admin_record_sensor_check(
    truck_id: int,
    sensor_count: int,
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Record that sensors were checked for a truck"""
    Updates = models.Base.classes.updates
    Trucks = models.Base.classes.trucks
    
    truck = db.query(Trucks).filter(Trucks.ID == truck_id).first()
    truck_name = truck.name if truck else f"شاحنة {truck_id}"
    
    update_record = Updates(
        truck_id=truck_id,
        admin_id=current_user.ID,
        item_name="فحص الحساسات",
        description=f"تم فحص حساسات {truck_name} - عدد الحساسات: {sensor_count}"
    )
    db.add(update_record)
    db.commit()
    
    return {"status": "success", "message": "تم تسجيل فحص الحساسات"}

@app.get("/admin/updates")
def admin_get_updates(
    truck_id: int = Query(None),
    start_date: str = Query(None),
    end_date: str = Query(None),
    search: str = Query(None),
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get hardware maintenance updates"""
    Updates = models.Base.classes.updates
    Trucks = models.Base.classes.trucks
    Users = models.Base.classes.users
    
    query = db.query(Updates, Trucks.name, Users.full_name).join(
        Trucks, Updates.truck_id == Trucks.ID
    ).join(
        Users, Updates.admin_id == Users.ID
    )
    
    # Apply filters
    if truck_id:
        query = query.filter(Updates.truck_id == truck_id)
    
    if start_date:
        query = query.filter(Updates.created_at >= start_date)
    if end_date:
        query = query.filter(Updates.created_at <= end_date)
    
    if search:
        query = query.filter(
            or_(
                Updates.item_name.like(f'%{search}%'),
                Updates.description.like(f'%{search}%')
            )
        )
    
    results = query.order_by(Updates.created_at.desc()).all()
    
    updates_list = []
    for update, truck_name, admin_name in results:
        updates_list.append({
            "id": update.ID,
            "truck_id": update.truck_id,
            "truck_name": truck_name,
            "admin_id": update.admin_id,
            "admin_name": admin_name,
            "item_name": update.item_name,
            "description": update.description,
            "created_at": update.created_at.strftime("%Y-%m-%d %H:%M:%S") if update.created_at else ""
        })
    
    return updates_list

@app.post("/admin/updates")
def admin_create_update(
    truck_id: int,
    item_name: str,
    description: str,
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Create new maintenance update"""
    Updates = models.Base.classes.updates
    
    new_update = Updates(
        truck_id=truck_id,
        admin_id=current_user['id'],
        item_name=item_name,
        description=description
    )
    
    db.add(new_update)
    db.commit()
    db.refresh(new_update)
    
    return {"message": "تم إضافة التحديث بنجاح", "id": new_update.ID}

@app.get("/admin/products")
def admin_get_products(
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get all products with their group information"""
    Products = models.Base.classes.products
    Groups = models.Base.classes.groups
    
    results = db.query(Products, Groups).outerjoin(
        Groups, Groups.ID == Products.group_id
    ).all()
    
    return [{
        "id": p.ID,
        "product_name": p.product_name,
        "group_id": p.group_id or None,
        "group_min_temperature": g.min_temperature if g else None,
        "group_max_temperature": g.max_temperature if g else None,
        "group_min_humidity": g.min_humidity if g else None,
        "group_max_humidity": g.max_humidity if g else None
    } for p, g in results]

class AdminSecurityLimitsRequest(BaseModel):
    shipment_number: str
    min_temperature: Optional[float] = None
    max_temperature: Optional[float] = None
    min_humidity: Optional[int] = None
    max_humidity: Optional[int] = None
    door_open_duration: int = 60
    door_open_count: int = 5

@app.get("/admin/shipment-info/{shipment_number}")
def get_shipment_info(
    shipment_number: str,
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Get shipment details including products and auto-calculated security limits"""
    Trips = models.Base.classes.trips
    Products = models.Base.classes.products
    Groups = models.Base.classes.groups
    UserTrucks = models.Base.classes.user_trucks
    Trucks = models.Base.classes.trucks
    SecurityLimits = models.Base.classes.security_limits
    
    # Get trip
    trip = db.query(Trips).filter(Trips.shipment_number == shipment_number).first()
    
    if not trip:
        raise HTTPException(status_code=404, detail="رقم الشحنة غير موجود")
    
    # Get truck info
    user_truck = db.query(UserTrucks, Trucks).join(
        Trucks, UserTrucks.truck_id == Trucks.ID
    ).filter(UserTrucks.ID == trip.user_truck_id).first()
    
    truck_id = user_truck[1].ID if user_truck else None
    truck_name = user_truck[1].name if user_truck else "Unknown"
    
    # Parse product_ids from JSON
    product_ids = []
    if trip.product_ids:
        try:
            product_ids = json.loads(trip.product_ids)
        except:
            product_ids = []
    
    # Get products details
    products_info = []
    if product_ids:
        products = db.query(Products, Groups).outerjoin(
            Groups, Products.group_id == Groups.ID
        ).filter(Products.ID.in_(product_ids)).all()
        
        products_info = [{
            "id": p.ID,
            "name": p.product_name,
            "group_min_temp": g.min_temperature if g else None,
            "group_max_temp": g.max_temperature if g else None,
            "group_min_humidity": g.min_humidity if g else None,
            "group_max_humidity": g.max_humidity if g else None
        } for p, g in products]
    
    # Auto-calculate most restrictive limits
    auto_limits = {
        "min_temperature": None,
        "max_temperature": None,
        "min_humidity": None,
        "max_humidity": None
    }
    
    if products_info:
        temps_min = [p["group_min_temp"] for p in products_info if p["group_min_temp"] is not None]
        temps_max = [p["group_max_temp"] for p in products_info if p["group_max_temp"] is not None]
        hums_min = [p["group_min_humidity"] for p in products_info if p["group_min_humidity"] is not None]
        hums_max = [p["group_max_humidity"] for p in products_info if p["group_max_humidity"] is not None]
        
        if temps_min:
            auto_limits["min_temperature"] = max(temps_min)  # Most restrictive (highest min)
        if temps_max:
            auto_limits["max_temperature"] = min(temps_max)  # Most restrictive (lowest max)
        if hums_min:
            auto_limits["min_humidity"] = max(hums_min)
        if hums_max:
            auto_limits["max_humidity"] = min(hums_max)
    
    # Check if security limits already exist
    existing_limits = db.query(SecurityLimits).filter(
        SecurityLimits.shipment_number == shipment_number
    ).first()
    
    return {
        "shipment_number": shipment_number,
        "truck_id": truck_id,
        "truck_name": truck_name,
        "status": trip.status,
        "products": products_info,
        "auto_calculated_limits": auto_limits,
        "existing_limits": {
            "min_temperature": existing_limits.min_temperature if existing_limits else None,
            "max_temperature": existing_limits.max_temperature if existing_limits else None,
            "min_humidity": existing_limits.min_humidity if existing_limits else None,
            "max_humidity": existing_limits.max_humidity if existing_limits else None,
            "door_open_duration": existing_limits.door_open_duration if existing_limits else 60,
            "door_open_count": existing_limits.door_open_count if existing_limits else 5
        } if existing_limits else None
    }

@app.post("/admin/save-security-limits")
def admin_save_security_limits(
    data: AdminSecurityLimitsRequest,
    db: Session = Depends(get_db),
    current_user=Depends(require_admin)
):
    """Admin: Save security limits for a specific shipment"""
    Trips = models.Base.classes.trips
    Products = models.Base.classes.products
    Groups = models.Base.classes.groups
    SecurityLimits = models.Base.classes.security_limits
    
    # Verify shipment exists
    trip = db.query(Trips).filter(Trips.shipment_number == data.shipment_number).first()
    
    if not trip:
        raise HTTPException(status_code=404, detail="رقم الشحنة غير موجود")
    
    # If limits not provided, auto-calculate from products
    min_temp = data.min_temperature
    max_temp = data.max_temperature
    min_hum = data.min_humidity
    max_hum = data.max_humidity
    
    if None in [min_temp, max_temp, min_hum, max_hum]:
        # Parse product_ids
        product_ids = []
        if trip.product_ids:
            try:
                product_ids = json.loads(trip.product_ids)
            except:
                pass
        
        if product_ids:
            # Get products with groups
            products = db.query(Products, Groups).outerjoin(
                Groups, Products.group_id == Groups.ID
            ).filter(Products.ID.in_(product_ids)).all()
            
            temps_min = [g.min_temperature for p, g in products if g and g.min_temperature is not None]
            temps_max = [g.max_temperature for p, g in products if g and g.max_temperature is not None]
            hums_min = [g.min_humidity for p, g in products if g and g.min_humidity is not None]
            hums_max = [g.max_humidity for p, g in products if g and g.max_humidity is not None]
            
            if min_temp is None and temps_min:
                min_temp = max(temps_min)
            if max_temp is None and temps_max:
                max_temp = min(temps_max)
            if min_hum is None and hums_min:
                min_hum = max(hums_min)
            if max_hum is None and hums_max:
                max_hum = min(hums_max)
    
    # Validate limits
    if min_temp is not None and max_temp is not None and min_temp >= max_temp:
        raise HTTPException(status_code=400, detail="الحرارة الدنيا يجب أن تكون أقل من العليا")
    
    if min_hum is not None and max_hum is not None and min_hum >= max_hum:
        raise HTTPException(status_code=400, detail="الرطوبة الدنيا يجب أن تكون أقل من العليا")
    
    # Require all limits to be set
    if None in [min_temp, max_temp, min_hum, max_hum]:
        raise HTTPException(
            status_code=400, 
            detail="لا يمكن تحديد الحدود تلقائياً. الرجاء إدخال جميع القيم يدوياً"
        )
    
    # Check if limits already exist
    existing_limit = db.query(SecurityLimits).filter(
        SecurityLimits.shipment_number == data.shipment_number
    ).first()
    
    if existing_limit:
        # Update existing
        existing_limit.min_temperature = min_temp
        existing_limit.max_temperature = max_temp
        existing_limit.min_humidity = min_hum
        existing_limit.max_humidity = max_hum
        existing_limit.door_open_duration = data.door_open_duration
        existing_limit.door_open_count = data.door_open_count
    else:
        # Create new
        new_limit = SecurityLimits(
            shipment_number=data.shipment_number,
            min_temperature=min_temp,
            max_temperature=max_temp,
            min_humidity=min_hum,
            max_humidity=max_hum,
            door_open_duration=data.door_open_duration,
            door_open_count=data.door_open_count
        )
        db.add(new_limit)
    
    db.commit()
    
    # Auto-insert update record for security limits
    Updates = models.Base.classes.updates
    Trucks = models.Base.classes.trucks
    UserTrucks = models.Base.classes.user_trucks
    
    # Get truck_id from trip via user_truck_id
    try:
        user_truck = db.query(UserTrucks).filter(UserTrucks.ID == trip.user_truck_id).first()
        if user_truck:
            truck_id = user_truck.truck_id
            truck = db.query(Trucks).filter(Trucks.ID == truck_id).first()
            truck_name = truck.name if truck else f"شاحنة {truck_id}"
            
            action_type = "تحديث" if existing_limit else "تعيين"
            
            update_record = Updates(
                truck_id=truck_id,
                admin_id=current_user.ID,
                item_name="تحديد حدود الأمان",
                description=f"تم {action_type} حدود الأمان للشحنة {data.shipment_number} - الحرارة: {min_temp}°-{max_temp}° - الرطوبة: {min_hum}%-{max_hum}%"
            )
            db.add(update_record)
            db.commit()
    except Exception as e:
        # Log the error but don't fail the main operation
        print(f"Error inserting update record: {e}")
    
    return {
        "status": "success",
        "message": "تم حفظ حدود الأمان بنجاح",
        "shipment_number": data.shipment_number,
        "limits": {
            "min_temperature": min_temp,
            "max_temperature": max_temp,
            "min_humidity": min_hum,
            "max_humidity": max_hum,
            "door_open_duration": data.door_open_duration,
            "door_open_count": data.door_open_count
        }
    }

# ============================================================
# ✅ Export Endpoints (Excel/PDF)
# ============================================================
@app.get("/export-excel-reports")
def export_excel_reports(
    shipment_number: str = Query(None),
    start_date: str = Query(None),
    end_date: str = Query(None),
    search: str = Query(None),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Export reports to Excel"""
    Reports = models.Base.classes.reports
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    query = db.query(Reports).join(
        Trips, Reports.shipment_number == Trips.shipment_number
    ).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(UserTrucks.user_id == current_user.ID)
    
    if shipment_number:
        query = query.filter(Reports.shipment_number == shipment_number)
    
    query = apply_filters(query, Reports, start_date, end_date, search)
    results = query.order_by(Reports.full_date.desc()).all()
    
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "التقارير"
    
    ws.append([
        "التاريخ", "رقم الشحنة", "الحرارة", "الرطوبة",
        "حالة الباب", "غاز MQ9", "غاز MQ135", "خط العرض", "خط الطول"
    ])
    
    for r in results:
        ws.append([
            r.full_date.strftime("%Y-%m-%d %H:%M:%S") if r.full_date else "",
            r.shipment_number or "",
            str(r.temperature) if r.temperature else "",
            str(r.humidity) if r.humidity else "",
            r.door_condition or "",
            str(r.mq9_gas) if r.mq9_gas is not None else "",
            str(r.mq135_gas) if r.mq135_gas is not None else "",
            str(r.latitude) if r.latitude else "",
            str(r.longitude) if r.longitude else ""
        ])
    
    stream = io.BytesIO()
    wb.save(stream)
    stream.seek(0)
    
    return StreamingResponse(
        stream,
        media_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        headers={'Content-Disposition': 'attachment; filename="reports_export.xlsx"'}
    )

@app.get("/export-excel-alerts")
def export_excel_alerts(
    shipment_number: str = Query(None),
    start_date: str = Query(None),
    end_date: str = Query(None),
    search: str = Query(None),
    db: Session = Depends(get_db),
    current_user=Depends(get_current_user)
):
    """Export alerts to Excel"""
    Alerts = models.Base.classes.alerts
    Trips = models.Base.classes.trips
    UserTrucks = models.Base.classes.user_trucks
    
    query = db.query(Alerts).join(
        Trips, Alerts.shipment_number == Trips.shipment_number
    ).join(
        UserTrucks, Trips.user_truck_id == UserTrucks.ID
    ).filter(UserTrucks.user_id == current_user.ID)
    
    if shipment_number:
        query = query.filter(Alerts.shipment_number == shipment_number)
    
    query = apply_filters(query, Alerts, start_date, end_date, search)
    results = query.order_by(Alerts.full_date.desc()).all()
    
    wb = openpyxl.Workbook()
    ws = wb.active
    ws.title = "التنبيهات"
    
    ws.append([
        "التاريخ", "رقم الشحنة", "سبب التنبيه",
        "المدة (ثانية)", "خط العرض", "خط الطول"
    ])
    
    for r in results:
        ws.append([
            r.full_date.strftime("%Y-%m-%d %H:%M:%S") if r.full_date else "",
            r.shipment_number or "",
            r.alert_reason or "",
            str(r.duration) if r.duration is not None else "جاري...",
            str(r.latitude) if r.latitude else "",
            str(r.longitude) if r.longitude else ""
        ])
    
    stream = io.BytesIO()
    wb.save(stream)
    stream.seek(0)
    
    return StreamingResponse(
        stream,
        media_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        headers={'Content-Disposition': 'attachment; filename="alerts_export.xlsx"'}
    )

# ============================================================
# ✅ Startup Event
# ============================================================
@app.on_event("startup")
async def startup_event():
    print("🚀 SafeChain API - Normalized Database Version 2.0")
    print("✅ Server started successfully")

