-- ps-mdt ESX Legacy compatibility layer
--
-- Import sql/qbx.sql first to install the shared MDT tables, then import this
-- file. This file is safe to run after an accidental/partial qbx.sql import.

ALTER TABLE `mdt_impound`
  MODIFY COLUMN `vehicleid` varchar(20) NOT NULL;

ALTER TABLE `owned_vehicles`
  ADD COLUMN IF NOT EXISTS `mdt_vehicle_information` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `mdt_vehicle_points` int(11) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `mdt_vehicle_status` varchar(500) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT 'valid',
  ADD COLUMN IF NOT EXISTS `mdt_vehicle_stolen` tinyint(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `mdt_vehicle_boloactive` tinyint(1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS `mdt_vehicle_image` varchar(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;

ALTER TABLE `jobs`
  ADD COLUMN IF NOT EXISTS `type` varchar(50) NOT NULL DEFAULT 'civ';
UPDATE `jobs` SET `type` = 'leo' WHERE `name` = 'police' AND `type` = 'civ';
UPDATE `jobs` SET `type` = 'ems' WHERE `name` = 'ambulance' AND `type` = 'civ';

ALTER TABLE `users`
  ADD COLUMN IF NOT EXISTS `metadata` longtext DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS `phone_number` varchar(20) DEFAULT NULL;

-- ESX multicharacter identifiers can exceed the 50-character Qbox citizen ID
-- size. Keep every identity-bearing MDT column wide enough for char#:license:...
-- MariaDB does not allow either side of a foreign key to be modified while
-- the constraint exists, even when FOREIGN_KEY_CHECKS is disabled. Drop only
-- the six profile/citizen constraints here and restore them below. IF EXISTS
-- makes this block safe to rerun after a partially completed migration.
ALTER TABLE `mdt_messages`
  DROP FOREIGN KEY IF EXISTS `FK_mdt_messages_sender`,
  DROP FOREIGN KEY IF EXISTS `FK_mdt_messages_receiver`;
ALTER TABLE `mdt_reports_warrants`
  DROP FOREIGN KEY IF EXISTS `FK_mdt_reports_warrants_mdt_profiles`;
ALTER TABLE `mdt_arrests`
  DROP FOREIGN KEY IF EXISTS `FK_mdt_arrests_profiles`;
ALTER TABLE `mdt_case_officers`
  DROP FOREIGN KEY IF EXISTS `FK_mdt_case_officers_profiles`;
ALTER TABLE `mdt_weapons`
  DROP FOREIGN KEY IF EXISTS `FK_mdt_weapons_mdt_profiles`;

ALTER TABLE `mdt_profiles` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_messages`
  MODIFY `sender_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  MODIFY `receiver_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_profile_sessions` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_reports_charges` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_reports_involved` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_reports_warrants` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT '';
ALTER TABLE `mdt_arrests`
  MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  MODIFY `officer_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_case_officers` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_case_notes` MODIFY `author_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_evidence_custody`
  MODIFY `from_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  MODIFY `to_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_audit_logs` MODIFY `actor_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_weapons` MODIFY `owner` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_weapon_ownership_history` MODIFY `owner` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_bolos` MODIFY `subject_id` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_impound`
  MODIFY `officer_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL,
  MODIFY `released_by_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_report_vehicles` MODIFY `owner_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_citizen_licenses` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_ia_complaints` MODIFY `complainant_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_ia_notes` MODIFY `author_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_ppr`
  MODIFY `officer_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  MODIFY `author_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_ppr_notes` MODIFY `author_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_fto_assignments`
  MODIFY `trainee_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  MODIFY `trainer_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_fto_dors` MODIFY `author_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_sop_acknowledgements` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_court_cases` MODIFY `defendant_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_court_orders` MODIFY `target_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_legal_documents` MODIFY `author_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_warrant_requests`
  MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL,
  MODIFY `reviewer_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci DEFAULT NULL;
ALTER TABLE `mdt_warrant_reviews` MODIFY `reviewer_citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;
ALTER TABLE `mdt_court_attendees` MODIFY `citizenid` varchar(80) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL;

ALTER TABLE `mdt_messages`
  ADD CONSTRAINT `FK_mdt_messages_sender` FOREIGN KEY (`sender_citizenid`) REFERENCES `mdt_profiles` (`citizenid`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_mdt_messages_receiver` FOREIGN KEY (`receiver_citizenid`) REFERENCES `mdt_profiles` (`citizenid`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `mdt_reports_warrants`
  ADD CONSTRAINT `FK_mdt_reports_warrants_mdt_profiles` FOREIGN KEY (`citizenid`) REFERENCES `mdt_profiles` (`citizenid`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `mdt_arrests`
  ADD CONSTRAINT `FK_mdt_arrests_profiles` FOREIGN KEY (`citizenid`) REFERENCES `mdt_profiles` (`citizenid`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `mdt_case_officers`
  ADD CONSTRAINT `FK_mdt_case_officers_profiles` FOREIGN KEY (`citizenid`) REFERENCES `mdt_profiles` (`citizenid`) ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE `mdt_weapons`
  ADD CONSTRAINT `FK_mdt_weapons_mdt_profiles` FOREIGN KEY (`owner`) REFERENCES `mdt_profiles` (`citizenid`) ON DELETE NO ACTION ON UPDATE CASCADE;

CREATE OR REPLACE VIEW `players` AS
SELECT
  u.`identifier` AS `citizenid`,
  JSON_OBJECT(
    'firstname', COALESCE(u.`firstname`, ''),
    'lastname', COALESCE(u.`lastname`, ''),
    'birthdate', u.`dateofbirth`,
    'gender', u.`sex`,
    'phone', u.`phone_number`
  ) AS `charinfo`,
  JSON_OBJECT(
    'name', u.`job`,
    'label', COALESCE(j.`label`, u.`job`),
    'type', COALESCE(j.`type`, 'civ'),
    'onduty', COALESCE(JSON_EXTRACT(NULLIF(u.`metadata`, ''), '$.jobDuty'), TRUE),
    'isboss', COALESCE(jg.`name` = 'boss', FALSE),
    'grade', JSON_OBJECT(
      'level', COALESCE(u.`job_grade`, 0),
      'name', COALESCE(jg.`name`, CAST(u.`job_grade` AS CHAR)),
      'label', COALESCE(jg.`label`, CAST(u.`job_grade` AS CHAR))
    )
  ) AS `job`,
  COALESCE(NULLIF(u.`metadata`, ''), '{}') AS `metadata`
FROM `users` u
LEFT JOIN `jobs` j ON j.`name` = u.`job`
LEFT JOIN `job_grades` jg ON jg.`job_name` = u.`job` AND jg.`grade` = u.`job_grade`;

CREATE OR REPLACE ALGORITHM=MERGE VIEW `player_vehicles` AS
SELECT
  ov.`plate` AS `id`,
  ov.`owner` AS `citizenid`,
  ov.`plate` AS `plate`,
  ov.`vehicle` AS `vehicle`,
  ov.`stored` AS `state`,
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(ov.`vehicle`, '$.fuelLevel')), 100) AS `fuel`,
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(ov.`vehicle`, '$.engineHealth')), 1000) AS `engine`,
  COALESCE(JSON_UNQUOTE(JSON_EXTRACT(ov.`vehicle`, '$.bodyHealth')), 1000) AS `body`,
  ov.`mdt_vehicle_information`,
  ov.`mdt_vehicle_points`,
  ov.`mdt_vehicle_status`,
  ov.`mdt_vehicle_stolen`,
  ov.`mdt_vehicle_boloactive`,
  ov.`mdt_vehicle_image`
FROM `owned_vehicles` ov;
