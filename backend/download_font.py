# download_font.py
import os
import urllib.request

# إنشاء مجلد fonts
font_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts")
os.makedirs(font_dir, exist_ok=True)

# روابط التحميل المباشرة من GitHub
fonts = {
    "Amiri-Regular.ttf": "https://github.com/aliftype/amiri/raw/main/Amiri-Regular.ttf",
    "Amiri-Bold.ttf": "https://github.com/aliftype/amiri/raw/main/Amiri-Bold.ttf"
}

for name, url in fonts.items():
    path = os.path.join(font_dir, name)
    if os.path.exists(path):
        print(f"✅ {name} موجود بالفعل")
    else:
        print(f"⬇️ جاري تحميل {name}...")
        try:
            urllib.request.urlretrieve(url, path)
            print(f"✅ تم تحميل {name} بنجاح إلى: {path}")
        except Exception as e:
            print(f"❌ فشل تحميل {name}: {e}")

print("\n📁 مسار الخطوط:", font_dir)