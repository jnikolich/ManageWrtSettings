#!/usr/bin/env bash
#################################################################################
#     File Name           :     managewrt.sh
#     Created By          :     jnikolich
#     Creation Date       :     2015-02-07 19:35
#     Last Modified       :     2015-02-15 13:53
#     Description         :     Manages the NVRAM settings on a router running
#						  :	    a "WRT" style of firmware such as DD-WRT.
#################################################################################
# Copyright (C) 2015 James D. Nikolich
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#################################################################################


### Global Variables (READONLY)
###
readonly PROGNAME=$(basename $0)
readonly PROGDIR=$(readlink -m $(dirname $0))
readonly ARGS="$@"


### Result / Error Codes (READONLY)
###
declare -A ERRCD            # Declare the array and populate it
    ERRCD+=([OK]=0)             # Successful / no error.
    ERRCD+=([GENERAL]=99)       # Generalized, non-specific error.
    ERRCD+=([BADARG]=98)        # Bad argument / parameter.
    ERRCD+=([BADCFG]=97)        # Invalid configuration.
    ERRCD+=([MISMATCH]=96)      # Data or filename mismatch.
    ERRCD+=([MISSING]=95)       # Missing data, file, and/or directory.
    ERRCD+=([UNREACHABLE]=94)   # Device down, unreachable, or unresolvable.
    ERRCD+=([NOTWRITABLE]=93)   # File / directory not writable.
    ERRCD+=([CREATEFAILED]=92)  # Failure to create file / directory.
declare -r ERRCD            # Once array is constructed, lock it down readonly


### function Usage
###
### Emits usage information for this script.
###
### Args:   none
###
### Return: ${ERRCD[OK]}    = OK
###
Usage()
{
    cat <<ENDcat
NAME
    $PROGNAME   - Manage nvram settings on router running a "WRT" style of
	              firmware such as DD-WRT.

SYNOPSIS
    $PROGNAME COMMAND -l LISTNAME -d TARGETDEVICE [OPTION]...

DESCRIPTION
    Manage the nvram settings on router running a "WRT" style of firmware such
	as DD-WRT.  Settings can be grouped into "lists".  Lists are configured via
	drop-in config files.

    This script utilizes SSH to interact with the target router.  It is recom-
    mended that SSH public keys be set up between the system running this script
    and the target router, otherwise use of the script will likely result in
    password prompts being displayed.

    Mandatory arguments to long options are mandatory for short options too.

    COMMAND is (only) one of:
        -c, --compare
                Compare current specified list of settings with what was last
                recorded.

        -v, --view
                Pull current values of the nvram settings in the specified list from
                the router and display them to stdout.

        -r --record
                Pull current values of the nvram settings in the specified list from
                the router and record them to a local savefile.

        -w, --write
                Get the values of the nvram settings in the specified list from a
                local savefile, and write them to the router.  Each setting will be
                written with 'nvram set' and then committed with 'nvram commit'.

    OTHER arguments include:
        -d, --device TARGETDEVICE
                Run againt TARGETDEVICE, which may be either an IP address or a
                resolvable hostname.

        -h, --help
                Display this help-page and exit.

        -l, --list LISTNAME
                Operate on the LISTNAME list of settings.

        -x, --debug
                Enable debugging output to stderr.

ENDcat

    return ${ERRCD[OK]}
}


