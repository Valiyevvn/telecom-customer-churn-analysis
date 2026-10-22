"""
Addım 9: Sintetik abunəçi datası yaradır və Oracle-dakı CUSTOMERS cədvəlinə yükləyir.
Qeyd: Bütün data uydurmadır, Azercell Telecom-un real datası deyil.
"""
import numpy as np
import pandas as pd
from db import get_connection
 
# ---------------------------------------------------------------
# 1. Parametrlər
# ---------------------------------------------------------------
N_CUSTOMERS = 5000
START_MONTH = "2024-01-01"
END_MONTH = "2026-09-01"
rng = np.random.default_rng(42)   # eyni "seed" = hər dəfə eyni data
 
# ---------------------------------------------------------------
# 2. Qoşulma tarixləri: yavaş artım + mövsümilik
# ---------------------------------------------------------------
months = pd.date_range(START_MONTH, END_MONTH, freq="MS")
weights = []
for i, m in enumerate(months):
    w = 1 + i * 0.02              # hər ay biraz çox yeni abunəçi
    if m.month in (9, 12):        # sentyabr və dekabr kampaniyaları
        w *= 1.4
    elif m.month in (1, 2):       # yanvar-fevral sakit dövr
        w *= 0.8
    weights.append(w)
weights = np.array(weights) / np.sum(weights)
 
month_idx = rng.choice(len(months), size=N_CUSTOMERS, p=weights)
day_offset = rng.integers(0, 28, size=N_CUSTOMERS)
signup_dates = months[month_idx] + pd.to_timedelta(day_offset, unit="D")
 
# ---------------------------------------------------------------
# 3. Demoqrafiya və cəlb olunma kanalı
# ---------------------------------------------------------------
cities = ["Baku", "Sumgait", "Ganja", "Lankaran", "Mingachevir",
          "Shirvan", "Shaki", "Guba", "Khachmaz", "Masalli"]
city_p = [0.55, 0.09, 0.08, 0.04, 0.04, 0.03, 0.04, 0.04, 0.05, 0.04]
channels = ["Store", "Online", "Dealer", "Promo campaign"]
channel_p = [0.40, 0.25, 0.20, 0.15]
 
customers = pd.DataFrame({
    "signup_date": signup_dates,
    "gender": rng.choice(["Male", "Female"], size=N_CUSTOMERS),
    "age": np.clip(rng.normal(34, 11, N_CUSTOMERS), 18, 70).round(),
    "city": rng.choice(cities, size=N_CUSTOMERS, p=city_p),
    "acquisition_channel": rng.choice(channels, size=N_CUSTOMERS, p=channel_p),
})
customers["age"] = customers["age"].astype("Int64")
 
# Real data heç vaxt tam olmur: abunəçilərin ~3%-nin yaşı boşdur
customers.loc[rng.random(N_CUSTOMERS) < 0.03, "age"] = pd.NA
 
# ID-lər qoşulma tarixinə görə artsın (real sistemlərdə olduğu kimi)
customers = customers.sort_values("signup_date").reset_index(drop=True)
customers.insert(0, "customer_id", np.arange(100001, 100001 + N_CUSTOMERS))
 
# ---------------------------------------------------------------
# 4. Oracle-a yükləmək
# ---------------------------------------------------------------
conn = get_connection()
cur = conn.cursor()
 
# Skript təkrar işə salına bilsin deyə köhnə datanı silirik
# (əvvəlcə "uşaq" cədvəllər, sonra customers - foreign key-lərə görə)
for table in ["usage_monthly", "payments", "subscriptions", "customers"]:
    cur.execute(f"DELETE FROM {table}")
 
# pandas dəyərlərini Oracle-ın başa düşdüyü Python tiplərinə çeviririk
rows = [
    tuple(None if pd.isna(v) else v for v in row)
    for row in customers.astype(object).itertuples(index=False)
]
 
cur.executemany(
    """INSERT INTO customers
           (customer_id, signup_date, gender, age, city, acquisition_channel)
       VALUES (:1, :2, :3, :4, :5, :6)""",
    rows,
)
conn.commit()
 
# ---------------------------------------------------------------
# 5. Yoxlama: bazada həqiqətən nə var?
# ---------------------------------------------------------------
cur.execute("""SELECT COUNT(*), MIN(signup_date), MAX(signup_date),
                      COUNT(*) - COUNT(age)
               FROM customers""")
total, first_date, last_date, missing_age = cur.fetchone()
print(f"Yüklənən abunəçi sayı : {total}")
print(f"İlk qoşulma tarixi    : {first_date:%Y-%m-%d}")
print(f"Son qoşulma tarixi    : {last_date:%Y-%m-%d}")
print(f"Yaşı boş olanlar      : {missing_age}")
 
cur.close()
conn.close()