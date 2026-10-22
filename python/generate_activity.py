"""
Addım 10: Abunəliklər, ödənişlər və aylıq istifadə datasını simulyasiya edir
və Oracle-a yükləyir. Abunəçilər və tariflər bazadan oxunur.
Qeyd: Bütün data uydurmadır, Azercell Telecom-un real datası deyil.
"""
import math
from datetime import datetime, timedelta
 
import numpy as np
import oracledb
from db import get_connection
 
rng = np.random.default_rng(2026)
LAST_MONTH = datetime(2026, 9, 1)            # müşahidə dövrünün son ayı
PRICE_UP_FROM = datetime(2025, 7, 1)         # prepaid tariflərə 20% qiymət artımı
PRICE_UP_FACTOR = 1.20
 
 
def month_start(d):
    return datetime(d.year, d.month, 1)
 
 
def add_months(d, n):
    y, m = divmod(d.month - 1 + n, 12)
    return datetime(d.year + y, m + 1, 1)
 
 
def month_end(d):
    return add_months(d, 1) - timedelta(days=1)
 
 
# ---------------------------------------------------------------
# 1. Abunəçiləri və tarifləri BAZADAN oxuyuruq
# ---------------------------------------------------------------
conn = get_connection()
cur = conn.cursor()
 
cur.execute("""SELECT plan_id, plan_type, monthly_fee, data_gb_included, minutes_included
               FROM plans""")
plans = {r[0]: {"type": r[1], "fee": float(r[2]), "gb": r[3], "min": r[4]}
         for r in cur.fetchall()}
 
cur.execute("""SELECT customer_id, signup_date, age, city, acquisition_channel
               FROM customers ORDER BY customer_id""")
customers = cur.fetchall()
print(f"Bazadan oxunan abunəçi: {len(customers)}, tarif: {len(plans)}")
 
# ---------------------------------------------------------------
# 2. Hər abunəçinin həyatını ay-ay simulyasiya edirik
# ---------------------------------------------------------------
subscriptions, payments, usage = [], [], []
sub_id, pay_id = 1, 1
NEXT_PLAN = {1: 2, 2: 3, 4: 5, 5: 6}         # tarif artırma (upgrade) yolu
 
