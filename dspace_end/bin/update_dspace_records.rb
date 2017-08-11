#!/usr/bin/ruby
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# PURPOSE
# To import new and updated ReDBox metadata into the DSpace dataset-collection.
#
# NOTE
# - The ReDBox ID is the published ReDBox handle. Note that the handle is 
#   assigned immediately after the Publish button is clicked for the dataset
#   (even if the whole set of curated records including people, groups and
#   activities have not yet been curated).
# - The DSpace ID is the published DSpace handle.
#
# SYSTEM ALGORITHM
# - Extract ReDBox dataset records from ReDBox:
#   * Only extract if a handle (ReDBox ID) has been assigned.
#   * Only extract if "dspace" appears in a Notes field within the Notes tab.
#   * Crosswalk the metadata fields into DSpace BMET CSV format.
#   * Name the resulting file redbox_export.csv
#   * The CSV will contain a ReDBox ID. It may contain a DSpace ID if
#     manually added into ReDBox since the creation of the dataset.
#   * Transfer the file to the DSpace server.
# - Run this program:
#   * Export DSpace records from the dataset-collection:
#     + Use the BMET (Batch Metadata Editing Tool)
#     + Name the resulting file dspace_export.csv
#     + The CSV will contain both a ReDBox ID & DSpace ID.
#   * Create a BMET result-CSV as follows:
#     + Examine ReDBox IDs from both redbox_export.csv & dspace_export.csv
#     + If the ReDBox ID is in redbox_export.csv but not in dspace_export.csv,
#       then add the record to DSpace (ie. a "+" in the "id" column).
#     + If the ReDBox ID is in both redbox_export.csv and dspace_export.csv,
#       then update the record in DSpace (ie. the DSpace item-ID in the
#       "id" column).
#   * Import the BMET result-CSV into DSpace.
#
# FIXME:
# - Check what happens if we do BMET load of dc.contributor.author[en_US]
#   but the DSpace record already has dc.contributor.author. I suspect we
#   get duplicate metadata for multi-valued fields.
#
##############################################################################
# Add dirs to the library path
$: << File.expand_path("../etc", File.dirname(__FILE__))
$: << File.expand_path("../lib", File.dirname(__FILE__))
$: << File.expand_path("../lib/libext", File.dirname(__FILE__))

require "faster_csv"
require "dspace_utils"
require "object_extra"
require "common_config"
require "bmet_csv"

