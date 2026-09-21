-- =============================================================================
-- RailFlow — Railway Train Ticket Reservation & Management Database
-- File: 01_create_database.sql
-- Purpose: Create and select the working database.
-- =============================================================================

DROP DATABASE IF EXISTS railflow_db;

CREATE DATABASE railflow_db
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE railflow_db;

SET NAMES utf8mb4;
SET time_zone = '+00:00';