### function main
###
### Starting point for the actual shell script.  The only global code is the
### invocation of this main function (located at the end of this script).
###
### Args:   none (see "Global Variables (READONLY)" section above)
###
### Return: ${ERRCD[OK]}    = Completed successfully.
###
###         (Any failures will result in non-zero exiting from within this
###          function.)
###
main()
{
    local CONFIGDIR="./config"
    local DATADIR="./data"
    local DATANAMEPREFIX="wrt-savedata_"
    local DATANAMESUFFIX="_$(date '+%Y%m%d%H%M%S').dat"
    local SETTINGLIST="SETTINGLIST"
    local SETTINGVALUE="SETTINGVALUE"

    # Parse and validate all command-line flags and parameters.
    CmdLine $ARGS

    # Check if the target device is up and responsive.
    if ! CheckHostIsUp $DEVICE; then
        ErrExit "Router [$DEVICE] down or unresponsive." ${ERRCD[UNREACHABLE]}
    fi

    # Retrieve list of nvram setting names from config file
    SETTINGLIST='SETTINGLIST'
    LoadNVRamSet $CONFIGDIR $LISTNAME $SETTINGLIST

    # Perform the command specified on the command-line
    case $COMMAND in
        v)  # Iterate through the list, retrieving and displaying each setting
            # from the # target device
            for i in ${SETTINGLIST[@]}
            do
                SETTINGVALUE="SETTINGVALUE" # Init var to hold upvar'ed results
                GetNVRamSetting $i $DEVICE $SETTINGVALUE
                printf "$i=\"$SETTINGVALUE\"\n"
            done
            ;;
        r)  # Initialize a new Record data file, and then iterate through the
            # list, retrieving each setting and appending it to the data file
            PrepareDirWritable "$DATADIR"
            local TMPFILENAME=$(mktemp --tmpdir "$PROGNAME.tmp.XXXXXXXX")
            DebugPrint "Using tmpfile \'$TMPFILENAME\'."
            for i in ${SETTINGLIST[@]}
            do
                SETTINGVALUE="SETTINGVALUE" # Init var to hold upvar'ed results
                GetNVRamSetting $i $DEVICE $SETTINGVALUE
                printf "$i=\"$SETTINGVALUE\"\n" >>$TMPFILENAME
                DebugPrint "Wrote [$i=\"$SETTINGVALUE\"].\n"
            done
            local RECORDFILENAME="${DATADIR}/${DATANAMEPREFIX}${LISTNAME}${DATANAMESUFFIX}"
            mv $TMPFILENAME $RECORDFILENAME
            printf "$RECORDFILENAME created\n"
            ;;
        c)  # Iterate through the list, retrieving each setting and comparing it
            # to what's in the most recent saved file.
            local COMPAREFILENAME=$(ls -t1 ${DATADIR}/${DATANAMEPREFIX}${LISTNAME}*.dat 2>/dev/null | head -n 1)
            if [[ ! -f "$COMPAREFILENAME" ]];
            then
                ErrExit "Unable to find a save file for list [$LISTNAME]." ${ERRCD[MISSING]}
            fi
            local TMPFILENAME=$(mktemp --tmpdir "$PROGNAME.tmp.XXXXXXXX")
            DebugPrint "Using tmpfile \'$TMPFILENAME\'."
            for i in ${SETTINGLIST[@]}
            do
                SETTINGVALUE="SETTINGVALUE" # Init var to hold upvar'ed results
                GetNVRamSetting $i $DEVICE $SETTINGVALUE
                printf "$i=\"$SETTINGVALUE\"\n" >>$TMPFILENAME
            done
            #git diff --word-diff "$TMPFILENAME" "$COMPAREFILENAME"
            #diff "$TMPFILENAME" "$COMPAREFILENAME"
            git diff --color-words "$TMPFILENAME" "$COMPAREFILENAME"
            ;;
        w)  ErrExit "Write operation not yet implemented." ${ERRCD[OK]} ;;
    esac

    return ${ERRCD[OK]}
}


### function CheckHostIsUp
###
### Checks (via ping) whether a host is up and reachable or not.
###
### Args:   $1  = Hostname / IP
###
### Return: ${ERRCD[OK]}            = Host up and reachable.
###         ${ERRCD[UNREACHABLE]}   = Host is down, unreachable or unresolvable.
###
function CheckHostIsUp
{
    local HOST=$1
    local RETVAL=${ERRCD[OK]}

    DebugPrint "invoked with args [$@]"

    ping -c 1 $HOST >/dev/null 2>&1
    RETVAL=$?

    if [ $RETVAL -ne 0 ]; then
        RETVAL=${ERRCD[UNREACHABLE]}
    fi

    return ${ERRCD[OK]}
}


### function CmdLine
###
### Processes the command-line options and arguments specified when this
### script was invoked.
###
### Args:   $1 = All arguments provided to the script at invocation
###
### Return: ${ERRCD[OK]}        = Successfully parsed / validated all arguments.
###
### Exits:  This function will terminate the script upon encountering any of
###         the following error conditions:
###
###         ${ERRCD[BADARG]}    = Invalid / missing argument.
###
function CmdLine()
{
    local NEWARGS
    local ARG 

    for ARG
    do
        local DELIM=""
        case $ARG in
            --compare)  NEWARGS="${NEWARGS}-c " ;;
            --view)     NEWARGS="${NEWARGS}-v " ;;
            --record)   NEWARGS="${NEWARGS}-r " ;;
            --write)    NEWARGS="${NEWARGS}-w " ;;
            --device)   NEWARGS="${NEWARGS}-d " ;;
            --help)     NEWARGS="${NEWARGS}-h " ;;
            --list)     NEWARGS="${NEWARGS}-l " ;;
            --debug)    NEWARGS="${NEWARGS}-x " ;;
            *)          [[ "${ARG:0:1}" == "-" ]] || DELIM="\""
                        NEWARGS="${NEWARGS}${DELIM}${ARG}${DELIM} "
                        ;;
        esac
    done

    # Reset positional arguments to the short options
    eval set -- $NEWARGS

    while getopts "cvrwd:hl:x" OPTION
    do
        case $OPTION in
            c|v|r|w)
                    readonly COMMAND=$OPTION 2>/dev/null
                    if [[ $? -ne "0" ]];
                    then
                        ErrExit "Cannot mix 'compare, 'view', 'record', or 'write'." ${ERRCD[BADARG]}
                    fi
                    ;;
            d)
                    readonly DEVICE=$OPTARG
                    ;;
            h)
                    Usage
                    exit 0
                    ;;
            l)
                    readonly LISTNAME=$OPTARG
                    ;;
            x)
                    readonly DEBUG=1
                    ;;
        esac
    done

    DebugPrint "\$NEWARGS = [$NEWARGS]"

    if [[ "blah$COMMAND" == "blah" ]]; then
        ErrExit "Must specifiy one of 'compare, 'view', 'record', or 'write'." ${ERRCD[BADARG]}
    elif [[ "blah$DEVICE" == "blah" ]]; then
        ErrExit "Must specify a target device." ${ERRCD[BADARG]}
    elif [[ "blah$LISTNAME" == "blah" ]]; then
        ErrExit "Must specify a list." ${ERRCD[BADARG]}
    fi
}


