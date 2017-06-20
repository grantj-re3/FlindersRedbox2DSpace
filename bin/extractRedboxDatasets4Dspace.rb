#!/usr/bin/ruby
#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# PURPOSE
# Extract ReDBox metadata which is intended for loading into DSpace.
# Output the info in DSpace Batch Metadata Editing Tool (BMET) CSV format,
# with one record per line (with a header line). Extract the info from the
# ReDBox storage dir.
#
# ALGORITHM
# - Find ReDBox records which:
#   * are datasets (ie. not Data Management Plans or Self-subs)
#   * have a handle assigned (but may not have completed curation)
#   * contain "dspace" in the ReDBox Notes-tab
# - Extract metadata for each record.
# - Output metadata in DSpace BMET CSV format.
# - Sort records so they are in a repeatable record-order.
# - Write CSV header and records to STDOUT.
#
# GOTCHAS
# - The Ruby JSON gem was unable to parse ReDBox JSON files, so the
#   Ruby YAML stdlib class was used instead. See get_pkg_metadata()
#   for more details.
#
# TEST ENVIRONMENT
# - ruby 1.8.7 (2013-06-27 patchlevel 374) [x86_64-linux]
# - ReDBox 1.6.1 & 1.8; java version 1.6.0_30
# - Red Hat Enterprise Linux Server release 6.9 (Santiago)
# - Linux 2.6.32-642.13.1.el6.x86_64 #1 SMP Wed Nov 23 16:03:01 EST 2016 x86_64 x86_64 x86_64 GNU/Linux
#
##############################################################################

# Add dirs to the library path
$: << File.expand_path("../lib", File.dirname(__FILE__))
$: << File.expand_path("../lib/libext", File.dirname(__FILE__))

require "yaml"
require "find"

require "faster_csv"
require "dspace_utils"

