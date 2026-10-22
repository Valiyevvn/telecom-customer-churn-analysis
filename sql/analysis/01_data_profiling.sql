-- =========================================================
-- Azercell Customer Churn Analysis
-- 01_data_profiling.sql: Datanı tanımaq və churn tərifi
-- Qeyd: data sintetikdir, Azercell Telecom-un real datası deyil.
-- =========================================================


-- ---------------------------------------------------------
-- 1. Abunəçilərin cəlb olunma kanalları üzrə bölgüsü
-- Məqsəd: kanalların ölçüsünü, orta yaşı və boş yaş
-- dəyərlərini görmək (data keyfiyyəti yoxlaması).
-- Nəticə: Store ən böyük kanal (1982), Promo ən kiçik (714).
-- Orta yaş bütün kanallarda ~34. Yaşı boş olanlar (154)
-- kanallar arasında bərabər paylanıb (~3%).
-- ---------------------------------------------------------
SELECT acquisition_channel,
       COUNT(*)              AS customers,
       ROUND(AVG(age), 1)    AS avg_age,
       COUNT(*) - COUNT(age) AS missing_age
FROM customers
GROUP BY acquisition_channel
ORDER BY customers DESC;


-- ---------------------------------------------------------
-- 2. Bağlanmış abunəliklərin səbəbləri
-- Məqsəd: CANCELLED statusunun içində nə olduğunu görmək.
-- Nəticə: 2319 bağlanmış abunəliyin 574-ü "Plan change"-dir,
-- yəni abunəçi getməyib, böyük tarifə keçib.
-- Səbəbi boş olanlar "Unknown" kimi göstərilir (143).
-- ---------------------------------------------------------
SELECT NVL(cancel_reason, 'Unknown') AS cancel_reason,
       COUNT(*)                      AS subscriptions
FROM subscriptions
WHERE status = 'CANCELLED'
GROUP BY NVL(cancel_reason, 'Unknown')
ORDER BY subscriptions DESC;


-- =========================================================
-- 3. Churn tərifi
-- Abunəçinin heç bir ACTIVE abunəliyi qalmayıbsa = churned.
-- =========================================================

-- 3a. SƏHV yanaşma (müqayisə üçün saxlanılıb):
-- status = 'CANCELLED' "Plan change" hallarını da sayır.
-- Nəticə: 2319 abunəlik / 2151 abunəçi -> real itkini ~33% şişirdir.
SELECT COUNT(*)                    AS cancelled_subscriptions,
       COUNT(DISTINCT customer_id) AS customers_with_cancellation
FROM subscriptions
WHERE status = 'CANCELLED';

-- 3b. DÜZGÜN yanaşma:
-- Aktiv abunəliyi olmayan abunəçilər. Nəticə: 1745 abunəçi.
SELECT COUNT(*) AS churned_customers
FROM customers c
WHERE NOT EXISTS (
    SELECT 1
    FROM subscriptions s
    WHERE s.customer_id = c.customer_id
      AND s.status = 'ACTIVE'
);

