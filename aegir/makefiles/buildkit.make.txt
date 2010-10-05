; This file describes the core project requirements for BuildKit 7.x. Several
; patches against Drupal core and their associated issue numbers have been
; included here for reference.
;
; Use this file to build a full distro including Drupal core (with patches) and
; the BuildKit install profile using the following command:
;
;     $ drush make distro.make [directory]
;
; URL: http://drupalcode.org/viewvc/drupal/contributions/profiles/buildkit/distro.make?view=co&pathrev=DRUPAL-7--2-0-BETA1
; Revision 1.1.2.4
; See also: http://developmentseed.org/blog/2010/sep/30/features-and-exportables-drupal-7
;

api = 2
core = 7.x

projects[drupal][type] = core
projects[drupal][download][type] = cvs
projects[drupal][download][root] = :pserver:anonymous:anonymous@cvs.drupal.org:/cvs/drupal
projects[drupal][download][module] = drupal
projects[drupal][download][date] = 2010-09-29

; Create new boolean field "Cannot create references to/from string offsets nor overloaded objects"
; http://drupal.org/node/913528
projects[drupal][patch][913528] = http://drupal.org/files/issues/process-with-test.patch

; Exportability of vocabularies is ruined by taxo field 'allowed vocabs' settings
; http://drupal.org/node/881530
projects[drupal][patch][881530] = http://drupal.org/files/issues/881530_vocabulary_field_machine_names.6.patch

; Make system directories configurable to allow tests in profiles/[name]/modules to be run.
; http://drupal.org/node/911354
projects[drupal][patch][911354] = http://drupal.org/files/issues/search_path_4.patch

; Text formats need a machine name
; http://drupal.org/node/903730
projects[drupal][patch][903730] = http://drupal.org/files/issues/drupal.filter-format-machine-name.13.patch

projects[buildkit][type] = profile
projects[buildkit][download][type] = cvs
projects[buildkit][download][module] = contributions/profiles/buildkit
projects[buildkit][download][revision] = DRUPAL-7--2-0-BETA1
