-- =========================================================
-- Azercell Customer Churn Analysis
-- 05_revenue_impact.sql: Qiymət artımının prepaid gəlirinə təsiri
-- Qeyd: data sintetikdir, Azercell Telecom-un real datası deyil.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Prepaid aylıq gəlir, ödəyən abunəçi sayı və ARPU (2025)
-- ARPU = bir abunəçiyə düşən orta aylıq gəlir.
-- Yalnız uğurlu (SUCCESS) ödənişlər gəlir sayılır.
--
-- TAPINTI:
-- İyunla iyul arasında gəlir 11 405-dən 13 872 AZN-ə (+22%),
-- ARPU 10-dan 12 AZN-ə qalxıb. Amma gəlir qiymət artımından
-- əvvəl də artırdı (yeni abunəçilər hesabına), ona görə bu
-- müqayisə qiymət artımının təmiz təsirini göstərmir.
-- İyul-sentyabrda ödəyən abunəçi artımı kəskin yavaşlayıb
-- (ayda +50-80 əvəzinə +16-36): gedənlər artımı "yeyib".
-- ---------------------------------------------------------
SELECT TRUNC(p.payment_date, 'MM')                             AS pay_month,
       COUNT(DISTINCT s.customer_id)                           AS paying_customers,
       SUM(p.amount)                                           AS revenue_azn,
       ROUND(SUM(p.amount) / COUNT(DISTINCT s.customer_id), 2) AS arpu_azn
FROM payments p
JOIN subscriptions s ON s.subscription_id = p.subscription_id
JOIN plans pl        ON pl.plan_id = s.plan_id
WHERE pl.plan_type = 'PREPAID'
  AND p.payment_status = 'SUCCESS'
  AND p.payment_date >= DATE '2025-01-01'
  AND p.payment_date <  DATE '2026-01-01'
GROUP BY TRUNC(p.payment_date, 'MM')
ORDER BY pay_month;


