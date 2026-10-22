-- =====================================================
-- Telecom Customer Churn Analysis | 02_insert_plans.sql
-- Run as churn_analytics. Tariff names and prices are fictional.
-- =====================================================

INSERT INTO plans VALUES (1, 'Start 5',     'PREPAID',  5.00,   5,  100);
INSERT INTO plans VALUES (2, 'Smart 15',    'PREPAID',  10.00, 15,  300);
INSERT INTO plans VALUES (3, 'Smart 30',    'PREPAID',  15.00, 30,  500);
INSERT INTO plans VALUES (4, 'Biznes 20',   'POSTPAID', 20.00, 20, 1000);
INSERT INTO plans VALUES (5, 'Premium 50',  'POSTPAID', 30.00, 50, 2000);
INSERT INTO plans VALUES (6, 'Premium Max', 'POSTPAID', 45.00, 100, 5000);

COMMIT;

SELECT * FROM plans;
