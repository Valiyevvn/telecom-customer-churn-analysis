-- =========================================================
-- Azercell Customer Churn Analysis
-- 07_data_quality_checks.sql: Data keyfiyyəti yoxlamaları
-- Qeyd: data sintetikdir, Azercell Telecom-un real datası deyil.
--
-- Məqsəd: analizdən və dashboard-dan əvvəl datanın etibarlı
-- olduğunu sübut etmək. Hər yoxlama "pozuntu sayı" qaytarır.
-- Gözlənilən nəticə: bütün yoxlamalarda 0 (status PASS).
-- Data yenilənəndə bu fayl təkrar işə salınır.
-- =========================================================
 
 
-- ---------------------------------------------------------
-- 1. Pass / fail yoxlamaları (21 yoxlama)
-- A. Struktur və məntiq (1-7)
-- B. Dəyər aralıqları və biznes qaydaları (8-15)
-- C. Mətn təmizliyi (16-17)
-- D. Uzlaşdırma: VIEW-lar ilə mənbə cədvəllər (18-21)
--
-- Gözlənilən: hər sətirdə violations = 0, status = PASS.
-- Bu sorğunu bütövlükdə seçib Ctrl + Enter ilə işə salın.
-- ---------------------------------------------------------
WITH checks AS (
 
    -- A. Struktur və məntiq -----------------------------------
    SELECT 1 AS check_no, 'Customers without any subscription' AS check_name, COUNT(*) AS violations
    FROM customers c
    WHERE NOT EXISTS (SELECT 1 FROM subscriptions s WHERE s.customer_id = c.customer_id)
 
    UNION ALL
    SELECT 2, 'Customers with more than one ACTIVE subscription', COUNT(*)
    FROM (SELECT customer_id
          FROM subscriptions
          WHERE status = 'ACTIVE'
          GROUP BY customer_id
          HAVING COUNT(*) > 1)
 
    UNION ALL
    SELECT 3, 'ACTIVE with end_date, or CANCELLED without end_date', COUNT(*)
    FROM subscriptions
    WHERE (status = 'ACTIVE'    AND end_date IS NOT NULL)
       OR (status = 'CANCELLED' AND end_date IS NULL)
 
    UNION ALL
    SELECT 4, 'ACTIVE subscription with a cancel_reason', COUNT(*)
    FROM subscriptions
    WHERE status = 'ACTIVE' AND cancel_reason IS NOT NULL
 
    UNION ALL
    SELECT 5, 'Overlapping subscriptions of one customer', COUNT(*)
    FROM subscriptions a
    JOIN subscriptions b ON  a.customer_id     = b.customer_id
                         AND a.subscription_id < b.subscription_id
                         AND a.start_date < NVL(b.end_date, DATE '9999-12-31')
                         AND b.start_date < NVL(a.end_date, DATE '9999-12-31')
 
    UNION ALL
    SELECT 6, 'Subscription starts before customer signup', COUNT(*)
    FROM subscriptions s
    JOIN customers c ON c.customer_id = s.customer_id
    WHERE s.start_date < c.signup_date
 
    UNION ALL
    SELECT 7, 'Signup date in the future', COUNT(*)
    FROM customers
    WHERE signup_date > SYSDATE
 
    -- B. Dəyər aralıqları və biznes qaydaları ------------------
    UNION ALL
    SELECT 8, 'Age outside 18-70 (NULL ages are reported in section 2)', COUNT(*)
    FROM customers
    WHERE age < 18 OR age > 70
 
    UNION ALL
    SELECT 9, 'Payments with zero or negative amount', COUNT(*)
    FROM payments
    WHERE amount <= 0
 
    UNION ALL
    SELECT 10, 'Payments dated outside their subscription period', COUNT(*)
    FROM payments p
    JOIN subscriptions s ON s.subscription_id = p.subscription_id
    WHERE p.payment_date < s.start_date
       OR p.payment_date > NVL(s.end_date, DATE '9999-12-31')
 
    UNION ALL
    -- Biznes qaydası: iyul 2025-dən prepaid tariflərə +20% qiymət
    SELECT 11, 'Payment amount differs from the tariff price', COUNT(*)
    FROM payments p
    JOIN subscriptions s ON s.subscription_id = p.subscription_id
    JOIN plans pl        ON pl.plan_id = s.plan_id
    WHERE p.amount <> CASE WHEN pl.plan_type = 'PREPAID'
                            AND p.payment_date >= DATE '2025-07-01'
                           THEN ROUND(pl.monthly_fee * 1.2, 2)
                           ELSE pl.monthly_fee
                      END
 
    UNION ALL
    SELECT 12, 'Duplicate payments (same customer, same month)', COUNT(*)
    FROM (SELECT s.customer_id, TRUNC(p.payment_date, 'MM') AS pay_month
          FROM payments p
          JOIN subscriptions s ON s.subscription_id = p.subscription_id
          GROUP BY s.customer_id, TRUNC(p.payment_date, 'MM')
          HAVING COUNT(*) > 1)
 
    UNION ALL
    SELECT 13, 'Usage rows in or after the month the customer churned', COUNT(*)
    FROM usage_monthly u
    JOIN v_customer_churn c ON c.customer_id = u.customer_id
    WHERE c.churn_date IS NOT NULL
      AND u.usage_month >= TRUNC(c.churn_date, 'MM')
 
    UNION ALL
    SELECT 14, 'Usage rows before the customer signup month', COUNT(*)
    FROM usage_monthly u
    JOIN customers c ON c.customer_id = u.customer_id
    WHERE u.usage_month < TRUNC(c.signup_date, 'MM')
 
    UNION ALL
    SELECT 15, 'Negative usage values', COUNT(*)
    FROM usage_monthly
    WHERE data_used_gb < 0 OR voice_minutes < 0 OR sms_count < 0
       OR support_tickets < 0 OR network_complaints < 0
 
    -- C. Mətn təmizliyi ---------------------------------------
    UNION ALL
    SELECT 16, 'Leading or trailing spaces in city, channel, gender', COUNT(*)
    FROM customers
    WHERE city <> TRIM(city)
       OR acquisition_channel <> TRIM(acquisition_channel)
       OR gender <> TRIM(gender)
 
    UNION ALL
    SELECT 17, 'City spelling variants (Baku, BAKU, baku)',
           COUNT(DISTINCT city) - COUNT(DISTINCT UPPER(TRIM(city)))
    FROM customers
 
    -- D. Uzlaşdırma (reconciliation) --------------------------
    UNION ALL
    SELECT 18, 'v_customer_churn vs NOT EXISTS churn count (difference)',
           ABS((SELECT SUM(is_churned) FROM v_customer_churn)
             - (SELECT COUNT(*)
                FROM customers c
                WHERE NOT EXISTS (SELECT 1
                                  FROM subscriptions s
                                  WHERE s.customer_id = c.customer_id
                                    AND s.status = 'ACTIVE')))
    FROM dual
 
    UNION ALL
    SELECT 19, 'v_monthly_churn vs v_customer_churn churner total (difference)',
           ABS((SELECT SUM(churned_in_month) FROM v_monthly_churn)
             - (SELECT SUM(is_churned) FROM v_customer_churn))
    FROM dual
 
    UNION ALL
    -- Gözlənilən ümumi gəlir: 971,304 AZN (Power BI Revenue kartı: 971K)
    SELECT 20, 'v_monthly_revenue vs payments revenue (difference, AZN)',
           ROUND(ABS((SELECT SUM(revenue_azn) FROM v_monthly_revenue)
                   - (SELECT SUM(amount) FROM payments WHERE payment_status = 'SUCCESS')), 2)
    FROM dual
 
    UNION ALL
    SELECT 21, 'v_monthly_revenue vs payments row count (difference)',
           ABS((SELECT SUM(total_payments) FROM v_monthly_revenue)
             - (SELECT COUNT(*) FROM payments))
    FROM dual
)
SELECT check_no,
       check_name,
       violations,
       CASE WHEN violations = 0 THEN 'PASS' ELSE 'FAIL' END AS status
