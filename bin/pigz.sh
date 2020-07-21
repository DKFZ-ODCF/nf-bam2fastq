#!/usr/bin/env bash
#
# Copyright (c) 2018 DKFZ.
#
# Distributed under the MIT License (license terms are at https://github.com/TheRoddyWMS/BamToFastqPlugin/blob/master/LICENSE.txt).
#

pigz -p "${compressorThreads:-1}" -c "$@"
