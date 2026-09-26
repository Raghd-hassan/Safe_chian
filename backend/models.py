from sqlalchemy.ext.automap import automap_base
from database import engine

Base = automap_base()

Base.prepare(
    engine,
    reflect=True
)
print("الجداول المكتشفة هي:", Base.classes.keys())
print("تم جلب الجداول بنجاح")