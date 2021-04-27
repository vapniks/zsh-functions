# Show info about symlinks in /dev matching first argument (a regexp)
# subsequent arguments specify what information to show.
# e.g: show-matching-devlinks root devlink devnode mount symlink
show-matching-devlinks() {
    if [[ $# < 1 || $1 == "-h" || $1 == "--help" ]]; then
	echo "Usage: show-matching-devlinks <REGEXP> [DEVLINK|DEVNODE|MOUNT|SYSLINK|..] ...
Show info about symlinks in /dev matching <REGEX>. Fields of info to show can include
those listed above, and any returned by udevadm info."
	return 1
    fi
    local devlink doneheader key devnode
    typeset -a keys devlinks
    typeset -A keyvals
    # Set default column headers if none are given on command line
    if [[ ${#@} -lt 2 ]]; then
	keys=(DEVLINK DEVNODE MOUNT)
    else
	# otherwise use command line args as headers
	keys=(${@[2,-1]})
    fi
    # Find all matching links in /dev
    devlinks=($(find /dev -iregex ".*${1}.*" -type l 2>/dev/null))
    # TODO: Remove links that are prefixes of others (how to do this efficiently?)
    # Get required values for each link:
    for devlink in ${devlinks[@]}; do
	# The node used for mounting (need to find this first so we can use it to find the mountpoint)
	devnode="${$(/bin/udevadm info ${devlink} --query=name --root):-\-\-}"
	for key in ${keys[@]}; do
	    case $key
	    in
		(DEVLINK|devlink)
		    keyvals[$key]="${devlink}"
		    ;;
		(DEVNODE|devnode)
		    keyvals[$key]="${devnode}"
		    ;;
		# the mount point
		(MOUNT|mount) 
		    keyvals[$key]="${$(mount | grep ${devnode} | cut -f 3 -d \ ):-\-\-}"
		    ;;
		# the corresponding link in /sys
		(SYSLINK|syslink)
		    keyvals[$key]="${$(/bin/udevadm info ${devlink} --query=path):-\-\-}"
		    ;;
		# any other user values
		*)
		    keyvals[$key]="${$(/bin/udevadm info ${devlink} | grep -i "$key" | head -n 1 | sed 's/^.*=\(.*\)/\1/'):-\-\-}"
		    ;;
	    esac
	done
	# Print column headers
	if [[ -z "${doneheader}" ]]; then
	    print "${keys[@]}
----------"
	    doneheader=yes
	fi
	# Print values in same order that they were given on the command line
	# (if you try just printing all the values at once they will be printed in alphabetical order)
	for key in "${keys[@]}"; do
	    print -n "${keyvals[$key]} "
	done
	print "\n"
	# format the output into columns
    done 2>/dev/null | column -t 
}
# given a path in /sys print matching entries in the linux source documentation
# e.g: show-sysfs-description /sys/bus/usb/modalias
# if the path doesn't match it will try again after replacing the last directory with .*
# e.g. /sys/bus/.*/modalias, then /sys/.*/modalias then /.*/modalias
# (assumes you have installed the linux sources)
# You can use TAB completion on the filename.
show-sysfs-description() {
    if [[ $# < 1 || $1 == "-h" || $1 == "--help" ]]; then
	echo "Usage: show-sysfs-description <PATH>
where <PATH> is a path to a file in /sys.
Shows linux source documentation for <PATH>."
	return 1
    fi
    emulate -LR zsh
    set -o extendedglob
    local files1 head="${1:h}" tail="${1:t}" kernel="${$(uname -r)%%-*}"
    local docdir="/usr/src/linux-source-${kernel}/linux-source-${kernel}/Documentation/ABI"
    files1=$(eval "grep -E 'What:.*/${tail}[[:space:]]*$' ${docdir}/{stable,testing,obsolete}/*(.r)")
    typeset -aU docfiles=("${(f)files1}")
    docmatches=(${(M)docfiles:#*What:[[:space:]]#${head}*/${tail}})
    if [[ -r $1 ]]; then
	local value="${1}: $(cat ${1})"
	if [[ ${#value} -lt $COLUMNS ]]; then
	    echo "${value}\n"
	fi
    fi
    while [[ -z ${docmatches} && ! ${head} = / ]]; do
	head=${head:h}
	docmatches=(${(M)docfiles:#*What:[[:space:]]#${head}*/${tail}})
    done
    for file in ${docmatches%%:*}; do
	awk "/What:[[:space:]]*${${head:q}//\//\\/}.*\/${tail}/,/^[[:space:]]*\$/{print \$0}" ${file}
    done
}
compdef '_files -P /sys/ -W /sys/' show-sysfs-description
# given arg regexp1 and optional arg regexp2, print linux source sysfs descriptions matching regex1
# and with "What" field (i.e. path in /sys) matching regexp2
search-sysfs-descriptions () {
    if [[ $# < 1 || $1 == "-h" || $1 == "--help" ]]; then
	echo "Usage: search-sysfs-description <REGEX1> [<REGEX2>]
where <REGEX1> is a regexp to match description in sysfs documentation,
and <REGEX2> is an optional regexp to limit results to those matching paths in /sys"
	return 1
    fi
    local files1 desc="${1}" what="${2:-.*}" kernel="${$(uname -r)%%-*}"
    local docdir="/usr/src/linux-source-${kernel}/linux-source-${kernel}/Documentation/ABI"
    awk "BEGIN{flag=0;accum=\"\"}
/^What:[[:space:]]+.*${what//\//\\/}/{accum=\"\";flag=1}
/[^[:space:]]/{if(flag>0){accum=accum \"\n\" \$0}}
/${desc}/{if(flag>0){flag=2}}
/^[[:space:]]*$/{if(flag==2){print accum \"\n----------------\"};accum=\"\";flag=0}"\
	${docdir}/{stable,testing,obsolete}/*(.r)
}

# Search module descriptions for matches to the regexp argument for this function,
# and return all matching info, e.g: search-modules wifi
search-modules() {
    if [[ $# < 1 || $1 == "-h" || $1 == "--help" ]]; then
	echo "Usage: search-modules <REGEXP>
list kernel modules with descriptions matching <REGEXP>"
	return 1
    fi
    matches=()
    for mod in /lib/modules/$(uname -r)/**/*.ko; do
	if modinfo "$mod" | grep -E -i "$*" 2>&1 1>/dev/null; then
	    matches+="$mod"
	fi
    done
    for mod in ${matches}; do
	echo "\033[0;31m$(basename ${mod%%.ko})\033[0m: $(modinfo -d $mod)"
    done
}

# Show command lines used to start processes matching a pattern (argument to this function).
# With no argument show command lines of all processes.
show-cmdline() {
    if [[ $1 == "-h" || $1 == "--help" ]]; then
	echo "Usage: show-cmdline [<REGEX>]
show command-line used to invoke processes matching <REGEXP>"
	return 1
    fi
    ps -feww|grep "$1"|grep -v grep|awk -F" *" '{$1=$2=$3=$4=$5=$6=$7="";print $0}'|sed -e 's/^ *//g' -e 's/ *$//g'
}

# For a given PID (1st arg), show contents of a file (2nd arg) in /proc
# e.g. show-process-info 1234 status
# You can use TAB completion for the PID and filename.
show-process-info() {
    local pid;
    # Parse the arguments
    if [[ $1 == "--help" || $1 == "-h" ]]; then
        echo "Usage: show-process-info <PID> [<FILE>]
       show-process-info [ --help | -h ]

where <PID>  := process id number (can be found with pgrep PROGNAME)
      <FILE> := file containing info to view (use tab completion).

If no arguments are given man page for /proc will be shown
(explaining the contents of the various files)."
        return 1;
    elif [[ $1 =~ ^[0-9]+$ ]]; then
        pid=$1
    elif [[ -n $1 ]]; then
        pid=`pgrep w|head -1|cut -f1 -d" "`
    else
        man proc
        return
    fi
    # Now look at the file
    if [ $2 ]; then
        if [ -f /proc/$pid/$2 ]; then
            sudo cat /proc/$pid/$2; echo ""
        elif [ -d /proc/$pid/$2 ]; then
            sudo ls /proc/$pid/$2
        else
            echo "No file/dir of that name exists in /proc/$pid/"
        fi
    else
        ls /proc/$pid
    fi
}
compdef '_arguments "1:PID:_pids" "2:file:_files -W /proc/${words[$((${CURRENT}-1))]}/"' show-process-info

# Show description of a standard linux directory obtained from hier manpage,
# You can use TAB completion on the directory name.
describedir() {
    if [[ $# < 1 || $1 == "-h" || $1 == "--help" ]]; then
	echo "Usage: describedir [-h|--help] [-a|--all] <DIR>
show description of <DIR> in the standard linux directory hierarchy.
Options:
 -h,--help  show this help
 -a,--all   show hier manpage, i.e. describe all directories"
	return 1
    fi
    if [[ $1 == "-a" || $1 == "--all" ]]; then
	man hier
    fi
    dir=${1-$(pwd)}
    dir=${1%/}
    man --pager=cat hier | sed -rn "\:^[\t ]*${dir}([\t ]|$):,\:^ *$:p" | grep -v '^[ \t]*$'
}
_describedir() {
    dirs=$(man --pager=cat hier|awk '/^[ \t]+\/[a-z/]+/ {print $1}'|sed -r 's/([/a-zA-Z0-9]+).*/\1/')
    compadd ${(f)dirs}
}
compdef _describedir describedir

# If symtree is installed, define this wrapper function to unmangle the symbols
if [[ $(command -v symtree) && $(command -v awk) && $(command -v c++filt) ]]; then
    function show-external-symbols() {
	if [[ $# < 1 || $1 == "-h" || $1 == "--help" ]]; then
	    echo "Usage: show-external-symbols <ELF>...
where each <ELF> arg is an executable binary or shared object (.so) in ELF format."
	    return 1
	fi
	symtree $@|awk '/^[^[:space:]]/{print $0};/^[[:space:]]+/{split($3,symbols,",");printf("%s %s\n",$1,$2);for(i in symbols){print "\t" symbols[i]};print ""}'|c++filt
    }
    compdef '_files' show-external-symbols
fi

describe-runtime-parameter() {
    if [[ $# < 1 || $1 == "-h" || $1 == "--help" ]]; then
	echo "Usage: describe-runtime-parameter <PARAM>
show linux source documentation for kernel runtime parameter <PARAM> (as listed by sysctl)"
	return 1
    fi
    local kver="$(uname -r|cut -d- -f1)"
    local docdir="/usr/src/linux-source-${kver}/linux-source-${kver}/Documentation/sysctl"
    local docfile="${docdir}/${1%%.*}.txt"
    local doctxt=
    case "${1%%.*}"; in
	(kernel|vm)
	    doctxt=$(cat "${docfile}"|\
			 sed -nr "N;/^\n(([^\n]+(,? (&|and)|,)|-) )?([a-z.-_]*\.)?${1##*.}:?/,/^===*/P;D"|\
			 head -n -2|tail -n +2)
	    ;;
	(user)
	    doctxt=$(cat "${docfile}"|\
			 sed -nr "{N;/^- ${1##*.}/,/^- /P;D}"|\
			 head -n -2|tail -n +1)
	    if [[ ! "${doctxt}" =~ $'\n' ]]; then
	    	doctxt=$(cat "${docfile}"|sed -nr "/^- ${1##*.}/,$ p"|tail -n +1)
	    fi
	    ;;
	(net)
	    if [[ "${1}" =~ '\.(ipv4|ipv6|bridge|sctp|unix)\.' ]]; then
		docfile="${docdir%/sysctl}/networking/ip-sysctl.txt"
		doctxt=$(cat "${docfile}"|\
			     sed -nr "\@^(${${${1#*.}#*.}//.//}|${1##*.})\>@,\@^[a-z/]@p"|\
			     head -n -2)
	    else
		doctxt=$(cat "${docfile}"|\
			     sed -nr "/^([a-z._-]+ and )?\<${1##*.}\>/,/^---*/p;N;/^([a-z._-]+ and )?\<${1##*.}\>[^\n]*\n---*/!D"|\
			     head -n -3)
	    fi
	    ;;
	(fs)
	    if [[ "${1}" =~ '\.(binfmt_misc)\.' ]]; then
		doctxt=$(cat "${docdir%/sysctl}/admin-guide/binfmt-misc.rst")
	    elif [[ "${1}" =~ '\.(mqueue)\.' ]]; then
		doctxt=$(cat "${docfile}"|sed -nr "\@^[0-9]\. /proc/sys/fs/mqueue@,\@^[0-9]\.@p"|\
			     head -n -2)
	    elif [[ "${1}" =~ '\.(epoll)\.' ]]; then
		doctxt=$(cat "${docfile}"|sed -nr '\@^[0-9]\. /proc/sys/fs/epoll@,$p')		
	    else
		doctxt=$(cat "${docfile}"|\
			     sed -nr "{N;/^\n([^\n]+(,? (&|and)|,) )?${1#*.}:?/,/^==*/P;D}"|\
			     head -n -2|tail -n +2)
	    fi
	    ;;
    esac
    if [[ -n ${doctxt} ]]; then
	echo ${doctxt}
    else
	echo "No documentation found for ${1}"
    fi
}

describe-device() {
    if [[ $# < 1 || $1 == "-h" || $1 == "--help" ]]; then
	echo "Usage: describe-device [-h|--help] [-a|--all] <DEV>
show linux source documentation for device in /dev
Options:
 -h,--help   show this help
 -a,--all    view documentation for all devices with ${PAGER}"
	return 1
    fi
    local kver="$(uname -r|cut -d- -f1)"
    local doc="/usr/src/linux-source-${kver}/linux-source-${kver}/Documentation/admin-guide/devices.txt"
    if [[ $1 == "-a" || $1 == "--all" ]]; then
	${PAGER} ${doc}
    else
	cat ${doc}|grep ${1}	
    fi
}

