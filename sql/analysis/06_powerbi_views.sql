-- =========================================================
-- Azercell Customer Churn Analysis
-- 06_powerbi_views.sql: Power BI dashboard üçün VIEW-lar
-- Qeyd: data sintetikdir, Azercell Telecom-un real datası deyil.
-- Power BI yalnız bu VIEW-lara və v_customer_churn-a qoşulur.
-- Faizlər VIEW-larda saxlanılmır, yalnız saylar: faizlər
-- Power BI-da DAX ilə hesablanır ki, istənilən filtrdə düzgün olsun.
-- =========================================================


-- ---------------------------------------------------------
-- 1. v_monthly_churn: hər ay, tarif növü, kanal və şəhər üzrə bir sətir
-- Grain: ay x plan_type x acquisition_channel x city
-- Kanal və şəhər əlavə olunub ki, Power BI slicer-ləri bu
-- cədvəli də filtrləyə bilsin.
-- active_at_start  : ayın əvvəlində aktiv abunəçilər
-- churned_in_month : həmin ay gedənlər
-- new_customers    : həmin ay qoşulanlar
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly_churn AS
WITH month_list AS (
    SELECT DISTINCT usage_month AS month_start
    FROM usage_monthly
)
SELECT m.month_start,
       c.plan_type,
       c.acquisition_channel,
       c.city,
       COUNT(CASE WHEN c.signup_date < m.month_start
                   AND (c.churn_date IS NULL OR c.churn_date >= m.month_start)
                  THEN 1 END) AS active_at_start,
       COUNT(CASE WHEN c.churn_date >= m.month_start
                   AND c.churn_date <  ADD_MONTHS(m.month_start, 1)
                  THEN 1 END) AS churned_in_month,
       COUNT(CASE WHEN c.signup_date >= m.month_start
                   AND c.signup_date <  ADD_MONTHS(m.month_start, 1)
                  THEN 1 END) AS new_customers
FROM month_list m
CROSS JOIN v_customer_churn c
GROUP BY m.month_start, c.plan_type, c.acquisition_channel, c.city;


-- ---------------------------------------------------------
-- 2. v_monthly_revenue: hər ay, tarif növü, kanal və şəhər üzrə bir sətir
-- Grain: ay x plan_type x acquisition_channel x city
-- paying_customers : uğurlu ödəniş edən fərqli abunəçilər
-- revenue_azn      : yalnız uğurlu (SUCCESS) ödənişlərin cəmi
-- failed_payments  : uğursuz ödəniş sayı
-- total_payments   : bütün ödəniş cəhdləri
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT TRUNC(p.payment_date, 'MM')                                AS month_start,
       pl.plan_type,
       c.acquisition_channel,
       c.city,
       COUNT(DISTINCT CASE WHEN p.payment_status = 'SUCCESS'
                           THEN s.customer_id END)                AS paying_customers,
       SUM(CASE WHEN p.payment_status = 'SUCCESS'
                THEN p.amount ELSE 0 END)                         AS revenue_azn,
       COUNT(CASE WHEN p.payment_status = 'FAILED' THEN 1 END)    AS failed_payments,
       COUNT(*)                                                   AS total_payments
FROM payments p
JOIN subscriptions s ON s.subscription_id = p.subscription_id
JOIN plans pl        ON pl.plan_id = s.plan_id
JOIN customers c     ON c.customer_id = s.customer_id
GROUP BY TRUNC(p.payment_date, 'MM'), pl.plan_type, c.acquisition_channel, c.city;

-- ---------------------------------------------------------
-- 3. v_price_impact: qiymət artımının təmiz aylıq təsiri (tək sətir)
-- Hesablama məntiqi və sütunların izahı: 05_revenue_impact.sql
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW v_price_impact AS
WITH params AS (
    SELECT DATE '2025-07-01' AS change_date
    FROM dual
),
prepaid_payments AS (
    SELECT TRUNC(p.payment_date, 'MM') AS pay_month,
           s.customer_id,
           p.amount
    FROM payments p
    JOIN subscriptions s ON s.subscription_id = p.subscription_id
    JOIN plans pl
    
-- Gözlənilən: v_customer_churn 5000, v_monthly_churn ~2640
-- (33 ay x 2 tarif x 4 kanal x 10 şəhər), v_monthly_revenue ~2600,
-- v_price_impact 1    