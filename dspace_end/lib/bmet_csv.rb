#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# PURPOSE
# A class to process a DSpace BMET (Batch Metadata Editing Tool) CSV file
# in the context of transferring metadata from ReDBox to DSpace.
#
##############################################################################
require "faster_csv"
require "dspace_utils"
require "common_config"

##############################################################################
class BmetCsv
  include DSpaceUtils
  include CommonConfig

  DEBUG = false

  attr_reader :ids

  ############################################################################
  def initialize(csv_fpath)
    @csv_fpath = csv_fpath
    @ids = []
    @s_bmet_csv = nil
    extract_ids
    printf "self=%s\n\n", self.inspect if DEBUG
  end

  ############################################################################
  def extract_ids
    @ids = []
    FasterCSV.foreach(@csv_fpath, FCSV_IN_OPTS){|line|
      ds_item_id = line['id'].to_s.empty? ? nil : line['id']
      redbox_id, dspace_id = self.class.get_redbox_id_dspace_id_from_csv_line(line)
      @ids << {
        :ds_item_id => ds_item_id,
        :dspace_id  => dspace_id,
        :redbox_id  => redbox_id,
      } if ds_item_id || redbox_id || dspace_id
    }
    @ids
  end

  ############################################################################
  def item_ids_by_redbox_id
    @ids.inject({}){|hacc,hid| hacc[ hid[:redbox_id] ] = hid[:ds_item_id]; hacc}
  end

  ############################################################################
  def dspace_ids_by_redbox_id
    @ids.inject({}){|hacc,hid| hacc[ hid[:redbox_id] ] = hid[:dspace_id]; hacc}
  end

  ############################################################################
  def redbox_ids
    @ids.inject([]){|a,hid| a << hid[:redbox_id] if hid[:redbox_id]; a}
  end

  ############################################################################
  # This method must be invoked for a ReDBox (not DSpace) BmetCsv object. (A
  # ReDBox BMET CSV is created by running a crosswalk program against ReDBox
  # metadata.) The method argument must be a DSpace (not ReDBox) BmetCsv object.
  #
  # The main purpose of this method is to copy columns from the input CSV to
  # the output CSV with the following enhancements:
  # - 2 columns will be added to the output CSV ("id" and "collection")
  # - the REDBOX_DSPACE_ID_FIELD column sometimes requires a minor update
  def enhance_redbox_bmet_csv(dspace_bmet)
    # Create an object to store all lines of the *output* CSV
    headers = nil
    line_num = 0
    ds_item_ids = dspace_bmet.item_ids_by_redbox_id	# Lookup via DSpace CSV
    ds_dspace_ids = dspace_bmet.dspace_ids_by_redbox_id	# Lookup via DSpace CSV

    @s_bmet_csv = FasterCSV.generate(FCSV_OUT_OPTS){|csv_out_lines| 
      # Iterate thru each *input* object
      FasterCSV.foreach(@csv_fpath, FCSV_IN_OPTS){|line|
        line_num += 1
        # Start with the CSV header line
        csv_out_lines << ["id", "collection"] + line.headers if line_num == 1

        # "id" column: *update* DSpace record if there is a DSpace item_id;
        # else *add* a DSpace record
        line_out = []					# An array of columns
        # redbox_id from the ReDBox CSV; corresponding dspace_id from the DSpace CSV
        redbox_id, _ = self.class.get_redbox_id_dspace_id_from_csv_line(line)
        dspace_id = ds_dspace_ids[redbox_id]
        line_out << (ds_item_ids[redbox_id] ? ds_item_ids[redbox_id] : "+")

        # "collection" column
        line_out << DSPACE_DATASET_COLLECTION_HDL

        # Copy each column of the input CSV to the output CSV
        line.headers.each{|key|
          # When a new DSpace record is created/published, a DSpace ID
          # (ie. handle) is automatically added to dc.identifier.uri.
          # When an existing DSpace record is updated, we need to add
          # the DSpace ID ourselves (to the ReDBox BMET CSV).
          will_add_dspace_id = false
          if key == REDBOX_DSPACE_ID_FIELD && dspace_id && !line[key].to_s.empty?
            will_add_dspace_id = ! line[key].split(VALUE_DELIMITER).include?(dspace_id)
          end
          line_out << (will_add_dspace_id ? "#{line[key]}#{VALUE_DELIMITER}#{dspace_id}" : line[key])
        }
        csv_out_lines << line_out
      }
    }
    @s_bmet_csv
  end

  ############################################################################
  def to_s
    @s_bmet_csv
  end

  ############################################################################
  # Class methods

  ############################################################################
  def self.get_redbox_id_dspace_id_from_csv_line(fcsv_line)
    redbox_id = nil
    dspace_id = nil

    s_subfields = fcsv_line[REDBOX_DSPACE_ID_FIELD]
    return [redbox_id, dspace_id] if s_subfields.to_s.empty?

    s_subfields.split(VALUE_DELIMITER).each{|subfield|
      redbox_id = subfield if subfield.match(REDBOX_HDL_URL_REGEX)
      dspace_id = subfield if subfield.match(DSPACE_HDL_URL_REGEX)
    }
    [redbox_id, dspace_id]
  end

end