for cust_id, signup, age, city, channel in customers:
    # İlk tarif seçimi: gənclər və onlayn gələnlər daha çox prepaid seçir
    p = np.array([0.22, 0.25, 0.15, 0.15, 0.15, 0.08])
    if age is not None and age < 25:
        p *= [1.6, 1.5, 1.2, 0.5, 0.5, 0.3]
    if channel == "Promo campaign":
        p *= [2.0, 1.2, 0.8, 0.6, 0.6, 0.4]
    if channel == "Online":
        p *= [0.8, 1.4, 1.4, 0.8, 1.0, 1.0]
    plan_id = int(rng.choice([1, 2, 3, 4, 5, 6], p=p / p.sum()))
 
    # Abunəçinin dəyişməz xüsusiyyətləri
    demand_gb = plans[plan_id]["gb"] * float(np.clip(rng.lognormal(-0.3, 0.35), 0.1, 2.0))
    complaint_rate = 0.06 if city == "Baku" else 0.22    # regionlarda şəbəkə zəifdir
    fail_base = 0.06 if plans[plan_id]["type"] == "PREPAID" else 0.025
    fail_rate = float(np.clip(fail_base * rng.lognormal(0, 0.6), 0, 0.5))
    pay_day = min(signup.day, 28)
 
    start = signup
    month = month_start(signup)
    tenure = 0
    last_complaints, last_failed, last_ratio = 0, False, 1.0
    churned = False
 
    while month <= LAST_MONTH:
        plan = plans[plan_id]
 
        # --- 2a. Ayın əvvəlində: abunəçi gedirmi? (keçən ayın siqnallarına görə)
        if tenure > 0:
            logit = -4.3
            logit += 0.8 if tenure < 3 else 0
            logit += 0.5 if plan["type"] == "PREPAID" else 0
            logit += 1.3 if channel == "Promo campaign" and tenure in (3, 4) else 0
            logit += 0.45 * min(last_complaints, 3)
            logit += 1.0 if last_failed else 0
            logit += 0.9 if last_ratio < 0.3 else 0
            logit += 0.3 if age is not None and age < 25 else 0
            logit -= 0.5 if plan_id in (5, 6) else 0
            if plan["type"] == "PREPAID" and PRICE_UP_FROM <= month < add_months(PRICE_UP_FROM, 3):
                logit += 0.9                                  # qiymət artımından sonrakı şok
            if rng.random() < 1 / (1 + math.exp(-logit)):
                reasons = {"Moved to competitor": 3.0, "Price": 2.0,
                           "Relocation": 0.7, "No longer needed": 1.0,
                           "Network quality": 0.3 + 3.0 * last_complaints,
                           "Payment issues": 3.0 if last_failed else 0.1}
                if plan["type"] == "PREPAID" and month >= PRICE_UP_FROM:
                    reasons["Price"] += 2.5
                if channel == "Promo campaign" and tenure in (3, 4):
                    reasons["Price"] += 3.0
                names = list(reasons)
                w = np.array(list(reasons.values()))
                reason = str(rng.choice(names, p=w / w.sum()))
                if rng.random() < 0.08:
                    reason = None                             # operator səbəbi qeyd etməyib
                end = month + timedelta(days=int(rng.integers(0, 27)))
                subscriptions.append((sub_id, cust_id, plan_id, start, end, "CANCELLED", reason))
                sub_id += 1
                churned = True
                break
 
        # --- 2b. Bu ayın istifadəsi
        demand_gb *= float(rng.lognormal(-0.01, 0.12))     # istifadə zamanla dəyişir
        data_used = max(0.0, demand_gb * float(rng.uniform(0.85, 1.15)))
        ratio = data_used / plan["gb"]
        complaints = int(rng.poisson(complaint_rate))
        voice = int(plan["min"] * min(ratio, 1.5) * float(rng.uniform(0.3, 0.8)))
        sms = int(rng.poisson(6))
 
        # --- 2c. Bu ayın ödənişi
        pay_date = month.replace(day=pay_day)
        if month == month_start(signup):
            pay_date = signup
        fee = plan["fee"]
        if plan["type"] == "PREPAID" and month >= PRICE_UP_FROM:
            fee = round(fee * PRICE_UP_FACTOR, 2)
        failed = bool(rng.random() < fail_rate)
        payments.append((pay_id, sub_id, pay_date, fee, "FAILED" if failed else "SUCCESS"))
        pay_id += 1
 
        tickets = int(rng.poisson(0.08 + 0.5 * complaints + (0.6 if failed else 0)))
        usage.append((cust_id, month, round(data_used, 2), voice, sms, tickets, complaints))
 
        # --- 2d. Tarif artırma: limiti daim aşanlar bəzən böyük tarifə keçir
        if ratio > 0.95 and plan_id in NEXT_PLAN and month < LAST_MONTH and rng.random() < 0.08:
            subscriptions.append((sub_id, cust_id, plan_id, start,
                                  month_end(month), "CANCELLED", "Plan change"))
            sub_id += 1
            plan_id = NEXT_PLAN[plan_id]
            start = add_months(month, 1)
 
        last_complaints, last_failed, last_ratio = complaints, failed, ratio
        tenure += 1
        month = add_months(month, 1)
 
    if not churned:
        subscriptions.append((sub_id, cust_id, plan_id, start, None, "ACTIVE", None))
        sub_id += 1
 
# ---------------------------------------------------------------
# 3. Oracle-a yükləmək (əvvəl köhnə datanı silirik - skript təkrar işə salına bilsin)
# ---------------------------------------------------------------
for table in ["usage_monthly", "payments", "subscriptions"]:
    cur.execute(f"DELETE FROM {table}")
 
# end_date bəzi sətirlərdə boşdur (aktiv abunəlik), ona görə tipini əvvəlcədən bildiririk
cur.setinputsizes(None, None, None, oracledb.DB_TYPE_DATE, oracledb.DB_TYPE_DATE, 15, 40)
cur.executemany("""INSERT INTO subscriptions
                       (subscription_id, customer_id, plan_id, start_date, end_date, status, cancel_reason)
                   VALUES (:1, :2, :3, :4, :5, :6, :7)""", subscriptions)
cur.executemany("""INSERT INTO payments
                       (payment_id, subscription_id, payment_date, amount, payment_status)
                   VALUES (:1, :2, :3, :4, :5)""", payments)
cur.executemany("""INSERT INTO usage_monthly
                       (customer_id, usage_month, data_used_gb, voice_minutes,
                        sms_count, support_tickets, network_complaints)
                   VALUES (:1, :2, :3, :4, :5, :6, :7)""", usage)
conn.commit()
 
# ---------------------------------------------------------------
# 4. Yoxlama
# ---------------------------------------------------------------
for table in ["subscriptions", "payments", "usage_monthly"]:
    cur.execute(f"SELECT COUNT(*) FROM {table}")
    print(f"{table:<15}: {cur.fetchone()[0]:>7} sətir")
 
cur.execute("SELECT status, COUNT(*) FROM subscriptions GROUP BY status ORDER BY status")
for status, cnt in cur.fetchall():
    print(f"  {status:<10}: {cnt}")
 
cur.close()
conn.close()