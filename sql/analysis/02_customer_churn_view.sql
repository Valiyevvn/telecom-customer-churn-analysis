-- =========================================================
-- Azercell Customer Churn Analysis
-- 02_customer_churn_view.sql: Abunəçi səviyyəsində churn VIEW-u
-- Qeyd: data sintetikdir, Azercell Telecom-un real datası deyil.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Edge case yoxlaması: tarif dəyişən abunəçilərin abunəlikləri
-- Məqsəd: ROW_NUMBER ilə hər abunəçinin son abunəliyini (rn = 1)
-- düzgün tapdığımızı kiçik nümunədə yoxlamaq.
-- Nəticə: 100003 və 100013 böyük tarifə keçib və aktivdir.
-- 100010 tarifini artırıb, sonra Relocation səbəbi ilə gedib.
-- rn = 1 sətri hər abunəçinin hazırkı vəziyyətini və real
-- gediş səbəbini verir, "Plan change" isə rn = 2-də qalır.
-- ---------------------------------------------------------
SELECT customer_id,
       subscription_id,
       plan_id,
       start_date,
       end_date,
       status,
       cancel_reason,
       ROW_NUMBER() OVER (PARTITION BY customer_id
                          ORDER BY start_date DESC) AS rn
FROM subscriptions
WHERE customer_id IN (
    SELECT customer_id
    FROM subscriptions
    WHERE cancel_reason = 'Plan change'
    FETCH FIRST 3 ROWS ONLY
)
ORDER BY customer_id, start_date;


-- ---------------------------------------------------------
-- 2. v_customer_churn: hər abunəçi üçün bir sətir
-- Churn tərifi: son abunəliyi ACTIVE deyilsə = churned.
-- Müşahidə tarixi (obs_end_date) datadan dinamik götürülür,
-- yeni ay datası gələndə VIEW avtomatik yenilənir.
-- Sütunlar: cohort_month (qoşulma ayı), is_churned (1 və ya 0),
-- churn_date, churn_reason, tenure_months (qalma müddəti).
-- ---------------------------------------------------------
CREATE OR REPLACE VIEW v_customer_churn AS
WITH last_sub AS (
    SELECT s.customer_id,
           s.plan_id,
           s.status,
           s.end_date,
           s.cancel_reason,
           ROW_NUMBER() OVER (PARTITION BY s.customer_id
                              ORDER BY s.start_date DESC) AS rn
    FROM subscriptions s
),
obs AS (
    SELECT LAST_DAY(MAX(usage_month)) AS obs_end_date
    FROM usage_monthly
)
SELECT c.customer_id,
       c.signup_date,
       TRUNC(c.signup_date, 'MM')                                  AS cohort_month,
       c.gender,
       c.age,
       c.city,
       c.acquisition_channel,
       p.plan_name                                                 AS current_plan,
       p.plan_type,
       CASE WHEN ls.status = 'ACTIVE' THEN 0 ELSE 1 END            AS is_churned,
       CASE WHEN ls.status = 'CANCELLED' THEN ls.end_date END      AS churn_date,
       CASE WHEN ls.status = 'CANCELLED'
            THEN NVL(ls.cancel_reason, 'Unknown') END              AS churn_reason,
       FLOOR(MONTHS_BETWEEN(NVL(ls.end_date, o.obs_end_date),
                            c.signup_date))                        AS tenure_months
FROM customers c
JOIN last_sub ls ON ls.customer_id = c.customer_id
                AND ls.rn = 1
JOIN plans p     ON p.plan_id = ls.plan_id
CROSS JOIN obs o;


-- ---------------------------------------------------------
-- 3. VIEW-un yoxlanması
-- Gözlənilən: 5000 sətir, 5000 unikal abunəçi (təkrar yoxdur),
-- 1745 churned (01 faylındakı NOT EXISTS nəticəsi ilə eyni).
-- churn_pct = 34.9%: bu, aylıq yox, 2024-dən bəri ÜMUMİ paydır.
-- ---------------------------------------------------------
SELECT COUNT(*)                        AS customers,
       COUNT(DISTINCT customer_id)     AS unique_customers,
       SUM(is_churned)                 AS churned,
       ROUND(100 * AVG(is_churned), 1) AS churn_pct
FROM v_customer_churn;

-- İlk 10 sətrə baxış
SELECT *
FROM v_customer_churn
FETCH FIRST 10 ROWS ONLY;