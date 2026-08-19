ALTER TABLE `mdt_patrols`
  ADD COLUMN IF NOT EXISTS `agency` varchar(16) DEFAULT NULL AFTER `job_type`;

CREATE INDEX IF NOT EXISTS `idx_mdt_patrols_agency_sort`
  ON `mdt_patrols` (`agency`, `sort_order`);

UPDATE `mdt_officer_status`
SET `status` = 'available'
WHERE `status` = 'active';

ALTER TABLE `mdt_officer_status`
  ALTER `status` SET DEFAULT 'available';
