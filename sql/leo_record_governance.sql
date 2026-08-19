ALTER TABLE `mdt_reports`
  ADD COLUMN IF NOT EXISTS `owning_agency` varchar(16) DEFAULT NULL AFTER `authorplaintext`,
  ADD COLUMN IF NOT EXISTS `task_force_id` char(36) DEFAULT NULL AFTER `owning_agency`,
  ADD COLUMN IF NOT EXISTS `lifecycle_status` enum('draft','submitted','approved','closed','voided') NOT NULL DEFAULT 'submitted' AFTER `task_force_id`,
  ADD COLUMN IF NOT EXISTS `version` int(10) unsigned NOT NULL DEFAULT 1 AFTER `lifecycle_status`;

ALTER TABLE `mdt_cases`
  ADD COLUMN IF NOT EXISTS `owning_agency` varchar(16) DEFAULT NULL AFTER `assigned_department`,
  ADD COLUMN IF NOT EXISTS `task_force_id` char(36) DEFAULT NULL AFTER `owning_agency`,
  ADD COLUMN IF NOT EXISTS `lifecycle_status` enum('active','closed','voided') NOT NULL DEFAULT 'active' AFTER `task_force_id`,
  ADD COLUMN IF NOT EXISTS `version` int(10) unsigned NOT NULL DEFAULT 1 AFTER `lifecycle_status`;

ALTER TABLE `mdt_bolos`
  ADD COLUMN IF NOT EXISTS `owning_agency` varchar(16) DEFAULT NULL AFTER `status`,
  ADD COLUMN IF NOT EXISTS `task_force_id` char(36) DEFAULT NULL AFTER `owning_agency`,
  ADD COLUMN IF NOT EXISTS `created_by` varchar(50) DEFAULT NULL AFTER `task_force_id`,
  ADD COLUMN IF NOT EXISTS `lifecycle_status` enum('active','closed','voided') NOT NULL DEFAULT 'active' AFTER `created_by`,
  ADD COLUMN IF NOT EXISTS `version` int(10) unsigned NOT NULL DEFAULT 1 AFTER `lifecycle_status`,
  ADD COLUMN IF NOT EXISTS `created_at` timestamp NOT NULL DEFAULT current_timestamp() AFTER `version`,
  ADD COLUMN IF NOT EXISTS `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp() AFTER `created_at`;

ALTER TABLE `mdt_evidence_items`
  ADD COLUMN IF NOT EXISTS `owning_agency` varchar(16) DEFAULT NULL AFTER `created_by`,
  ADD COLUMN IF NOT EXISTS `task_force_id` char(36) DEFAULT NULL AFTER `owning_agency`,
  ADD COLUMN IF NOT EXISTS `compartment` varchar(64) DEFAULT NULL AFTER `task_force_id`,
  ADD COLUMN IF NOT EXISTS `lifecycle_status` enum('active','released','disposed','voided') NOT NULL DEFAULT 'active' AFTER `compartment`,
  ADD COLUMN IF NOT EXISTS `version` int(10) unsigned NOT NULL DEFAULT 1 AFTER `lifecycle_status`;

CREATE TABLE IF NOT EXISTS `mdt_record_revisions` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `record_type` enum('case','report','bolo','evidence') NOT NULL,
  `record_id` int(10) unsigned NOT NULL,
  `revision_number` int(10) unsigned NOT NULL,
  `action` varchar(64) NOT NULL,
  `author_citizenid` varchar(50) NOT NULL,
  `author_name` varchar(100) DEFAULT NULL,
  `author_agency` varchar(16) NOT NULL,
  `reason` varchar(500) NOT NULL,
  `before_json` longtext DEFAULT NULL,
  `after_json` longtext DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_mdt_record_revision` (`record_type`,`record_id`,`revision_number`),
  KEY `idx_mdt_record_revision_author` (`author_citizenid`),
  KEY `idx_mdt_record_revision_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `mdt_record_supplements` (
  `id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `record_type` enum('case','report','bolo','evidence') NOT NULL,
  `record_id` int(10) unsigned NOT NULL,
  `author_citizenid` varchar(50) NOT NULL,
  `author_name` varchar(100) DEFAULT NULL,
  `author_agency` varchar(16) NOT NULL,
  `content` text NOT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
  PRIMARY KEY (`id`),
  KEY `idx_mdt_record_supplement_record` (`record_type`,`record_id`,`created_at`),
  KEY `idx_mdt_record_supplement_author` (`author_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

UPDATE `mdt_reports` SET `owning_agency` = 'brpd' WHERE `owning_agency` IS NULL OR `owning_agency` = '';
UPDATE `mdt_cases` SET `owning_agency` = LOWER(`assigned_department`) WHERE (`owning_agency` IS NULL OR `owning_agency` = '') AND LOWER(`assigned_department`) IN ('brpd','ebrso','lsp');
UPDATE `mdt_cases` SET `owning_agency` = 'brpd' WHERE `owning_agency` IS NULL OR `owning_agency` = '';
UPDATE `mdt_bolos` SET `owning_agency` = 'brpd' WHERE `owning_agency` IS NULL OR `owning_agency` = '';
UPDATE `mdt_evidence_items` evidence
LEFT JOIN `mdt_cases` case_record ON case_record.id = evidence.case_id
LEFT JOIN `mdt_reports` report_record ON report_record.id = evidence.report_id
SET evidence.owning_agency = COALESCE(case_record.owning_agency, report_record.owning_agency, 'brpd')
WHERE evidence.owning_agency IS NULL OR evidence.owning_agency = '';