##############################################################################
class BmetCsvPair
  include CommonConfig

  DEBUG = false

  attr_reader :dspace_csv_fpath, :redbox_csv_fpath, :dspace_csv_result_fpath

  ############################################################################
  def initialize(redbox_csv_fpath, dspace_csv_fpath, dspace_csv_result_fpath)
    @dspace_csv_fpath = dspace_csv_fpath
    @redbox_csv_fpath = redbox_csv_fpath

    @dspace_csv_result_fpath = dspace_csv_result_fpath
    allow_write_dspace_csv_result
  end

  ############################################################################
  def parse_bmet_csv_objects
    @ds_bmet = BmetCsv.new(@dspace_csv_fpath)
    @rb_bmet = BmetCsv.new(@redbox_csv_fpath)
  end

  ############################################################################
  # FIXME: Do extra checks. Eg.
  # - Warn if new record but already has DSpace ID
  # - Warn if 2 DS records have same RB ID (or same DS ID). Crosswalk/autoload fault.
  # - Warn if 2 RB records have same DS ID (or same RB ID). Data entry fault.
  # - Warn if duplicated DS ID or RB ID. Crosswalk/autoload bug.
  def verify
    new_rb_id_list = @rb_bmet.redbox_ids - @ds_bmet.redbox_ids
    update_rb_id_list = @rb_bmet.redbox_ids - new_rb_id_list
    if DEBUG
      puts
      puts "@ds_bmet.redbox_ids=#{@ds_bmet.redbox_ids.inspect}"
      puts "@rb_bmet.redbox_ids=#{@rb_bmet.redbox_ids.inspect}"
      puts
      puts "new_rb_id_list=#{new_rb_id_list.inspect}"
      puts "update_rb_id_list=#{update_rb_id_list.inspect}"
      puts
    end
  end

  ############################################################################
  def process_redbox_records
    @rb_bmet.enhance_redbox_bmet_csv(@ds_bmet)
  end

  ############################################################################
  def to_s
    @rb_bmet.to_s
  end

  ############################################################################
  def allow_write_dspace_csv_result
    will_allow = FORCE_OVERWRITE_DSPACE_CSV_RESULT || !File.exists?(@dspace_csv_result_fpath)
    unless will_allow
      STDERR.puts "ERROR: DSpace CSV result-file already exists at path below."
      STDERR.puts "CSV path: #{@dspace_csv_result_fpath}"
      STDERR.puts "You can overwrite by setting FORCE_OVERWRITE_DSPACE_CSV_RESULT."
      exit 1
    end
    will_allow
  end

  ############################################################################
  def write_csv_result
    File.write_string(@dspace_csv_result_fpath, to_s) if allow_write_dspace_csv_result
  end

  ############################################################################
  def export_from_dspace
    cmd = "%s -f \"%s\" -i \"%s\" > \"%s\" 2> \"%s\"" % [
      DS_EXP_CMD, @dspace_csv_fpath, DSPACE_DATASET_COLLECTION_HDL,
      DS_EXP_LOG, DS_EXP_LOG2
    ]
    error_msg = "DSpace BMET export failed with exit-code {{res.exitstatus}}. See file #{File.basename(DS_EXP_LOG2)}"
    self.class.run_simple_system_command(cmd, error_msg)
  end

  ############################################################################
  def import_into_dspace
    cmd = "%s |%s -f \"%s\" -e \"%s\" > \"%s\" 2> \"%s\"" % [
      DS_IMP_ECHO_YES_NO_CMD,
      DS_IMP_CMD, @dspace_csv_result_fpath, DS_IMP_USER_EMAIL,
      DS_IMP_LOG, DS_IMP_LOG2
    ]
    error_msg = "DSpace BMET import failed with exit-code {{res.exitstatus}}. See file #{File.basename(DS_IMP_LOG2)}"
    self.class.run_simple_system_command(cmd, error_msg)
  end

  ############################################################################
  # Class methods
  ############################################################################
  def self.run_simple_system_command(cmd, msg_bad_exitstatus)
    puts "cmd: '#{cmd}'" if DEBUG
    `#{cmd}`
    res = $?
    unless res.exitstatus == 0
      if msg_bad_exitstatus.to_s.empty?
        STDERR.puts "Command: '#{cmd}'"
        STDERR.puts "ERROR: The above command failed with exit-code #{res.exitstatus}."
      else
        STDERR.puts msg_bad_exitstatus.gsub(/\{\{res.exitstatus\}\}/, res.exitstatus.to_s)
      end
      exit res.exitstatus
    end
  end

  ############################################################################
  def self.main
    $SAFE = 2
    redbox_csv_fpath = "#{ROOT_DIR}/result/redbox_export.csv"
    dspace_csv_fpath = "#{ROOT_DIR}/result/dspace_export.csv"
    dspace_csv_result_fpath = "#{ROOT_DIR}/result/dspace_result.csv"

    pair = BmetCsvPair.new(redbox_csv_fpath, dspace_csv_fpath, dspace_csv_result_fpath)
    # Assume ReDBox export/crosswalk CSV already exists.
    pair.export_from_dspace		# Creates the DSpace export-CSV
    pair.parse_bmet_csv_objects		# Creates objects for both CSVs
    pair.verify
    pair.process_redbox_records

    puts "Writing new DSpace-BMET CSV to #{File.basename(pair.dspace_csv_result_fpath)}"
    pair.write_csv_result
    pair.import_into_dspace
  end
end

##############################################################################
# Main()
##############################################################################
$SAFE = 1
BmetCsvPair.main

