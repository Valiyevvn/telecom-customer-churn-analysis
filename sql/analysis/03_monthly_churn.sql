-- ---------------------------------------------------------
-- Prepaid və postpaid üzrə aylıq churn (aprel-dekabr 2025)
-- Məqsəd: iyul-sentyabr 2025 sıçrayışının hansı qrupda
-- olduğunu tapmaq.
--
-- TAPINTI:
-- İyul 2025-dəki 20% qiymət artımından sonra prepaid
-- abunəçilərdə aylıq churn 3-4%-dən 7-8%-ə qalxdı və 3 ay
-- yüksək qaldı. Qiyməti dəyişməyən postpaid abunəçilərdə
-- dəyişiklik olmadı (1-2%).
--
-- Yoxlanılan alternativ: "yay mövsümü" fərziyyəsi təkzib
-- olundu, çünki 2024-ün yayında belə sıçrayış yoxdur.
-- ---------------------------------------------------------

WITH month_list AS (
    SELECT DISTINCT usage_month AS month_start
    FROM usage_monthly
),
monthly_stats AS (
    SELECT m.month_start,
           COUNT(CASE WHEN c.signup_date < m.month_start
                       AND (c.churn_date IS NULL OR c.churn_date >= m.month_start)
                      THEN 1 END) AS active_at_start,
           COUNT(CASE WHEN c.churn_date >= m.month_start
                       AND c.churn_date <  ADD_MONTHS(m.month_start, 1)
                      THEN 1 END) AS churned_in_month
    FROM month_list m
    CROSS JOIN v_customer_churn c
    GROUP BY m.month_start
)
SELECT month_start,
       active_at_start,
       churned_in_month,
       ROUND(100 * churned_in_month / NULLIF(active_at_start, 0), 2) AS churn_rate_pct
FROM monthly_stats
WHERE active_at_start > 0
ORDER BY month_start;

-- Prepaid və postpaid üzrə aylıq churn (2025-in aprelindən dekabrına)
WITH month_list AS (
    SELECT DISTINCT usage_month AS month_start
    FROM usage_monthly
),
monthly_stats AS (
    SELECT m.month_start,
           c.plan_type,
           COUNT(CASE WHEN c.signup_date < m.month_start
                       AND (c.churn_date IS NULL OR c.churn_date >= m.month_start)
                      THEN 1 END) AS active_at_start,
           COUNT(CASE WHEN c.churn_date >= m.month_start
                       AND c.churn_date <  ADD_MONTHS(m.month_start, 1)
                      THEN 1 END) AS churned_in_month
    FROM month_list m
    CROSS JOIN v_customer_churn c
    GROUP BY m.month_start, c.plan_type
)
SELECT month_start,
       plan_type,
       active_at_start,
       churned_in_month,
       ROUND(100 * churned_in_month / NULLIF(active_at_start, 0), 2) AS churn_rate_pct
FROM monthly_stats
WHERE month_start >= DATE '2025-04-01'
  AND month_start <  DATE '2026-01-01'
ORDER BY month_start, plan_type;