FROM checks
ORDER BY check_no;
 
 
-- ---------------------------------------------------------
-- 2a. Sətir sayları (hər yükləmədən sonra yoxlanır)
-- Gözlənilən: plans 6, customers 5000, subscriptions 5574,
-- payments 56197, usage_monthly 56197.
-- ---------------------------------------------------------
SELECT 'plans'         AS table_name, COUNT(*) AS row_count FROM plans
UNION ALL
SELECT 'customers',      COUNT(*) FROM customers
UNION ALL
SELECT 'subscriptions',  COUNT(*) FROM subscriptions
UNION ALL
SELECT 'payments',       COUNT(*) FROM payments
UNION ALL
SELECT 'usage_monthly',  COUNT(*) FROM usage_monthly;
 
 
-- ---------------------------------------------------------
-- 2b. Çatışmayan dəyərlər (qəsdən qoyulmuş, məlum data boşluqları)
-- Bu, xəta deyil, məlumdur: real datada da belə boşluqlar olur.
-- Gözlənilən: customers.age 154 (3.1%), cancel_reason 143 (6.2%),
-- digər sütunlarda 0. Boş səbəb dashboard-da "Unknown" kimi
-- göstərilir, boş yaş isə "Unknown" yaş qrupuna düşür.
-- ---------------------------------------------------------
SELECT 'customers.age' AS column_name,
       COUNT(*) - COUNT(age) AS missing,
       ROUND(100 * (COUNT(*) - COUNT(age)) / COUNT(*), 1) AS missing_pct
