-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1:3306
-- Generation Time: Jun 11, 2026 at 03:20 AM
-- Server version: 10.4.32-MariaDB
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `safechain`
--

-- --------------------------------------------------------

--
-- Table structure for table `alerts`
--

CREATE TABLE `alerts` (
  `ID` int(11) NOT NULL,
  `shipment_number` varchar(100) NOT NULL,
  `alert_reason` varchar(255) NOT NULL,
  `duration` int(11) DEFAULT NULL COMMENT 'Duration in seconds, NULL if ongoing',
  `latitude` decimal(10,8) DEFAULT NULL,
  `longitude` decimal(11,8) DEFAULT NULL,
  `full_date` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `alerts`
--

INSERT INTO `alerts` (`ID`, `shipment_number`, `alert_reason`, `duration`, `latitude`, `longitude`, `full_date`) VALUES
(1, 'SHP-1001', 'تجاوز درجة الحرارة المسموحة (9.2 درجة)', 900, 24.72000000, 46.68000000, '2023-10-01 06:10:00'),
(2, 'SHP-1001', 'فتح باب الشاحنة أثناء النقل', 300, 24.72000000, 46.68000000, '2023-10-01 06:10:00'),
(8, 'SHP-2004', 'تجاوز حرارة الأنسولين الحد الأقصى (10.5 درجة)', 720, 21.62000000, 39.24000000, '2023-10-22 06:10:00'),
(9, 'SHP-2004', 'الباب مفتوح لمدة طويلة (تجاوز 10 دقائق)', 720, 21.62000000, 39.24000000, '2023-10-22 06:10:00');

-- --------------------------------------------------------

--
-- Table structure for table `groups`
--

CREATE TABLE `groups` (
  `ID` int(11) NOT NULL,
  `min_temperature` float DEFAULT NULL,
  `max_temperature` float DEFAULT NULL,
  `min_humidity` int(11) DEFAULT NULL,
  `max_humidity` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `groups`
--

INSERT INTO `groups` (`ID`, `min_temperature`, `max_temperature`, `min_humidity`, `max_humidity`, `created_at`) VALUES
(1, 2, 8, 30, 50, '2026-06-09 21:50:27'),
(2, 0, 4, 70, 90, '2026-06-09 21:50:27'),
(3, -18, -15, 10, 30, '2026-06-09 21:50:27'),
(4, 15, 25, 30, 60, '2026-06-09 21:50:27');

-- --------------------------------------------------------

--
-- Table structure for table `products`
--

CREATE TABLE `products` (
  `ID` int(11) NOT NULL,
  `product_name` varchar(255) NOT NULL,
  `group_id` int(11) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `products`
--

INSERT INTO `products` (`ID`, `product_name`, `group_id`, `created_at`) VALUES
(1, 'لقاح كوفيد-19', 1, '2026-06-09 21:50:27'),
(2, 'أنسولين', 1, '2026-06-09 21:50:27'),
(3, 'فراولة طازجة', 2, '2026-06-09 21:50:27'),
(4, 'لحوم مجمدة', 3, '2026-06-09 21:50:27'),
(5, 'أجهزة حاسوب محمولة', 4, '2026-06-09 21:50:27');

-- --------------------------------------------------------

--
-- Table structure for table `reports`
--

CREATE TABLE `reports` (
  `ID` int(11) NOT NULL,
  `shipment_number` varchar(100) NOT NULL,
  `temperature` float NOT NULL,
  `humidity` float NOT NULL,
  `door_condition` enum('OPEN','CLOSED') NOT NULL DEFAULT 'CLOSED',
  `mq9_gas` float DEFAULT NULL,
  `mq135_gas` float DEFAULT NULL,
  `latitude` decimal(10,8) NOT NULL,
  `longitude` decimal(11,8) NOT NULL,
  `full_date` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `reports`
--

INSERT INTO `reports` (`ID`, `shipment_number`, `temperature`, `humidity`, `door_condition`, `mq9_gas`, `mq135_gas`, `latitude`, `longitude`, `full_date`) VALUES
(1, 'SHP-1001', 4.5, 40, 'CLOSED', 0.1, 0.2, 24.71360000, 46.67530000, '2023-10-01 05:10:00'),
(2, 'SHP-1001', 4.7, 41, 'CLOSED', 0.1, 0.2, 24.71400000, 46.67600000, '2023-10-01 05:40:00'),
(3, 'SHP-1001', 9.2, 44, 'OPEN', 0.3, 0.5, 24.72000000, 46.68000000, '2023-10-01 06:10:00'),
(4, 'SHP-1001', 5.1, 42, 'CLOSED', 0.1, 0.2, 24.73000000, 46.69000000, '2023-10-01 06:40:00'),
(5, 'SHP-1001', 4.9, 40, 'CLOSED', 0.1, 0.2, 24.74000000, 46.70000000, '2023-10-01 07:10:00'),
(10, 'SHP-2001', 5, 35, 'CLOSED', 0.1, 0.2, 21.54330000, 39.17280000, '2023-10-01 05:25:00'),
(11, 'SHP-2001', 5.2, 36, 'CLOSED', 0.1, 0.2, 21.55000000, 39.18000000, '2023-10-01 05:55:00'),
(12, 'SHP-2001', 4.8, 34, 'CLOSED', 0.1, 0.2, 21.56000000, 39.19000000, '2023-10-01 06:25:00'),
(13, 'SHP-2001', 4.5, 33, 'CLOSED', 0.1, 0.2, 21.57000000, 39.20000000, '2023-10-01 06:55:00'),
(18, 'SHP-1004', 4.2, 38, 'CLOSED', 0.1, 0.2, 24.80000000, 46.75000000, '2023-10-20 04:40:00'),
(19, 'SHP-1004', 4.5, 39, 'CLOSED', 0.1, 0.2, 24.81000000, 46.76000000, '2023-10-20 05:10:00'),
(20, 'SHP-1004', 4.6, 40, 'CLOSED', 0.1, 0.2, 24.82000000, 46.77000000, '2023-10-20 05:40:00'),
(21, 'SHP-1004', 4.4, 38, 'CLOSED', 0.1, 0.2, 24.83000000, 46.78000000, '2023-10-20 06:10:00'),
(22, 'SHP-1004', 4.3, 37, 'CLOSED', 0.1, 0.2, 24.84000000, 46.79000000, '2023-10-20 06:40:00'),
(23, 'SHP-2004', 5.5, 45, 'CLOSED', 0.1, 0.2, 21.60000000, 39.22000000, '2023-10-22 05:10:00'),
(24, 'SHP-2004', 5.7, 46, 'CLOSED', 0.1, 0.2, 21.61000000, 39.23000000, '2023-10-22 05:40:00'),
(25, 'SHP-2004', 10.5, 55, 'OPEN', 0.4, 0.6, 21.62000000, 39.24000000, '2023-10-22 06:10:00'),
(26, 'SHP-2004', 6, 48, 'CLOSED', 0.1, 0.2, 21.63000000, 39.25000000, '2023-10-22 06:40:00'),
(27, 'SHP-2004', 5.8, 47, 'CLOSED', 0.1, 0.2, 21.64000000, 39.26000000, '2023-10-22 07:10:00'),
(28, 'SHP-4-0005', 5.8, 47, 'CLOSED', 0.1, 0.2, 24.54330000, 46.65810000, '2026-04-11 00:10:00'),
(29, 'SHP-1001', 23.5, 45, 'CLOSED', 0.5, 0.3, 24.71360000, 46.67530000, '2026-06-10 14:26:56'),
(30, 'SHP-4-0005', 15.8, 50, 'CLOSED', 0.1, 0.2, 24.54330000, 47.65810000, '2026-04-11 00:20:00'),
(31, 'SHP-4-0005', -15.5, 20, 'CLOSED', 6, 6, 24.54330000, 44.65810000, '2026-04-11 00:20:00');

-- --------------------------------------------------------

--
-- Table structure for table `security_limits`
--

CREATE TABLE `security_limits` (
  `ID` int(11) NOT NULL,
  `shipment_number` varchar(100) NOT NULL,
  `min_temperature` float NOT NULL,
  `max_temperature` float NOT NULL,
  `min_humidity` int(11) NOT NULL,
  `max_humidity` int(11) NOT NULL,
  `door_open_duration` int(11) NOT NULL COMMENT 'Maximum door open duration in seconds',
  `door_open_count` int(11) NOT NULL COMMENT 'Maximum allowed door opens',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `security_limits`
--

INSERT INTO `security_limits` (`ID`, `shipment_number`, `min_temperature`, `max_temperature`, `min_humidity`, `max_humidity`, `door_open_duration`, `door_open_count`, `created_at`) VALUES
(1, 'SHP-1001', 2, 8, 30, 50, 600, 3, '2026-06-09 21:50:27'),
(4, 'SHP-1004', 2, 8, 30, 50, 600, 3, '2026-06-09 21:50:27'),
(6, 'SHP-2001', 2, 8, 30, 50, 600, 3, '2026-06-09 21:50:27'),
(9, 'SHP-2004', 2, 8, 30, 50, 600, 3, '2026-06-09 21:50:27'),
(12, 'SHP-4-0005', -16, -15, 0, 30, 60, 5, '2026-06-10 21:07:23');

-- --------------------------------------------------------

--
-- Table structure for table `sensors`
--

CREATE TABLE `sensors` (
  `ID` int(11) NOT NULL,
  `truck_id` int(11) NOT NULL,
  `name` varchar(60) NOT NULL,
  `serial_number` varchar(100) NOT NULL,
  `sensor_type` enum('Temperature','Humidity','Gas','Door','GPS') NOT NULL,
  `status` enum('active','inactive','maintenance') NOT NULL DEFAULT 'active',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `sensors`
--

INSERT INTO `sensors` (`ID`, `truck_id`, `name`, `serial_number`, `sensor_type`, `status`, `created_at`, `updated_at`) VALUES
(1, 1, 'حساس حرارة', 'SN-TEMP-001', 'Temperature', 'active', '2026-06-09 21:50:27', '2026-06-10 18:22:51'),
(2, 1, 'حساس رطوبة', 'SN-HUM-001', 'Humidity', 'active', '2026-06-09 21:50:27', '2026-06-10 18:25:16'),
(3, 2, 'حساس حرارة', 'SN-TEMP-002', 'Temperature', 'active', '2026-06-09 21:50:27', '2026-06-10 18:22:51'),
(4, 1, 'حساس غاز', 'SN-GAS-002', 'Gas', 'maintenance', '2026-06-09 21:50:27', '2026-06-10 18:28:26'),
(5, 3, 'حساس حرارة', 'SN-TEMP-003', 'Temperature', 'active', '2026-06-09 21:50:27', '2026-06-10 18:22:51'),
(6, 1, 'حساس GPS', 'SN-GPS-001', 'GPS', 'active', '2026-06-09 21:50:27', '2026-06-10 18:29:06'),
(7, 4, 'حساس حرارة', 'SN-TEMP-004', 'Temperature', 'active', '2026-06-09 21:50:27', '2026-06-10 18:22:51'),
(8, 4, 'حساس رطوبة', 'SN-HUM-004', 'Humidity', 'active', '2026-06-09 21:50:27', '2026-06-10 18:25:16'),
(9, 5, 'حساس حرارة', 'SN-TEMP-005', 'Temperature', 'inactive', '2026-06-09 21:50:27', '2026-06-10 18:22:51'),
(10, 5, 'حساس غاز', 'SN-GAS-005', 'Gas', 'active', '2026-06-09 21:50:27', '2026-06-10 18:28:26'),
(11, 6, 'حساس حرارة', 'SN-TEMP-006', 'Temperature', 'active', '2026-06-09 21:50:27', '2026-06-10 18:22:51'),
(12, 6, 'حساس باب', 'SN-DOOR-006', 'Door', 'active', '2026-06-09 21:50:27', '2026-06-10 18:27:36');

-- --------------------------------------------------------

--
-- Table structure for table `trips`
--

CREATE TABLE `trips` (
  `ID` int(11) NOT NULL,
  `shipment_number` varchar(100) NOT NULL,
  `status` enum('active','completed','cancelled') NOT NULL DEFAULT 'active',
  `user_truck_id` int(11) NOT NULL,
  `product_ids` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL COMMENT 'Array of product IDs' CHECK (json_valid(`product_ids`)),
  `start_time` datetime NOT NULL DEFAULT current_timestamp(),
  `end_time` datetime DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `trips`
--

INSERT INTO `trips` (`ID`, `shipment_number`, `status`, `user_truck_id`, `product_ids`, `start_time`, `end_time`, `created_at`, `updated_at`) VALUES
(1, 'SHP-1001', 'completed', 1, '[1]', '2026-06-10 17:02:11', NULL, '2026-06-09 21:50:27', '2026-06-10 19:27:43'),
(4, 'SHP-1004', 'completed', 1, '[2]', '2023-10-20 07:30:00', NULL, '2026-06-09 21:50:27', '2026-06-10 01:45:07'),
(6, 'SHP-2001', 'completed', 4, '[1]', '2023-10-01 08:15:00', '2023-10-01 18:15:00', '2026-06-09 21:50:27', '2026-06-09 21:50:27'),
(9, 'SHP-2004', 'completed', 4, '[2]', '2023-10-22 08:00:00', NULL, '2026-06-09 21:50:27', '2026-06-10 01:47:53'),
(11, 'SHP-4-0003', 'completed', 4, '[1, 2]', '2026-06-10 04:48:23', '2026-06-10 04:49:04', '2026-06-10 01:48:23', '2026-06-10 01:49:04'),
(12, 'SHP-4-0004', 'completed', 4, '[1, 2]', '2026-06-10 04:52:18', '2026-06-10 04:52:27', '2026-06-10 01:52:18', '2026-06-10 01:52:27'),
(13, 'SHP-4-0005', 'active', 4, '[3, 4]', '2026-06-10 17:02:11', NULL, '2026-06-10 14:02:11', '2026-06-10 14:02:11');

-- --------------------------------------------------------

--
-- Table structure for table `trip_counter`
--

CREATE TABLE `trip_counter` (
  `ID` int(11) NOT NULL,
  `truck_id` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `last_sequence` int(11) NOT NULL DEFAULT 0,
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `trip_counter`
--

INSERT INTO `trip_counter` (`ID`, `truck_id`, `user_id`, `last_sequence`, `updated_at`) VALUES
(1, 1, 2, 2, '2026-06-09 21:50:27'),
(2, 2, 2, 2, '2026-06-09 21:50:27'),
(3, 3, 2, 1, '2026-06-09 21:50:27'),
(4, 4, 3, 5, '2026-06-10 14:02:11'),
(5, 5, 3, 2, '2026-06-09 21:50:27'),
(6, 6, 3, 1, '2026-06-09 21:50:27');

-- --------------------------------------------------------

--
-- Table structure for table `trucks`
--

CREATE TABLE `trucks` (
  `ID` int(11) NOT NULL,
  `name` varchar(255) NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `trucks`
--

INSERT INTO `trucks` (`ID`, `name`, `created_at`) VALUES
(1, 'Truck-001', '2026-06-09 21:50:27'),
(2, 'Truck-002', '2026-06-09 21:50:27'),
(3, 'Truck-003', '2026-06-09 21:50:27'),
(4, 'Truck-004', '2026-06-09 21:50:27'),
(5, 'Truck-005', '2026-06-09 21:50:27'),
(6, 'Truck-006', '2026-06-09 21:50:27');

-- --------------------------------------------------------

--
-- Table structure for table `updates`
--

CREATE TABLE `updates` (
  `ID` int(11) NOT NULL,
  `truck_id` int(11) NOT NULL,
  `admin_id` int(11) NOT NULL,
  `item_name` varchar(255) NOT NULL,
  `description` varchar(500) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `updates`
--

INSERT INTO `updates` (`ID`, `truck_id`, `admin_id`, `item_name`, `description`, `created_at`) VALUES
(1, 1, 1, 'معايرة حساس الحرارة', 'تمت معايرة حساس الحرارة لشاحنة اللقاحات', '2023-09-28 07:00:00'),
(2, 2, 1, 'صيانة وحدة التبريد', 'إصلاح عطل في ضاغط الثلاجة المجمدة', '2023-10-03 12:30:00'),
(3, 3, 1, 'تحديث البرنامج', 'تحديث نظام التتبع Firmware إلى v2.1', '2023-10-09 08:00:00'),
(4, 1, 1, 'استبدال حساس الباب', 'تركيب حساس باب جديد أكثر دقة', '2023-10-19 06:00:00'),
(5, 4, 1, 'فحص دوري', 'فحص دوري لشاحنة المستخدم - كل شيء سليم', '2023-09-30 05:30:00'),
(6, 5, 1, 'تغيير حساس الغاز', 'استبدال حساس MQ9 المعطل', '2023-10-06 11:00:00'),
(7, 6, 1, 'صيانة بطارية السنسر', 'تغيير بطارية حساس الرطوبة', '2023-10-20 13:00:00'),
(8, 4, 1, 'تحديث نظام GPS', 'تحسين دقة التتبع عبر الأقمار الصناعية', '2023-10-21 07:00:00'),
(9, 1, 4, 'فحص الحساسات', 'تم فحص حساسات Truck-001 - عدد الحساسات: 4', '2026-06-10 20:47:57'),
(10, 6, 4, 'إسناد شاحنة لمستخدم', 'تم إسناد الشاحنة Truck-006 للمستخدم محمد عبدالله (ID: 5)', '2026-06-10 20:51:36'),
(11, 4, 4, 'تحديد حدود الأمان', 'تم تحديث حدود الأمان للشحنة SHP-4-0005 - الحرارة: -16.0°--15.0° - الرطوبة: 0%-30%', '2026-06-10 21:18:31');

-- --------------------------------------------------------

--
-- Table structure for table `users`
--

CREATE TABLE `users` (
  `ID` int(11) NOT NULL,
  `full_name` varchar(255) NOT NULL,
  `email` varchar(255) NOT NULL,
  `phone` varchar(50) DEFAULT NULL,
  `password` varchar(255) NOT NULL,
  `role` enum('admin','user') NOT NULL DEFAULT 'user',
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `users`
--

INSERT INTO `users` (`ID`, `full_name`, `email`, `phone`, `password`, `role`, `created_at`, `updated_at`) VALUES
(1, 'رغد المسعري', 'rag425h@gmail.com', '0988621263', '$2b$12$tw28d2bEB8DGZ5556TPeFeUYoUOBl1zf.BssWn60aFMdHIKsU8BL6', 'admin', '2026-06-09 21:50:27', '2026-06-10 00:56:47'),
(2, 'رغد حسن', '3hd1425h@gmail.com', '05058666263', '$2b$12$l2qW2RHTH5m.69rG.KY41.we/5188a5zo6CEx/8tSEELUZTkRKc26', 'user', '2026-06-09 21:50:27', '2026-06-09 21:50:27'),
(3, 'GGGGG', 'ghdi.itac234@gmail.com', '221234568', '$2b$12$CuqG0f6aVR1cU4oyjAgUHeRppraleaHuqhQgX082dJgpWurj7vt/W', 'user', '2026-06-09 21:50:27', '2026-06-10 22:38:35'),
(4, 'GGGGG', 'aaaaa@gmail.com', '1234567', '$2b$12$CuqG0f6aVR1cU4oyjAgUHeRppraleaHuqhQgX082dJgpWurj7vt/W', 'admin', '2026-06-09 21:50:27', '2026-06-09 21:50:27'),
(5, 'محمد عبدالله', 'mhmmd1425h@gmail.com', '050222263', '$2b$12$tw28d2bEB8DGZ5556TPeFeUYoUOBl1zf.BssWn60aFMdHIKsU8BL6', 'user', '2026-06-09 21:50:27', '2026-06-09 21:50:27'),
(6, 'فاطمة عبدالله', 'fati1425h@gmail.com', '050224263', '$2b$12$tw28d2bEB8DGZ5556TPeFeUYoUOBl1zf.BssWn60aFMdHIKsU8BL6', 'user', '2026-06-09 21:50:27', '2026-06-09 21:50:27');

-- --------------------------------------------------------

--
-- Table structure for table `user_trucks`
--

CREATE TABLE `user_trucks` (
  `ID` int(11) NOT NULL,
  `user_id` int(11) NOT NULL,
  `truck_id` int(11) NOT NULL,
  `assigned_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `user_trucks`
--

INSERT INTO `user_trucks` (`ID`, `user_id`, `truck_id`, `assigned_at`) VALUES
(1, 2, 1, '2026-06-09 21:50:27'),
(4, 3, 4, '2026-06-09 21:50:27'),
(7, 6, 2, '2026-06-10 01:09:33'),
(9, 5, 6, '2026-06-10 20:51:36');

--
-- Indexes for dumped tables
--

--
-- Indexes for table `alerts`
--
ALTER TABLE `alerts`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `shipment_number` (`shipment_number`),
  ADD KEY `full_date` (`full_date`);

--
-- Indexes for table `groups`
--
ALTER TABLE `groups`
  ADD PRIMARY KEY (`ID`);

--
-- Indexes for table `products`
--
ALTER TABLE `products`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `group_id` (`group_id`);

--
-- Indexes for table `reports`
--
ALTER TABLE `reports`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `shipment_number` (`shipment_number`),
  ADD KEY `full_date` (`full_date`);

--
-- Indexes for table `security_limits`
--
ALTER TABLE `security_limits`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `shipment_number` (`shipment_number`);

--
-- Indexes for table `sensors`
--
ALTER TABLE `sensors`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `serial_number` (`serial_number`),
  ADD KEY `truck_id` (`truck_id`);

--
-- Indexes for table `trips`
--
ALTER TABLE `trips`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `shipment_number` (`shipment_number`),
  ADD KEY `user_truck_id` (`user_truck_id`),
  ADD KEY `status` (`status`),
  ADD KEY `start_time` (`start_time`);

--
-- Indexes for table `trip_counter`
--
ALTER TABLE `trip_counter`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `truck_user_unique` (`truck_id`,`user_id`),
  ADD KEY `truck_id` (`truck_id`),
  ADD KEY `user_id` (`user_id`);

--
-- Indexes for table `trucks`
--
ALTER TABLE `trucks`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `name` (`name`);

--
-- Indexes for table `updates`
--
ALTER TABLE `updates`
  ADD PRIMARY KEY (`ID`),
  ADD KEY `truck_id` (`truck_id`),
  ADD KEY `admin_id` (`admin_id`);

--
-- Indexes for table `users`
--
ALTER TABLE `users`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `email` (`email`),
  ADD UNIQUE KEY `phone` (`phone`);

--
-- Indexes for table `user_trucks`
--
ALTER TABLE `user_trucks`
  ADD PRIMARY KEY (`ID`),
  ADD UNIQUE KEY `user_truck_unique` (`user_id`,`truck_id`),
  ADD KEY `user_id` (`user_id`),
  ADD KEY `truck_id` (`truck_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `alerts`
--
ALTER TABLE `alerts`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=11;

--
-- AUTO_INCREMENT for table `groups`
--
ALTER TABLE `groups`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=5;

--
-- AUTO_INCREMENT for table `products`
--
ALTER TABLE `products`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=6;

--
-- AUTO_INCREMENT for table `reports`
--
ALTER TABLE `reports`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=32;

--
-- AUTO_INCREMENT for table `security_limits`
--
ALTER TABLE `security_limits`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT for table `sensors`
--
ALTER TABLE `sensors`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=13;

--
-- AUTO_INCREMENT for table `trips`
--
ALTER TABLE `trips`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=14;

--
-- AUTO_INCREMENT for table `trip_counter`
--
ALTER TABLE `trip_counter`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `trucks`
--
ALTER TABLE `trucks`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `updates`
--
ALTER TABLE `updates`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=12;

--
-- AUTO_INCREMENT for table `users`
--
ALTER TABLE `users`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- AUTO_INCREMENT for table `user_trucks`
--
ALTER TABLE `user_trucks`
  MODIFY `ID` int(11) NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=10;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `alerts`
--
ALTER TABLE `alerts`
  ADD CONSTRAINT `alerts_ibfk_1` FOREIGN KEY (`shipment_number`) REFERENCES `trips` (`shipment_number`) ON DELETE CASCADE;

--
-- Constraints for table `products`
--
ALTER TABLE `products`
  ADD CONSTRAINT `products_ibfk_1` FOREIGN KEY (`group_id`) REFERENCES `groups` (`ID`) ON DELETE SET NULL;

--
-- Constraints for table `reports`
--
ALTER TABLE `reports`
  ADD CONSTRAINT `reports_ibfk_1` FOREIGN KEY (`shipment_number`) REFERENCES `trips` (`shipment_number`) ON DELETE CASCADE;

--
-- Constraints for table `security_limits`
--
ALTER TABLE `security_limits`
  ADD CONSTRAINT `security_limits_ibfk_1` FOREIGN KEY (`shipment_number`) REFERENCES `trips` (`shipment_number`) ON DELETE CASCADE;

--
-- Constraints for table `sensors`
--
ALTER TABLE `sensors`
  ADD CONSTRAINT `sensors_ibfk_1` FOREIGN KEY (`truck_id`) REFERENCES `trucks` (`ID`) ON DELETE CASCADE;

--
-- Constraints for table `trips`
--
ALTER TABLE `trips`
  ADD CONSTRAINT `trips_ibfk_1` FOREIGN KEY (`user_truck_id`) REFERENCES `user_trucks` (`ID`) ON DELETE CASCADE;

--
-- Constraints for table `trip_counter`
--
ALTER TABLE `trip_counter`
  ADD CONSTRAINT `trip_counter_ibfk_1` FOREIGN KEY (`truck_id`) REFERENCES `trucks` (`ID`) ON DELETE CASCADE,
  ADD CONSTRAINT `trip_counter_ibfk_2` FOREIGN KEY (`user_id`) REFERENCES `users` (`ID`) ON DELETE CASCADE;

--
-- Constraints for table `updates`
--
ALTER TABLE `updates`
  ADD CONSTRAINT `updates_ibfk_1` FOREIGN KEY (`truck_id`) REFERENCES `trucks` (`ID`) ON DELETE CASCADE,
  ADD CONSTRAINT `updates_ibfk_2` FOREIGN KEY (`admin_id`) REFERENCES `users` (`ID`) ON DELETE CASCADE;

--
-- Constraints for table `user_trucks`
--
ALTER TABLE `user_trucks`
  ADD CONSTRAINT `user_trucks_ibfk_1` FOREIGN KEY (`user_id`) REFERENCES `users` (`ID`) ON DELETE CASCADE,
  ADD CONSTRAINT `user_trucks_ibfk_2` FOREIGN KEY (`truck_id`) REFERENCES `trucks` (`ID`) ON DELETE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
