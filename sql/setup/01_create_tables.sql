-- =====================================================
-- Telecom Customer Churn Analysis | 01_create_tables.sql
-- Note: all data is synthetic
-- Run as churn_analytics
-- =====================================================

-- Əvvəlki versiyanın cədvəlləri varsa, onları silir (yoxdursa, xəta vermir)
BEGIN
  FOR t IN (SELECT table_name FROM user_tables
             WHERE table_name IN ('USAGE_MONTHLY','PAYMENTS','SUBSCRIPTIONS','CUSTOMERS','PLANS'))
  LOOP
    EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' CASCADE CONSTRAINTS PURGE';
  END LOOP;
END;
/

-- Tarif planları
CREATE TABLE plans (
  plan_id             NUMBER(3)     PRIMARY KEY,
  plan_name           VARCHAR2(30)  NOT NULL,
  plan_type           VARCHAR2(10)  NOT NULL CHECK (plan_type IN ('PREPAID', 'POSTPAID')),
  monthly_fee         NUMBER(6,2)   NOT NULL,
  data_gb_included    NUMBER(5),
  minutes_included    NUMBER(5)
);

-- Abunəçilər
CREATE TABLE customers (
  customer_id          NUMBER(8)     PRIMARY KEY,
  signup_date          DATE          NOT NULL,
  gender               VARCHAR2(10),
  age                  NUMBER(3),
  city                 VARCHAR2(30),
  acquisition_channel  VARCHAR2(30)
);

-- Abunəliklər (bir abunəçinin bir neçə abunəliyi ola bilər: tarif dəyişmə, ayrılıb geri qayıtma)
CREATE TABLE subscriptions (
  subscription_id  NUMBER(10)    PRIMARY KEY,
  customer_id      NUMBER(8)     NOT NULL REFERENCES customers(customer_id),
  plan_id          NUMBER(3)     NOT NULL REFERENCES plans(plan_id),
  start_date       DATE          NOT NULL,
  end_date         DATE,
  status           VARCHAR2(15)  NOT NULL CHECK (status IN ('ACTIVE', 'CANCELLED')),
  cancel_reason    VARCHAR2(40),
  CONSTRAINT chk_sub_dates CHECK (end_date IS NULL OR end_date >= start_date)
);

-- Aylıq ödənişlər (postpaid hesab ödənişi / prepaid balans artırma)
CREATE TABLE payments (
  payment_id       NUMBER(12)    PRIMARY KEY,
  subscription_id  NUMBER(10)    NOT NULL REFERENCES subscriptions(subscription_id),
  payment_date     DATE          NOT NULL,
  amount           NUMBER(8,2)   NOT NULL,
  payment_status   VARCHAR2(10)  NOT NULL CHECK (payment_status IN ('SUCCESS', 'FAILED'))
);

-- Aylıq istifadə göstəriciləri
CREATE TABLE usage_monthly (
  customer_id         NUMBER(8)     NOT NULL REFERENCES customers(customer_id),
  usage_month         DATE          NOT NULL,
  data_used_gb        NUMBER(7,2),
  voice_minutes       NUMBER(6),
  sms_count           NUMBER(5),
  support_tickets     NUMBER(3),
  network_complaints  NUMBER(3),
  CONSTRAINT pk_usage PRIMARY KEY (customer_id, usage_month)
);

-- Sorğuları sürətləndirmək üçün indekslər
CREATE INDEX ix_sub_customer ON subscriptions(customer_id);
CREATE INDEX ix_sub_start    ON subscriptions(start_date);
CREATE INDEX ix_pay_sub      ON payments(subscription_id);
CREATE INDEX ix_pay_date     ON payments(payment_date);
