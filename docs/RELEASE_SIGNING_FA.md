# امضای ثابت نسخه اندروید

بدون امضای ثابت، GitHub Actions در هر اجرا نسخه debug را با یک کلید تازه امضا می‌کند. نتیجه:
- نسخه جدید روی نسخه قبلی نصب نمی‌شود و باید اول برنامه را حذف کنید.
- حذف برنامه، پیش‌نویس‌ها و فهرست بایگانی را هم پاک می‌کند.

ساخت اندروید در CI به این صورت کار می‌کند:
- اگر چهار Secret زیر در مخزن تنظیم شده باشد، نسخه **release** با کلید شما امضا و با نام `PayamYar-release.apk` منتشر می‌شود.
- اگر نباشد، همان نسخه debug قبلی با نام `PayamYar-debug.apk` ساخته می‌شود.

کلید و رمزها هرگز داخل فایل‌های مخزن ذخیره نمی‌شوند. فقط در Secrets رمزگذاری‌شده GitHub نگهداری می‌شوند و فایل کلید پس از ساخت از روی سرور حذف می‌شود.

## ۱. ساخت کلید (یک بار، روی کامپیوتر خودتان)
به JDK نیاز دارید (ابزار `keytool`):

```sh
keytool -genkeypair -v -keystore payamyar-release.jks -keyalg RSA -keysize 4096 -validity 10000 -alias payamyar
```

**از فایل `payamyar-release.jks` و رمزها پشتیبان امن بگیرید.** اگر گم شوند، هیچ به‌روزرسانی بعدی روی نسخه نصب‌شده کاربران قابل نصب نیست. این فایل را هرگز commit نکنید (در `.gitignore` قرار دارد).

## ۲. تبدیل کلید به متن base64
ویندوز (PowerShell):

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("payamyar-release.jks")) | Set-Clipboard
```

لینوکس/مک:

```sh
base64 -w0 payamyar-release.jks
```

## ۳. افزودن Secrets در GitHub
مخزن → Settings → Secrets and variables → Actions → New repository secret:

| نام | مقدار |
|---|---|
| `PAYAMYAR_KEYSTORE_BASE64` | متن base64 مرحله ۲ |
| `PAYAMYAR_KEYSTORE_PASSWORD` | رمز keystore |
| `PAYAMYAR_KEY_ALIAS` | `payamyar` (یا alias انتخابی شما) |
| `PAYAMYAR_KEY_PASSWORD` | رمز کلید (اگر جدا تعیین نکرده‌اید، همان رمز keystore) |

## ۴. اولین نصب
نسخه release امضای متفاوتی با نسخه‌های debug قبلی دارد، پس **یک بار** باید نسخه debug را حذف و نسخه release را نصب کنید. از آن به بعد، نسخه‌های بعدی بدون حذف روی هم نصب می‌شوند.