### function DebugPrint
###
### Emits the specified info to stderr only if debugging has been enabled
### (i.e. when $DEBUG=1)
###
### Args:   $@ = all arguments will be included in the debugging output
###
### Return: ${ERRCD[OK]}    = OK.
###
### Note: $FUNCNAME is a bash builtin array specifying the names of all shell
###       functions currently in the execution call stack.
###       ${FUNCNAME[0]} = current function name
###       ${FUNCNAME[1]} = name of whatever called this function.
###         ...
###
DebugPrint()
{
    local MSG=$@
    [[ DEBUG -eq 1 ]] && printf "${FUNCNAME[1]}() : $MSG\n" 1>&2
    return ${ERRCD[OK]}
}

### function ErrExit
###
### Emits the specified error message and then terminates the script with the
### specified error code.
###
### If no error message is supplied then a general message will be emitted.
### If no error-code is supplied than a general error-code is used.
###
### Args:   $1 = Error message to emit
###         $2 = Error code to terminate the script with
###
### Ret:    none (terminates script with error code.)
###
ErrExit()
{
    DebugPrint "invoked with args [$@]"

    local ERRMSG=${1:-Error occurred}
    local EXITCODE=${2:-1}

    printf "$ERRMSG\n" 1>&2
    exit $EXITCODE
}


### function GetNVRamSetting
###
### Retrieves a single NVRam setting from the specified device and returns
### it in the specified return-value argument.
###
### Args:   $1 = Name of NVRam setting to be retrieved
###         $2 = Name of device to be queried
###         $3 = Reference to up-scope variable that will be set to contain
###              the value of the queried NVRam setting.
###
### Ret:     0 = OK
###         99 = Missing / invalid argument
###
GetNVRamSetting()
{
    local SETTINGNAME=${1:-notspecified}
    local DEVICENAME=${2:-notspecified}
    local GOTTENSETTING

    DebugPrint "invoked with args [$@]"

    # Do some basic argument-checking
    if [[ $SETTINGNAME == 'notspecified'    ]]      \
    || [[ $DEVICENAME == 'notspecified'     ]]; then
        return ${ERRCD[BADARG]}
    fi

    DebugPrint "Querying router [$DEVICENAME] for setting '$SETTINGNAME'"
    GOTTENSETTING="$(ssh -l root -q $DEVICENAME "nvram get $SETTINGNAME")"
    local "$3" && UpVar $3 "$GOTTENSETTING"

    return ${ERRCD[OK]}
}