FROM customers
UNION ALL
SELECT 'customers.gender',
       COUNT(*) - COUNT(gender),
       ROUND(100 * (COUNT(*) - COUNT(gender)) / COUNT(*), 1)
FROM customers
UNION ALL
SELECT 'customers.city',
       COUNT(*) - COUNT(city),
       ROUND(100 * (COUNT(*) - COUNT(city)) / COUNT(*), 1)
FROM customers
UNION ALL
SELECT 'customers.acquisition_channel',
       COUNT(*) - COUNT(acquisition_channel),
       ROUND(100 * (COUNT(*) - COUNT(acquisition_channel)) / COUNT(*), 1)
FROM customers
UNION ALL
SELECT 'subscriptions.cancel_reason (CANCELLED only)',
       COUNT(*) - COUNT(cancel_reason),
       ROUND(100 * (COUNT(*) - COUNT(cancel_reason)) / COUNT(*), 1)
FROM subscriptions
WHERE status = 'CANCELLED';
 
 
-- ---------------------------------------------------------
-- 2c. Tarix əhatəsi (datanın hansı dövrü əhatə etdiyi)
-- Gözlənilən: payments 2024-01-01 - 2026-09-28 (33 ay),
-- usage_monthly 2024-01-01 - 2026-09-01 (33 ay).
-- Aylarda boşluq olmamalıdır: 33 fərqli ay = tam əhatə.
-- ---------------------------------------------------------
SELECT 'payments'           AS source,
       MIN(payment_date)    AS first_date,
       MAX(payment_date)    AS last_date,
       COUNT(DISTINCT TRUNC(payment_date, 'MM')) AS distinct_months
FROM payments
UNION ALL
SELECT 'usage_monthly',
       MIN(usage_month),
       MAX(usage_month),
       COUNT(DISTINCT usage_month)
FROM usage_monthly
UNION ALL
SELECT 'customers (signup)',
       MIN(signup_date),
       MAX(signup_date),
       COUNT(DISTINCT TRUNC(signup_date, 'MM'))
FROM customers;