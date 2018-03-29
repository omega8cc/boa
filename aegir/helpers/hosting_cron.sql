CREATE TABLE IF NOT EXISTS `hosting_cron` (
  `nid` int(10) unsigned NOT NULL DEFAULT '0',
  `cron_interval` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`nid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