-- ---------------------------------------------------------
-- 2. Qiymət artımının təmiz aylıq təsiri
-- Müqayisə: qiymət artımından əvvəlki 3 ay (aprel-iyun 2025)
-- vs sonrakı 3 ay (iyul-sentyabr 2025).
-- Qiymət artımı tarixi params CTE-sində bir dəfə yazılıb.
--
-- SÜTUNLAR:
-- arpu_before_azn        : artımdan əvvəl bir abunəçinin ayda
--                          ödədiyi orta məbləğ
-- arpu_after_azn         : artımdan sonra bir abunəçinin ayda
--                          ödədiyi orta məbləğ
-- avg_payers_after       : artımdan sonra ayda orta hesabla
--                          ödəniş edən abunəçi sayı
-- base_churn_pct         : artımdan əvvəlki "normal" aylıq churn faizi
-- actual_churn_after     : artımdan sonrakı 3 ayda həqiqətən gedənlər
-- expected_churn_after   : normal faiz davam etsəydi, gedəcək olanlar
-- excess_churn           : qiymət artımına görə ƏLAVƏ gedənlər
--                          (actual - expected)
-- price_gain_azn_month   : nəzəri qazanc, qalanların çox ödəməsi
--                          (avg_payers_after x ARPU fərqi)
-- lost_revenue_azn_month : əlavə gedənlərin köhnə qiymətlə
--                          ödəyəcəyi, amma artıq ödəmədiyi məbləğ
--                          (excess_churn x arpu_before)
-- net_impact_azn_month   : təmiz təsir (price_gain - lost_revenue)
--
-- TAPINTI:
-- ARPU 9.95-dən 11.97 AZN-ə qalxıb. Normal şəraitdə 3 ayda ~126
-- abunəçi gedəcəkdisə, 296 nəfər gedib: qiymət artımı ~170 əlavə
-- itkiyə səbəb olub. Nəzəri qazanc ~+2 390 AZN/ay, itirilən gəlir
-- ~1 690 AZN/ay, təmiz təsir ~+700 AZN/ay.
--
-- NƏTİCƏ: Qiymət artımı müsbət olub, amma potensial qazancın
-- ~70%-i itirilmiş abunəçilərə gedib. Növbəti qiymət
-- dəyişikliyində qiymətə həssas seqmentlər üçün saxlama
-- təklifləri hazırlamaq tövsiyə olunur.
--
-- MƏHDUDİYYƏT: Bu, əvvəl-sonra müqayisəsinə əsaslanan təxmini
-- hesablamadır. Daha dəqiq nəticə üçün qiyməti artırılmayan
-- nəzarət qrupu ilə müqayisə lazımdır.
-- ---------------------------------------------------------
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
    JOIN plans pl        ON pl.plan_id = s.plan_id
    WHERE pl.plan_type = 'PREPAID'
      AND p.payment_status = 'SUCCESS'
),
monthly_revenue AS (
    SELECT pay_month,
           COUNT(DISTINCT customer_id) AS payers,
           SUM(amount)                 AS revenue
    FROM prepaid_payments
    GROUP BY pay_month
),
revenue_periods AS (
    SELECT SUM(CASE WHEN r.pay_month >= ADD_MONTHS(pr.change_date, -3)
                     AND r.pay_month <  pr.change_date THEN r.revenue END)
         / SUM(CASE WHEN r.pay_month >= ADD_MONTHS(pr.change_date, -3)
                     AND r.pay_month <  pr.change_date THEN r.payers END)  AS arpu_before,
           SUM(CASE WHEN r.pay_month >= pr.change_date
                     AND r.pay_month <  ADD_MONTHS(pr.change_date, 3) THEN r.revenue END)
         / SUM(CASE WHEN r.pay_month >= pr.change_date
                     AND r.pay_month <  ADD_MONTHS(pr.change_date, 3) THEN r.payers END) AS arpu_after,
           AVG(CASE WHEN r.pay_month >= pr.change_date
                     AND r.pay_month <  ADD_MONTHS(pr.change_date, 3) THEN r.payers END) AS avg_payers_after
    FROM monthly_revenue r
    CROSS JOIN params pr
),
month_list AS (
    SELECT DISTINCT usage_month AS month_start
    FROM usage_monthly
),
prepaid_churn AS (
    SELECT m.month_start,
           COUNT(CASE WHEN c.signup_date < m.month_start
                       AND (c.churn_date IS NULL OR c.churn_date >= m.month_start)
                      THEN 1 END) AS active_at_start,
           COUNT(CASE WHEN c.churn_date >= m.month_start
                       AND c.churn_date <  ADD_MONTHS(m.month_start, 1)
                      THEN 1 END) AS churned
    FROM month_list m
    CROSS JOIN v_customer_churn c
    WHERE c.plan_type = 'PREPAID'
    GROUP BY m.month_start
),
churn_periods AS (
    SELECT SUM(CASE WHEN pc.month_start >= ADD_MONTHS(pr.change_date, -3)
                     AND pc.month_start <  pr.change_date THEN pc.churned END)
         / SUM(CASE WHEN pc.month_start >= ADD_MONTHS(pr.change_date, -3)
                     AND pc.month_start <  pr.change_date THEN pc.active_at_start END) AS base_churn_rate,
           SUM(CASE WHEN pc.month_start >= pr.change_date
                     AND pc.month_start <  ADD_MONTHS(pr.change_date, 3) THEN pc.churned END)         AS actual_churn_after,
           SUM(CASE WHEN pc.month_start >= pr.change_date
                     AND pc.month_start <  ADD_MONTHS(pr.change_date, 3) THEN pc.active_at_start END) AS active_sum_after
    FROM prepaid_churn pc
    CROSS JOIN params pr
)
SELECT ROUND(rp.arpu_before, 2)                                     AS arpu_before_azn,
       ROUND(rp.arpu_after, 2)                                      AS arpu_after_azn,
       ROUND(rp.avg_payers_after)                                   AS avg_payers_after,
       ROUND(100 * cp.base_churn_rate, 2)                           AS base_churn_pct,
       cp.actual_churn_after,
       ROUND(cp.base_churn_rate * cp.active_sum_after)             AS expected_churn_after,
       ROUND(cp.actual_churn_after
             - cp.base_churn_rate * cp.active_sum_after)            AS excess_churn,
       ROUND(rp.avg_payers_after * (rp.arpu_after - rp.arpu_before)) AS price_gain_azn_month,
       ROUND((cp.actual_churn_after
              - cp.base_churn_rate * cp.active_sum_after)
             * rp.arpu_before)                                      AS lost_revenue_azn_month,
       ROUND(rp.avg_payers_after * (rp.arpu_after - rp.arpu_before)
             - (cp.actual_churn_after
                - cp.base_churn_rate * cp.active_sum_after)
               * rp.arpu_before)                                    AS net_impact_azn_month
FROM revenue_periods rp
CROSS JOIN churn_periods cp;