##############################################################################
class RedboxDataset4Dspace
  include DSpaceUtils

  DEBUG = false

  FPATH_REDBOX_STORAGE = "/PATH/TO/REDBOX/storage"
  FNAME_OBJECT = "TF-OBJ-META"
  FNAME_VPKG_INDEX = "tfpackage_Version_Index.json"

  REGEX_TARGET_NOTE = /(^|[^a-z])dspace($|[^a-z])/i
  DOI_CITATION_LHS = "http://dx.doi.org/"

  # FIXME: Perhaps dc.language.iso rather than "dc.language?
  CSV_OUT_FIELDS = [
    # CSV columns will appear in the order below.
    #
    # Element 1: Says whether the input-field value obtained via the
    #   Metadata-key (column 2) is a single string or an array of
    #   strings.
    # Element 2: Gives the key into the @metadata hash for this field.
    # Element 3: Gives the output-CSV column name for this field.
    #
    # [Multi-1-value,	Metadata-key,		CSV-out-column-name]
    [:single_value,	:dc_title,		"dc.title[en_US]"],
    [:single_value,	:dc_type,		"dc.type[en_US]"],
    [:single_value,	:dc_created,		"dc.date"],

    [:multi_value,	:dc_creators,		"dc.creator[en_US]"],
    [:multi_value,	:ident_uris,		"dc.identifier.uri"],
    [:single_value,	:citation,		"dc.identifier.citation[en_US]"],
    [:multi_value,	:dc_rights,		"dc.rights[en_US]"],


    [:multi_value,	:funders,		"dc.description.sponsorship[en_US]"],
    [:multi_value,	:grant_numbers,		"dc.relation.grantnumber[en_US]"],
    [:multi_value,	:subjects,		"dc.subject[en_US]"],

    [:single_value,	:dc_language,		"dc.language[en_US]"],
    [:single_value,	:dc_description,	"dc.description[en_US]"],
  ]
  # Arrays derived from the above table
  CSV_OUT_HEADERS  = CSV_OUT_FIELDS.map{|(m1val, key, col)| col}
  CSV_INPUT_FIELDS = CSV_OUT_FIELDS.map{|(m1val, key, col)| key}
  MULTI_VALUE_INPUT_FIELDS  = CSV_OUT_FIELDS.inject([]){|a,(m1val, key, col)|
    a << key if m1val == :multi_value; a
  }
  SINGLE_VALUE_INPUT_FIELDS = CSV_OUT_FIELDS.inject([]){|a,(m1val, key, col)|
    a << key if m1val == :single_value; a
  }

  # FasterCSV options for writing CSV to output
  FCSV_OUT_OPTS = {
    :col_sep => ',',
    :headers => true,
    :force_quotes => true,
  }

  attr_reader :metadata

  ############################################################################
  def initialize(fpath_obj, fpath_pkg)
    @fpath_obj = fpath_obj
    if @fpath_obj.nil? || @fpath_obj.empty?
      STDERR.puts "ERROR: Object '#{self.class}' has an empty/nil file path to #{FNAME_OBJECT}."
      exit 1
    end

    @fpath_pkg = fpath_pkg
    if @fpath_pkg.nil? || @fpath_pkg.empty?
      STDERR.puts "ERROR: Object '#{self.class}' has an empty/nil file path to FILE.tfpackage"
      exit 1
    end
    @metadata = {}

    if DEBUG
      puts "OBJ Path: #{@fpath_obj.inspect}"
      puts "PKG Path: #{@fpath_pkg.inspect}" 
      puts
    end
  end

  ############################################################################
  def extract_metadata
    get_obj_metadata
    get_pkg_metadata

    if @metadata[:citation]
      doi_url = @metadata[:doi] ? " #{DOI_CITATION_LHS}#{@metadata[:doi]}" : ""
      @metadata[:citation] = @metadata[:citation] % [doi_url]
    end
  end

  ############################################################################
  def get_obj_metadata
    obj_strings = File.open(@fpath_obj).read.split(NEWLINE)
    get_ident_uris(obj_strings)
  end

  ############################################################################
  def get_ident_uris(obj_strings)
    @metadata[:doi] = self.class.get_field(obj_strings, "andsDoi")
    @metadata[:handle] = self.class.get_field(obj_strings, "handle").to_s.gsub(/\\/, "")

    doi = @metadata[:doi]
    handle = @metadata[:handle]

    metadata_key = :ident_uris
    @metadata[metadata_key] = []
    @metadata[metadata_key] << handle unless handle.empty?
    @metadata[metadata_key] << "#{DOI_CITATION_LHS}#{doi}" if doi
  end

  ############################################################################
  def get_pkg_metadata
    # FIXME: The JSON gem parse() method in Ruby 1.8.7 throws an exception
    # if newlines are in JSON field values. YAML 1.2 is a superset of JSON,
    # so tried YAML (although Ruby 1.8.7 uses YAML 1.0). Newlines seem to be
    # converted into spaces, which is ok for me.
    pkg_str = File.open(@fpath_pkg).read
    pkg_json = YAML.load(pkg_str)		# Convert JSON to a hash

    @metadata[:dc_title] = pkg_json["dc:title"]
    @metadata[:dc_type] = pkg_json["dc:type.rdf:PlainLiteral"]
    @metadata[:dc_created] = pkg_json["dc:created"]
    @metadata[:dc_description] = pkg_json["dc:description"]
    @metadata[:dc_language] = pkg_json["dc:language.skos:prefLabel"]

    # Citation will be a printf format-string, hence "%s" will be replaced with DOI
    @metadata[:citation] = pkg_json["dc:biblioGraphicCitation.skos:prefLabel"].gsub(/ *\{ID_WILL_BE_HERE\}/, "%s")

    get_creators(pkg_json)
    get_rights(pkg_json)
    get_funders(pkg_json)
    get_grant_numbers(pkg_json)
    get_subjects(pkg_json)
  end

  ############################################################################
  def get_subjects(pkg_json)
    metadata_key = :subjects
    get_for_codes(pkg_json, metadata_key)
    get_seo_codes(pkg_json, metadata_key)
    get_keywords(pkg_json, metadata_key)
  end

  ############################################################################
  def get_for_codes(pkg_json, metadata_key)
    redbox_key = "dc:subject.anzsrc:for.%s.skos:prefLabel"	# printf format string
    regex = Regexp.new( Regexp.escape(redbox_key) % ["(\\d+)"] )
    index_max = self.class.get_max_index(pkg_json, regex)

    @metadata[metadata_key] ||= []
    (1..index_max).each{|i|
      redbox_ikey = redbox_key % [i.to_s]
      for_code = pkg_json[redbox_ikey].to_s.strip
      @metadata[metadata_key] << for_code unless for_code.empty?
    }
  end

  ############################################################################
  def get_seo_codes(pkg_json, metadata_key)
    redbox_key = "dc:subject.anzsrc:seo.%s.skos:prefLabel"	# printf format string
    regex = Regexp.new( Regexp.escape(redbox_key) % ["(\\d+)"] )
    index_max = self.class.get_max_index(pkg_json, regex)

    @metadata[metadata_key] ||= []
    (1..index_max).each{|i|
      redbox_ikey = redbox_key % [i.to_s]
      for_code = pkg_json[redbox_ikey].to_s.strip
      @metadata[metadata_key] << for_code unless for_code.empty?
    }
  end

  ############################################################################
  def get_keywords(pkg_json, metadata_key)
    redbox_key = "dc:subject.vivo:keyword.%s.rdf:PlainLiteral"	# printf format string
    regex = Regexp.new( Regexp.escape(redbox_key) % ["(\\d+)"] )
    index_max = self.class.get_max_index(pkg_json, regex)

    @metadata[metadata_key] ||= []
    (1..index_max).each{|i|
      redbox_ikey = redbox_key % [i.to_s]
      keyword = pkg_json[redbox_ikey].to_s.strip
      @metadata[metadata_key] << keyword unless keyword.empty?
    }
  end

  ############################################################################
  def get_creators(pkg_json)
    # Person names below are extracted from the ReDBox People-tab. This
    # is better than attempting to extract from the Citation-tab because:
    # - Names derived from Mint or NLA are less likely to contain typos
    # - Local-ReDBox names will also be included
    # - Sometimes there is no citation from which to derive names

    index_max = self.class.get_max_index(pkg_json, /dc:creator\.foaf:Person\.(\d+)\.foaf:(familyName|givenName)/)
    @metadata[:dc_creators] = []
    (1..index_max).each{|i|
      family_name = pkg_json["dc:creator.foaf:Person.#{i}.foaf:familyName"].to_s.strip
      given_names = pkg_json["dc:creator.foaf:Person.#{i}.foaf:givenName"].to_s.strip
      next if family_name.empty? && given_names.empty?

      @metadata[:dc_creators] << if !family_name.empty? && !given_names.empty?
        "#{family_name}, #{given_names}"
      elsif !family_name.empty?
        family_name
      else
        given_names
      end
    }
  end

  ############################################################################
  def get_rights(pkg_json)
    @metadata[:dc_rights] = []
    [
      "dc:accessRights.skos:prefLabel",
      "dc:accessRights.dc:RightsStatement.skos:prefLabel",
      "dc:license.skos:prefLabel",
    ].each{|key|
      value = pkg_json[key].to_s.strip
      @metadata[:dc_rights] << value unless value.empty?
    }
  end

  ############################################################################
  def get_funders(pkg_json)
    redbox_key = "foaf:fundedBy.foaf:Agent.%s.skos:prefLabel"	# printf format string
    regex = Regexp.new( Regexp.escape(redbox_key) % ["(\\d+)"] )
    index_max = self.class.get_max_index(pkg_json, regex)

    @metadata[:funders] = []
    (1..index_max).each{|i|
      redbox_ikey = redbox_key % [i.to_s]
      funder = pkg_json[redbox_ikey].to_s.strip
      @metadata[:funders] << funder unless funder.empty?
    }
  end

  ############################################################################
  def get_grant_numbers(pkg_json)
    index_max = self.class.get_max_index(pkg_json, /foaf:fundedBy\.vivo:Grant\.(\d+)\.(redbox:grantNumber|skos:prefLabel)/)
    @metadata[:grant_numbers] = []
    (1..index_max).each{|i|
      grant_number = pkg_json["foaf:fundedBy.vivo:Grant.#{i}.redbox:grantNumber"].to_s.strip
      grant_label = pkg_json["foaf:fundedBy.vivo:Grant.#{i}.skos:prefLabel"].to_s.strip
      next if grant_number.empty? && grant_label.empty?

      unless grant_label.empty?
        # Strip out Mint data-source. Eg. Remove "(MIS Projects) "
        # from "(MIS Projects) 12345 NHMRC Research Fellowship..."
        grant_label.match(/^\([^\)]*\) (.*)$/)
        grant_label = $1 if $1
      end

      @metadata[:grant_numbers] << if !grant_number.empty? && !grant_label.empty?
        "#{grant_number}: #{grant_label}"
      elsif !grant_number.empty?
        grant_number
      else
        grant_label
      end
    }
  end

  ############################################################################
  # Class methods
  ############################################################################
  def self.get_field(string_list, field_name)
    regex = /^#{Regexp.escape(field_name)}=/

    # string_list is an array of strings with format:  key=value
    line = string_list.find{|s| s.match(regex)}
    line ? line.gsub(regex, "") : nil
  end

  ############################################################################
  def self.get_max_index(json_hash, regex)
    # The regex arg is expected to enclose the key's integer index within the
    # first bracket. Eg. Use /pre\.(\d+)\.post/ to find elements:
    #     pre.1.post, pre.2.post, pre.3.post, ... pre.290.post
    # and return integer 290.
    index_list = json_hash.keys.inject([]){|accum,key|
      key.match(regex)
      accum << $1.to_i if $1
      accum
    }
    index_list.empty? ? 0 : index_list.max
  end

  ############################################################################
  def self.get_filepath_pkg(fpath_obj)
    obj_strings = File.open(fpath_obj).read.split(NEWLINE)
    fpath_other_pkg = get_field(obj_strings, "file.path")
    "%s/%s" % [File.dirname(fpath_obj), File.basename(fpath_other_pkg)]
  end

  ############################################################################
  def self.get_dspace_pkg(fpath_obj)
    fpath_pkg = get_filepath_pkg(fpath_obj)
    pkg_str = File.open(fpath_pkg).read
    pkg_json = YAML.load(pkg_str)			# Convert JSON to a hash

    # Return fpath_pkg if we match regex /dspace/i in a note.
    index_max = get_max_index(pkg_json, /skos:note.(\d+).dc:description/)
    found = false
    (1..index_max).each{|i| found = true if pkg_json["skos:note.#{i}.dc:description"].to_s.match(REGEX_TARGET_NOTE)}
    found ? fpath_pkg : nil

    #fpath_pkg	# FIXME: Return all datasets (instead of only those which match REGEX_TARGET_NOTE)
  end

  ############################################################################
  def self.get_file_paths
    fpaths4dspace = []
    fpaths_obj = []
    fpaths_pkg = []
    Find.find(FPATH_REDBOX_STORAGE){|fpath|
      next unless File.basename(fpath) == FNAME_OBJECT

      obj_strings = File.open(fpath).read.split(NEWLINE)
      is_dataset = get_field(obj_strings, "jsonConfigPid") == "dataset.json"
      has_handle = get_field(obj_strings, "handle").to_s.match(/^http/)
      next unless is_dataset && has_handle

      fpath_ds_pkg = get_dspace_pkg(fpath)
      fpaths_obj << fpath if fpath_ds_pkg
      fpaths_pkg << fpath_ds_pkg if fpath_ds_pkg

      fpaths4dspace << {:obj => fpath, :pkg => fpath_ds_pkg} if fpath_ds_pkg
    }
    fpaths4dspace
  end

  ############################################################################
  def self.metadata_to_bmet_csv(objs)
    # Create an object to store all lines of the *output* CSV
    csv_out_data = FasterCSV.generate(FCSV_OUT_OPTS){|csv_out_lines| 
      csv_out_lines << CSV_OUT_HEADERS		# Header line

      # Iterate thru each *input* object
      objs.sort{|a,b| a.metadata[:handle] <=> b.metadata[:handle]}.each{|obj|

        # Iterate thru each *output* column
        line_out = []
        CSV_INPUT_FIELDS.each{|key|
          if SINGLE_VALUE_INPUT_FIELDS.include?(key)
            line_out << obj.metadata[key]
          elsif MULTI_VALUE_INPUT_FIELDS.include?(key)
            line_out << obj.metadata[key].join(VALUE_DELIMITER)
          else
            line_out << "MISSING-FIELD #{key.inspect}"
          end
        }
        csv_out_lines << line_out
      }
    }
    csv_out_data
  end

end

##############################################################################
# Main
##############################################################################
# Extracting info from datasets
fpath_list = RedboxDataset4Dspace.get_file_paths
puts "fpath_list=#{fpath_list.inspect} [#{fpath_list.length}]" if RedboxDataset4Dspace::DEBUG

objs = fpath_list.inject([]){|list, fpaths|
  obj = RedboxDataset4Dspace.new(fpaths[:obj], fpaths[:pkg])
  obj.extract_metadata
  list << obj
}

puts RedboxDataset4Dspace.metadata_to_bmet_csv(objs)

