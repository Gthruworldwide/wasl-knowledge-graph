# finance_lab

بيئة Python محلية للتحليل المالي والذهب والمحافظ، مستقلة عن تطبيق Flutter `wasl`.
لا تحتوي على أي مفتاح API حقيقي؛ ضع مفاتيحك في `.env` فقط إن احتجتها.

## الترتيب المطلوب

```powershell
cd E:\000000000\finance_lab
uv sync --python 3.13
uv run pytest
uv run python scripts\quickstart.py
```

## ما الذي تم تثبيته؟

- **الأساس:** numpy, pandas, scipy, statsmodels, matplotlib, requests, python-dotenv
- **بيانات السوق:** yfinance, yahooquery, akshare, ccxt, nasdaqdatalink, twelvedata, finnhub-python
- **تحليل فني:** ta, pandas-ta, mplfinance, backtrader
- **محافظ وثروة:** PyPortfolioOpt, riskfolio-lib, QuantStats, ffn
- **اختبارات:** pytest

المجموعة الثقيلة اختيارية لتجنب تعقيد التثبيت على Windows:

```powershell
uv sync --python 3.13 --extra heavy   # فقط OpenBB (vectorbt يأتي مع riskfolio-lib)
```

`TA-Lib` الأصلي متروك خارج التثبيت لأنه يحتاج مكتبة C على Windows؛ استخدم `ta` بديلاً عنه.

## المخرجات

بعد تشغيل `quickstart.py` تجد في `output/`:

- `prices.csv` — أسعار الإغلاق المعدّلة + أعمدة `source_kind` / `source` / `fetched_at` على كل صف
- `indicators.csv` — RSI / SMA / MACD
- `weights.csv` — أوزان محفظة max-Sharpe
- `quotes.csv` — أحدث أسعار الأصول ومعها نوع المصدر لكل صف
- `gold.csv` — الذهب (futures / ETF) والفضة؛ رمز `XAUUSD=X` لا يوفره Yahoo في كل المناطق لذا استخدمنا `GC=F` و`GLD`
- `provenance.json` — نوع المصدر والمصدر ووقت الجلب وسبب الرجوع للبديل
- `equal_weight_tearsheet.html` — تقرير QuantStats (يُكتب فقط للبيانات الحقيقية)
- `prices_live.csv` + `prices_live.meta.json` — آخر لقطة حقيقية تُستخدم كـ `cached` عند تعذّر الاتصال

## وسم البيانات (مطابق لـ WASL_FINANCIAL_AI_SPEC.md)

كل صف مُوسوم بأحد الأنواع: `live` | `cached` | `synthetic` | `manual`.

ترتيب الحل: `yfinance` حيّ ← لقطة محلية حقيقية `cached` ← بيانات تجريبية `synthetic`. لا تُخلط المصادر داخل مجموعة واحدة أبداً. إذا كانت النتيجة `synthetic` فيطبع السكربت تحذيراً صريحاً ويُمنع كتابة تقرير الأداء (`SyntheticDataError`) حتى لا تبدو الأرقام التجريبية كأنها نتائج مالية حقيقية.

في الاختبارات يمكن فرض المسار دون إنترنت:

```python
dataset = load_prices(["GLD", "SPY"], allow_live=False, allow_cache=False)
assert dataset.kind is SourceKind.SYNTHETIC
```

## CI (GitHub Actions / Buildkite)

الملف `.github/workflows/ci.yml` يشغّل عند `push` و`pull_request`:

1. تثبيت `uv` وPython 3.13
2. `uv sync --python 3.13 --locked` (يستخدم `uv.lock` المُثبّت)
3. `uv run pytest -q`
4. `uv run python scripts/quickstart.py` (جلب بيانات السوق وبناء المخرجات)
5. رفع مجلد `output/` كـ artifact

الملف يستخدم actions عامة فقط (`actions/checkout`, `astral-sh/setup-uv`, `actions/upload-artifact`) ولا يحتاج أي secrets لأن المشروع لا يستخدم مفاتيح API حقيقية.

**ملاحظة Buildkite:** ميزة GitHub Actions Compatibility (public preview) تشغّل هذا الملف كما هو بدون plugin أو pipeline YAML، لكنها **لا تدعم أحداث `schedule`** ولا `workflow_dispatch` المستقل. إذا احتجت جدولة لاحقاً، استخدم Buildkite cron أصلي أو GitHub Actions cron. كما أن `E:\000000000` ليس مستودع Git حالياً؛ يجب إنشاء مستودع GitHub ورفع مجلد `finance_lab` كجذر له قبل ربطه بـ Buildkite.

عند تغيير `pyproject.toml` حدّث القفل محلياً ثم التزامه:

```powershell
uv lock
```
