from pydantic import BaseModel, EmailStr, field_validator, model_validator
from typing import Optional, List
import re

# دالة التحقق من كلمة المرور
def validate_pass(password: str) -> str:
    if len(password) < 8:
        raise ValueError('كلمة المرور 8 أحرف على الأقل')
    if not re.search(r"[A-Z]", password):
        raise ValueError('حرف كبير واحد على الأقل (A-Z)')
    if not re.search(r"[a-z]", password):
        raise ValueError('حرف صغير واحد على الأقل (a-z)')
    if not re.search(r"\d", password):
        raise ValueError('رقم واحد على الأقل (0-9)')
    if not re.search(r"[ !@#$%^&*()_+\-=\[\]{};':\"\\|,.<>\/?]", password):
        raise ValueError('رمز خاص واحد على الأقل (! @ #)')
    return password

# ============================================================
# نماذج المصادقة (Authentication)
# ============================================================

class UserCreate(BaseModel):
    full_name: str
    email: EmailStr
    phone: str
    password: str
    confirm_password: str

    @field_validator('password')
    @classmethod
    def validate_password_strength(cls, v):
        return validate_pass(v)

    @model_validator(mode='after')
    def check_passwords_match(self):
        if self.password != self.confirm_password:
            raise ValueError('كلمتا المرور غير متطابقتين')
        return self

class UserLogin(BaseModel):
    email: EmailStr
    password: str

class VerifyCode(BaseModel):
    email: EmailStr
    code: str

class EmailRequest(BaseModel):
    email: EmailStr

class ResetPassword(BaseModel):
    email: EmailStr
    code: str
    new_password: str
    confirm_password: str

    @field_validator('new_password')
    @classmethod
    def validate_password_strength(cls, v):
        return validate_pass(v)

    @model_validator(mode='after')
    def check_passwords_match(self):
        if self.new_password != self.confirm_password:
            raise ValueError('كلمتا المرور غير متطابقتين')
        return self

class UserUpdate(BaseModel):
    full_name: str | None = None
    email: str | None = None
    phone: str | None = None
    password: str | None = None

    @field_validator('password')
    @classmethod
    def validate_password_strength(cls, v):
        if v:
            return validate_pass(v)
        return v

class UpdateRoleRequest(BaseModel):
    role: str

# ============================================================
# نماذج الشاحنات (Trucks)
# ============================================================

class TruckCreate(BaseModel):
    name: str

class AssignTruckRequest(BaseModel):
    user_id: int
    truck_id: int

# ============================================================
# نماذج الرحلات (Trips)
# ============================================================

class StartTripRequest(BaseModel):
    truck_id: int
    product_ids: List[int] = []  # Array of product IDs

class EndTripRequest(BaseModel):
    shipment_number: str

# ============================================================
# نماذج حدود الأمان (Security Limits)
# ============================================================

class SecurityLimitsRequest(BaseModel):
    shipment_number: str
    min_temperature: float
    max_temperature: float
    min_humidity: int
    max_humidity: int
    door_open_duration: int  # in seconds
    door_open_count: int

# ============================================================
# نماذج التقارير (Reports)
# ============================================================

class CreateReportRequest(BaseModel):
    shipment_number: str
    temperature: float
    humidity: float  # Changed from int to float to match DB
    door_condition: str  # OPEN or CLOSED
    mq9_gas: float | None = None
    mq135_gas: float | None = None
    latitude: float | None = None
    longitude: float | None = None

    @field_validator('door_condition')
    @classmethod
    def validate_door_condition(cls, v):
        if v not in ('OPEN', 'CLOSED'):
            raise ValueError('door_condition must be OPEN or CLOSED')
        return v

class ReportResponse(BaseModel):
    id: int
    shipment_number: str
    temperature: float
    humidity: float
    door_condition: str
    mq9_gas: float | None = None
    mq135_gas: float | None = None
    latitude: float | None = None
    longitude: float | None = None
    full_date: str
    
    class Config:
        from_attributes = True

# ============================================================
# نماذج التنبيهات (Alerts)
# ============================================================

class CreateAlertRequest(BaseModel):
    shipment_number: str
    alert_reason: str
    duration: int | None = None  # Duration in seconds, None if ongoing
    latitude: float | None = None
    longitude: float | None = None

class AlertResponse(BaseModel):
    id: int
    shipment_number: str
    alert_reason: str
    duration: int | None = None
    latitude: float | None = None
    longitude: float | None = None
    full_date: str
    
    class Config:
        from_attributes = True

# ============================================================
# نماذج المنتجات (Products)
# ============================================================

class ProductCreate(BaseModel):
    product_name: str
    group_id: int | None = None

class ProductResponse(BaseModel):
    id: int
    product_name: str
    group_id: int | None = None
    group_min_temperature: float | None = None
    group_max_temperature: float | None = None
    group_min_humidity: int | None = None
    group_max_humidity: int | None = None
    
    class Config:
        from_attributes = True

# ============================================================
# نماذج المجموعات (Groups)
# ============================================================

class GroupCreate(BaseModel):
    min_temperature: float
    max_temperature: float
    min_humidity: int
    max_humidity: int

# ============================================================
# نماذج الحساسات (Sensors)
# ============================================================

class SensorCreate(BaseModel):
    truck_id: int
    serial_number: str
    sensor_type: str  # Temperature, Humidity, Gas, Door
    status: str = 'active'  # active, inactive, maintenance

class SensorUpdate(BaseModel):
    status: str  # active, inactive, maintenance

# ============================================================
# نماذج التحديثات (Updates)
# ============================================================

class UpdateCreate(BaseModel):
    truck_id: int
    item_name: str
    description: str | None = None
