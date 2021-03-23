#!/usr/bin/env bash
#
# Copyright (c) 2021 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/DKFZ-ODCF/nf-bam2fastq/blob/master/LICENSE.txt).
#

source "bashLib.sh"

WORKFLOWLIB___SHELL_OPTIONS=$(set +o)
set +o verbose
set +o xtrace

# Accessor to retrieve global temporary directory setting.
tmpDir() {
  echo "${tmpDir:-tmp}"
}

normalizeBoolean() {
    if [[ "${1:-false}" == "true" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

isDebugSet() {
    normalizeBoolean "${debug:-false}"
}

mkFifo() {
    local fifo="${1:?No fifo name given}"
    if [[ ! -p "$fifo" ]]; then
        mkfifo "$fifo"
    fi
}

mbuf () {
    local bufferSize="$1"
    shift
    assertNonEmpty "$bufferSize" "No buffer size defined for mbuf()" || return $?
    "$MBUFFER_BINARY" -m "$bufferSize" -q -l /dev/null ${@}
}

lockFileName() {
  local resourceName="${1:?No resource name given}"
  echo $(tmpDir)/"$resourceName.lock"
}

lockResource() {
  local resourceName="${1:?No resource name given}"
  filelock $(lockFileName "$resourceName")
}

unlockResource() {
  local resourceName="${1:?No resource name given}"
  local lockFileName=$(lockFileName "$resourceName")
  if [[ ! -d "$lockFileName" ]]; then
      throw "Trying to remove non-directory lock: '$lockFileName'" 1
  fi
  rmdir "$lockFileName"
}

tmpFiles() {
  echo "$(tmpDir)/tmpFiles"
}

registerTmpFile() {
    local tmpFile="${1:?No temporary file name to register}"
    lockResource "tmpFiles"
    echo "$tmpFile" >> $(tmpFiles)
    unlockResource "tmpFiles"
}

## Always return a default read group, in case the file has no read groups annotated. This ensures that Roddy will create appropriate directories.
## But we need to make sure that there is no 'default' group already in the BAM header!
assertNoDefaultReadGroup() {
    declare -a groups=($@)
    if (echo "${groups[@]}" | grep -w default); then
        echo "BAM mentions a 'default' read group in its header. This clashes with the default read-group name in Biobambam"
        exit 2
    fi
}

getReadGroups() {
  local bamFile="${1:?No BAM file given}"
  declare -a groups=$($SAMTOOLS_BINARY view -H "${bamFile:?No input file given}" | grep -P '^@RG\s' | perl -ne 's/^\@RG\s+ID:(\S+).*?$/$1/; print' 2> /dev/null)
  assertNoDefaultReadGroup "${groups[@]}"
  echo "${groups[@]}"
  echo "default"
}

composeFastqFiles() {
  local outputDir="${1:?No output directory given}"
  local fastqSuffix=${2:?No FASTQ suffix given}
  shift 2
  declare -a readGroups=( "$@" )
  declare -a readFileTypes=("R1" "R2" "U1" "U2" "S")
  for rg in "${readGroups[@]}"; do
    for rft in "${readFileTypes[@]}"; do
      echo "$outputDir/${rg}_${rft}.${fastqSuffix}"
    done
  done
}

# Bash sucks. An empty array does not exist! So if there are no tempfiles/pids, then there is no array and set -u will result an error!
# Therefore we put a dummy value into the arrays and have to take care to remove the dummy before the processing.
# The dummy contains a random string to avoid collision with possible filenames (the filename 'dummy' is quite likely).
ARRAY_ELEMENT_DUMMY=$(mktemp -u "_dummy_XXXXX")

setUp_BashSucksVersion() {
    mkdir -p "$(tmpDir)"

    lockResource "tmpFiles"
    echo "$ARRAY_ELEMENT_DUMMY" > $(tmpFiles)
    unlockResource "tmpFiles"

    # Remove all registered temporary files upon exit
    trap "cleanUp_BashSucksVersion; rm \"$(tmpFiles)\"; rmdir \"$(tmpDir)\"" EXIT
}
cleanUp_BashSucksVersion() {
    lockResource "tmpFiles"
    declare -a tmpFiles=( $(tac $(tmpFiles)) )
    if [[ $(isDebugSet) == "false" && -v tmpFiles && ${#tmpFiles[@]} -gt 1 ]]; then
        for f in ${tmpFiles[@]}; do
            if [[ "$f" == "$ARRAY_ELEMENT_DUMMY" ]]; then
                continue
            elif [[ -d "$f" ]]; then
                rmdir "$f"
            elif [[ -e "$f" ]]; then
                rm -f "$f"
            fi
        done
        echo "$ARRAY_ELEMENT_DUMMY" > $(tmpFiles)
    fi
    unlockResource "tmpFiles"
}

# These versions only works with Bash >4.4. Prior version do not really declare the array variables with empty values and set -u results in error message.
setUp() {
    mkdir -p "$(tmpDir)"

    lockResource "tmpFiles"
    cat /dev/null > $(tmpFiles)
    unlockResource "tmpFiles"

     # Remove all registered temporary files upon exit
    trap "cleanUp; rm \"$(tmpFiles)\"; rmdir \"$(tmpDir)"\" EXIT
}
cleanUp() {
    lockResource "tmpFiles"
    declare -a tmpFiles=( $(tac $(tmpFiles)) )
    if [[ $(isDebugSet) == "false" && -v tmpFiles && ${#tmpFiles[@]} -gt 0 ]]; then
        for f in "${tmpFiles[@]}"; do
            if [[ -d "$f" ]]; then
                rmdir "$f"
            elif [[ -e "$f" ]]; then
                rm "$f"
            fi
        done
        cat /dev/null > $(tmpFiles)
    fi
    unlockResource "tmpFiles"
}

# Used to wait for a file expected to appear within the next moments. This is necessary, because in a network filesystems there may be latencies
# for synchronizing the filesystem between nodes.
waitForFile() {
    local file="${1:?No file to wait for}"
    local waitCount=0
    while [[ ${waitCount} -lt 3 && ! (-r "$file") ]]; do sleep 5; waitCount=$((waitCount + 1)); echo $waitCount; done
    if [[ ! -r "$file" ]]; then
        echo "The file '$file' does not exist or is not readable."
        exit 200
    else
        return 0
    fi
}

# Ensure that there is a directory with the given path name. This won't check whether the directory exists or is
# accessible. If the directory does not exist and cannot get created this should end with the exit code and error
# message `mkdir` uses to indicate a problem.
ensureDirectoryExists() {
    local pathname="${1:?No directory name given}"
    if [[ ! -e "$pathname" ]]; then
        mkdir -p "$pathname"
    fi
}

tmpBaseFile() {
    local name="${1:?No filename given}"
    echo $(tmpDir)/$(basename "$name")
}

createFifo() {
    local name="${1:?No FIFO name given}"
    mkFifo "$name"
    registerTmpFile "$name"
    echo "$name"
}

createTmpFile() {
    local name="${1:?No tempfile name given}"
    registerTmpFile "$name"
    echo "$name"
}

md5File() {
   local md5File="${1:?No MD5 filename given}"
   local inputFile="${2:-/dev/stdin}"
   local outputFile="${3:-/dev/stdout}"

   assertNonEmpty "$inputFile"  "inputFile not defined" || return $?
   assertNonEmpty "$outputFile" "outputFile not defined" || return $?

   local md5Fifo=$(tmpBaseFile "$md5File")".fifo"
   createFifo "$md5Fifo"

   cat "$md5Fifo" \
        | md5sum \
        | cut -d ' ' -f 1 \
        > "$md5File" \
        & md5Pid=$!

   cat "$inputFile" \
        | mbuf 10m \
            -f -o "$md5Fifo" \
            -f -o "$outputFile" \
        & mbufPid=$!

    wait "$md5Pid" "$mbufPid"
}

checkMd5Files() {
    local referenceFile="${1}"
    assertNonEmpty "$referenceFile" "No reference MD5 file given"
    local queryMd5File="$2"
    assertNonEmpty "$queryMd5File" "No query MD5 file given"
    referMd5=$(cat "$referenceMd5File" | cut -f 1 -d ' ')
    queryMd5=$(cat "$queryMd5File" | cut -f 1 -d ' ')
    if [[ "$referMd5" != "$queryMd5" ]]; then
        throw 10 "Reference MD5 in '$referenceMd5File' did not match actual MD5"
    fi
}

compressionOption() {
    if [[ "${sortCompressor:-}" != "" ]]; then
        echo "--compress-program" $sortCompressor
    fi
}

fastqLinearize() {
    paste - - - -
}

fastqDelinearize() {
    "$PERL_BINARY" -aF\\t -lne '$F[0] =~ s/^(\S+?)(?:\/\d)?(?:\s+.*)?$/$1/o; print join("\n", @F)'
}

sortLinearizedFastqStream() {
    local tmpDir="${1:?No temporary directory prefix given}"
    LC_ALL=C sort -t : -k 1d,1 -k 2n,2 -k 3d,3 -k 4n,4 -k 5n,5 -k 6n,6 -k 7n,7 -T "$tmpDir" $(compressionOption) --parallel=${sortThreads:-1} -S "${sortMemory:-100m}"
}

eval "$WORKFLOWLIB___SHELL_OPTIONS"
