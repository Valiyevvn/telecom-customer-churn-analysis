-- =====================================================
-- Telecom Customer Churn Analysis | 00_create_user.sql
-- Run as SYSTEM, connected to the pluggable database (XEPDB1).
-- Replace CHANGE_ME with your own password and use the same value
-- in your local .env file (DB_PASSWORD).
-- Note: all data in this project is synthetic.
-- =====================================================

CREATE USER churn_analytics IDENTIFIED BY "CHANGE_ME"
  DEFAULT TABLESPACE users
  QUOTA UNLIMITED ON users;

GRANT CREATE SESSION,
      CREATE TABLE,
      CREATE VIEW,
      CREATE SEQUENCE,
      CREATE PROCEDURE,
      CREATE MATERIALIZED VIEW
   TO churn_analytics;
