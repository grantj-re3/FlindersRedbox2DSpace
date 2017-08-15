#
# Copyright (c) 2017, Flinders University, South Australia. All rights reserved.
# Contributors: Library, Corporate Services, Flinders University.
# See the accompanying LICENSE file (or http://opensource.org/licenses/BSD-3-Clause).
#
# Common config vars for ruby
#
# The constants which are most likely to require customisation during
# installation have been marked with "CUSTOMISE" below.
#
##############################################################################
module CommonConfig
  # Root of this app. That is, the parent of "bin" & "lib" folders.
  # For $SAFE > 0, cannot use:  File.expand_path("..", File.dirname(__FILE__))
  ROOT_DIR = "/absolute/path/to/dspace_end"			# CUSTOMISE

  DSPACE_HDL_PREFIX = "123456789"				# CUSTOMISE
  DSPACE_DATASET_COLLECTION_HDL = "#{DSPACE_HDL_PREFIX}/999000"	# CUSTOMISE

  DSPACE_HDL_URL_PART1 = "hdl.handle.net/"	# Handle.net host part with trailing /
  DSPACE_HDL_URL_PART2 = "#{DSPACE_HDL_PREFIX}/" # Handle.net prefix with trailing /
  DSPACE_HDL_URL_REGEX = /			# Regex with () around DSpace ID
    #{Regexp.escape(DSPACE_HDL_URL_PART1)}
    (#{Regexp.escape(DSPACE_HDL_URL_PART2)}.*)
    $
  /x

  REDBOX_HDL_PREFIX = "0000"					# CUSTOMISE

  REDBOX_HDL_URL_PART1 = DSPACE_HDL_URL_PART1	# Handle.net host part with trailing /
  REDBOX_HDL_URL_PART2 = "#{REDBOX_HDL_PREFIX}/" # Handle.net prefix with trailing /
  REDBOX_HDL_URL_REGEX = /			# Regex with () around ReDBox ID
    #{Regexp.escape(REDBOX_HDL_URL_PART1)}
    (#{Regexp.escape(REDBOX_HDL_URL_PART2)}.*)
    $
  /x

  REDBOX_DSPACE_ID_FIELD = "dc.identifier.uri"	# Multivalue field containing ReDBox ID & DSpace ID

  # FasterCSV options for writing CSV to output
  FCSV_OUT_OPTS = {
    :col_sep => ',',
    :headers => true,
    :force_quotes => true,
  }

  # FasterCSV options for reading CSV
  FCSV_IN_OPTS = FCSV_OUT_OPTS

  ############################################################################
  # ENV['HOME'] is tainted; cannot use with $SAFE > 0
  HOME_DIR = "/home/dspacedir"					# CUSTOMISE
  DSPACE_CMD = "#{HOME_DIR}/dspace/bin/dspace"			# CUSTOMISE

  FORCE_OVERWRITE_DSPACE_CSV_RESULT = true

  # DSpace export info
  DS_EXP_CMD = "#{DSPACE_CMD} metadata-export"
  DS_EXP_LOG = "#{ROOT_DIR}/log/dspace_exp.log"
  DS_EXP_LOG2 = "#{ROOT_DIR}/log/dspace_exp.err"

  # DSpace import info
  DS_IMP_IS_YES = false				# Confirm import of Dspace records?
  DS_IMP_ECHO_YES_NO_CMD = "/bin/echo %s" % [DS_IMP_IS_YES ? "y" : "n"]

  DS_IMP_CMD = "#{DSPACE_CMD} metadata-import"
  DS_IMP_USER_EMAIL = "dspaceuser@example.com"			# CUSTOMISE
  DS_IMP_LOG = "#{ROOT_DIR}/log/dspace_imp.log"
  DS_IMP_LOG2 = "#{ROOT_DIR}/log/dspace_imp.err"
end

