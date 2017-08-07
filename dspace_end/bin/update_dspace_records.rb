#!/usr/bin/ruby
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# PURPOSE
# To import new and updated ReDBox metadata into the DSpace dataset collection.
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
# - Extract DSpace records from the dataset collection:
#   * Use the BMET (Batch Metadata Editing Tool)
#   * Name the resulting file dspace_export.csv
#   * The CSV will contain both a ReDBox ID & DSpace ID.
# - Run this program:
#   * Extract ReDBox IDs from redbox_export.csv
#   * Extract ReDBox IDs from dspace_export.csv
#   * For a new record (ie. ReDBox ID in redbox_export.csv but not in
#     dspace_export.csv) then add the record into DSpace.
#   * For an updated record (ie. ReDBox ID in both redbox_export.csv and
#     dspace_export.csv) then update the record in DSpace.
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
require "bmet_csv"

##############################################################################
class BmetCsvPair
  DEBUG = false

  ############################################################################
  def initialize(ds_csv_fpath, rb_csv_fpath)
    @ds_csv_fpath = ds_csv_fpath
    @rb_csv_fpath = rb_csv_fpath

    @ds_bmet = BmetCsv.new(@ds_csv_fpath)
    @rb_bmet = BmetCsv.new(@rb_csv_fpath)
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

end

##############################################################################
# Main()
##############################################################################
root_dir = File.expand_path("..", File.dirname(__FILE__))
ds_csv_fpath = "#{root_dir}/result/dspace_export.csv"
rb_csv_fpath = "#{root_dir}/result/redbox_export.csv"

pair = BmetCsvPair.new(ds_csv_fpath, rb_csv_fpath)
pair.verify
pair.process_redbox_records

puts "OUTPUT BMET CSV:"
puts pair