### LoadNVRamSet
###
### Looks for a config-file containing the specified NVRAM list-name, and loads
### the names of all NVRAM settings that are included in that list.  The list
### is returned to the caller by way of an upvar'ed array.
###
### Args:   $1 = Configuration directory to check within (absolute or relative)
###         $2 = nvram list-name to search for.
###         $3 = Reference to up-scope array variable that will be set to contain
###              all nvram setting names associated with with this list-name.
###
### Ret:     0 = OK
###         98 = Missing / invalid argument
###         97 = Config file containing specified list-name not found
###         96 = Config file's filename mismatches list-name within the file
###
function LoadNVRamSet
{
    local CFGDIR=${1:-notspecified}
    local LIST=${2:-notspecified}
    local CFGNAMEPREFIX="wrt-listcfg__"
    local CFGNAMESUFFIX=".conf"
    local CFGFILENAME="notspecified"

    DebugPrint "invoked with args [$@]"

    # Variables that are locally declared here, but whose values are sourced in
    # from a configuration file
    local NVRAMLISTNAME
    declare -a NVRAMSETTINGLIST

    # Do some basic argument-checking
    if [[ $CFGDIR == 'notspecified'     ]]      \
    || [[ $LIST == 'notspecified'   ]]; then
        ErrExit "Missing argument when calling LoadNVRamSet()." ${ERRCD[BADARG]}
    fi

    # Verify config dir exists, construct full filename, and verify file exists
    # (and is an actual file)
    if [[ ! -d $CFGDIR ]]; then
        ErrExit "Config dir \'$CFGDIR\' missing." ${ERRCD[MISSING]}
    fi
    CFGFILENAME="$CFGDIR/${CFGNAMEPREFIX}${LIST}${CFGNAMESUFFIX}"
    if [[ ! -f $CFGFILENAME ]]; then
        ErrExit "Config file for list [$LIST] not found." ${ERRCD[BADCFG]}
    fi

    # Source the config file
    . $CFGFILENAME

    # Do a quick filename / setname sanity check
    if [[ $LIST != $NVRAMLISTNAME ]]; then
        ErrExit "Config filename \'$CFGFILENAME\' doesn't match contents \'$NVRAMLISTNAME\'" ${ERRCD[MISMATCH]}
    fi

    # upvar the loaded set into the return-variable
    local "$3" && UpVar $3 "${NVRAMSETTINGLIST[@]}"

    return ${ERRCD[OK]}
}


### function PrepareDirWritable
###
### Prepares a writable directory for use by this script.  If a directory
### matching the specified name is found, then it is tested to see if it is
### writable. If no matching directory is found then an attempt is made to
### create it, which will also result in it being writable by-default.
###
### Args:   $1  = Name (relative or absolute) of data-directory to prepare.
###
### Return: ${ERRCD[OK]}            = Directory present/created and writable.
###         ${ERRCD[BADARG]}        = Bad or missing directory name.
###         ${ERRCD[NOTWRITABLE]}   = Directory present but not writable.
###         ${ERRCD[CREATEFAILED]}  = Directory not present and create failed.
###
function PrepareDirWritable()
{
    local DIRNAME="$1"
    local RETVAL=0

    DebugPrint "invoked with args [$@]"

    # Verify a directory name was provided  Return error if not.
    if [[ "blah$DIRNAME" == "blah" ]]; then
        ErrExit "Missing argument when calling PrepareDirWritable()." ${ERRCD[BADARG]}
    fi

    # Test if directory is writable (and therefore present). Exit if
    # true.  Otherwise if directory is present then it must not be
    # writable - exit w/err.
    if [[ -w $DIRNAME ]]; then
        return ${ERRCD[OK]}
    elif [[ -d $DIRNAME ]]; then
        ErrExit "Data directory \'$DIRNAME\' not writable." ${ERRCD[NOTWRITABLE]}
    fi

    # Directory not present.  Attempt to create specified directory (absolute
    # or relative path).  Return failure if create failed.
    mkdir -p $DIRNAME 2>/dev/null
    RETVAL=$?
    DebugPrint "RETVAL=[$RETVAL]"
    if [[ $RETVAL -ne 0 ]]; then
        ErrExit "Error creating data directory \'$DIRNAME\'." ${ERRCD[CREATEFAILED]}
    fi

    # Create succeeded.
    return ${ERRCD[OK]}
}


### function UpVar
###
### Assign variable one scope above the caller
###
### Usage:  local "$1" && UpVar $1 "value(s)"
###
### Args:   $1 = Variable name to assign value to
###         $* = Value(s) to assign.  If multiple values, an array is assigned,
###              otherwise a single value is assigned.
###
### NOTE:   For assigning multiple variables, use 'UpVars'.  Do NOT use multiple
###         'UpVar' calls, since one 'UpVar' call might reassign a variable to
###         be used by another 'UpVar' call.
###
### Example:    f() { local b; g b; echo $b; }
###             g() { local "$1" && UpVar $1 bar; }
###             f  # Ok: b=bar
###
### Gratefully derived from http://www.fvue.nl/wiki/Bash:_Passing_variables_by_reference
###
UpVar()
{
    local VARNAME=$1

    DebugPrint "invoked with args [$@]"

    if unset -v "$1"; then           # Unset & validate varname
        if (( $# == 2 )); then
            DebugPrint "UpVar'ing a single value into \$$VARNAME"
            eval $1=\"\$2\"          # Return single value
        else
            DebugPrint "UpVar'ing an array into \$$VARNAME"
            eval $1=\(\"\${@:2}\"\)  # Return array
        fi
    fi
}


main
exit ${ERRCD[OK]}
