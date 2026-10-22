-- =========================================================
-- Azercell Customer Churn Analysis
-- 04_churn_reasons.sql: Qiymət artımından əvvəl və sonra
-- prepaid abunəçilərin gediş səbəbləri
-- Qeyd: data sintetikdir, Azercell Telecom-un real datası deyil.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Prepaid gediş səbəbləri: aprel-iyun vs iyul-sentyabr 2025
-- Məqsəd: 03 faylındakı tapıntını ikinci, müstəqil mənbə ilə
-- yoxlamaq (triangulyasiya). Davranış datası churn-un qiymət
-- artımından sonra qalxdığını göstərdi. İndi abunəçilərin
-- özlərinin göstərdiyi səbəblərə baxırıq.
-- Faiz hər dövrün öz cəminə görə hesablanır (share of total),
-- çünki ikinci dövrdə ümumi gediş sayı daha çoxdur və sadəcə
-- saylara baxanda bütün səbəblər artmış görünür.
--
-- TAPINTI:
-- Gedən prepaid abunəçilərin sayı 111-dən 296-ya qalxdı (~2.7 dəfə).
-- "Price" səbəbi 30-dan 115-ə qalxdı (~3.8 dəfə), payı 27%-dən
-- 39%-ə yüksəldi və ən çox göstərilən səbəbə çevrildi.
-- "Moved to competitor" də 37-dən 90-a qalxdı (~2.4 dəfə).
-- Bu səbəbin bir hissəsi də qiymətlə bağlı ola bilər: abunəçi
-- daha ucuz rəqib təklifinə keçir, amma səbəb kimi "rəqib" qeyd olunur.
--
-- NƏTİCƏ: Davranış datası və abunəçilərin öz cavabları eyni
-- şeyi göstərir: iyul 2025-dəki churn sıçrayışının əsas
-- səbəbi prepaid qiymət artımıdır.
-- ---------------------------------------------------------
WITH prepaid_churn AS (
    SELECT CASE
             WHEN churn_date >= DATE '2025-04-01'
              AND churn_date <  DATE '2025-07-01' THEN '1. Before (Apr-Jun 2025)'
             WHEN churn_date >= DATE '2025-07-01'
              AND churn_date <  DATE '2025-10-01' THEN '2. After (Jul-Sep 2025)'
           END AS period,
           churn_reason
    FROM v_customer_churn
    WHERE plan_type = 'PREPAID'
      AND is_churned = 1
)
SELECT period,
       churn_reason,
       COUNT(*) AS churned,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY period), 1) AS pct_of_period
FROM prepaid_churn
WHERE period IS NOT NULL
GROUP BY period, churn_reason
ORDER BY period, churned DESC;