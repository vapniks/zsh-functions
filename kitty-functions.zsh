# Handy functions for use with the kitty terminal emulator

# Plot a graph in the kitty terminal using gnuplot, e.g: iplot "sin(x)"
function iplot {
    cat <<EOF | gnuplot
set terminal pngcairo enhanced font 'Fira Sans,10'
set autoscale
set samples 1000
set output '|kitty +kitten icat --stdin yes'
set object 1 rectangle from screen 0,0 to screen 1,1 fillcolor rgb"#fdf6e3" behind
plot $@
set output '/dev/null'
EOF
}
# Display a graph showing FIFO and UNIX interprocess communication in the kitty terminal window.
function lsof-ipc-graph () {
    trap 'sudo pkill lsof && lsof-ipc-graph @' SIGINT
    if [[ ! $@ == *@* ]]; then
        eval "lsof -F ${@}" > /tmp/ipc-graph.lsof
    fi
    cat /tmp/ipc-graph.lsof | lsofgraph | unflatten -l 1 -c 6 | dot -Tjpg > /tmp/lsof-ipc-graph.jpg
    kitty +kitten icat /tmp/lsof-ipc-graph.jpg
}
compdef _lsof lsof-ipc-graph

# Run command lines in other kitty windows.
ksplit () {
    [[ -n $KITTY_WINDOW_ID ]] || {
	print - "Error: not in a kitty window" >&2
	return 1
    }
    emulate -L zsh
    set -o extendedglob
    local USAGE="Usage: $0 [-h] [-r ROWS] [-c COLS] [-l LAYOUT] [-f NUM] \"CMDLINE1\" \"CMDLINE2\"...

Create new windows in the current kitty tab, and run CMDLINE's in each of them, optionally altering their sizes & layout.

Options:
  -h		show this help
  -r ROWS	a comma-separated list indicating No. of rows to try to resize each new window to, \"-\" indicates no change,
                e.g: 20,20,- (try to resize 1st & 2nd windows to 20 rows, don't change 3rd window)
  -c COLS	a comma-separated list indicating No. of columns to try to resize each new window to, \"-\" indicates no change,
                e.g: 50,50,- (try to resize 1st & 2nd windows to 50 columns, don't change 3rd window)
  -l LAYOUT	specify layout to use for window splits (e.g. vertical, horizontal, fat)
  -f NUM	specify window to focus on; 0=initial window (default), 1=1st window, 2=2nd window, etc.
"
    local -a allrows allcols cmdlines focus
    while getopts "hr:c:l:f:" option; do
	case $option in
            (h)
		print -- $USAGE
		return 0
		;;
            (r)
		allrows=("${(s:,:)OPTARG}")
		;;
	    (c)
		allcols=("${(s:,:)OPTARG}")
		;;
	    (l)
		kitty @ goto-layout $OPTARG || return 1
		;;
	    (f)
		focus=$OPTARG
		;;
	esac
    done
    cmdlines=(${@[@]:$OPTIND})
    if [[ -z $cmdlines ]] { print -- $USAGE; return 1 }
    # loop over cmdlines
    local rows cols cmd id ids currows curcols
    local -a ids
    for i in {1..${#cmdlines}}; do
	cmd=${cmdlines[$i]}
	rows=${allrows[$i]}
	cols=${allcols[$i]}
	id=$(kitty @ new-window --cwd $PWD --keep-focus)
	ids+=${id}
	currows=$(kitty @ ls|jq ".[].tabs[].windows[]|select(.id==${id}).lines")
	curcols=$(kitty @ ls|jq ".[].tabs[].windows[]|select(.id==${id}).columns")
	if [[ $rows == [0-9]## ]] { kitty @ resize-window -m id:$id -a vertical -i $((rows-currows)) 2>/dev/null || \
					print - "Could not resize window $id vertically by $((rows-currows))" >&2 }
	if [[ $cols == [0-9]## ]] { kitty @ resize-window -m id:$id -a horizontal -i $((cols-curcols)) 2>/dev/null || \
					print - "Could not resize window $id horizontally by $((cols-curcols))" >&2 }
	# can't use the launch subcommand here because ${cmd} may contain pipes or redirects
	kitty @ send-text -m id:$id "${cmd}\n" 
    done
    # focus the appropriate window
    if [[ -n $focus && $focus -gt 0 ]]; then
	kitty @ focus-window -m id:${ids[${focus}]}
    fi
    # print the IDs of the newly created windows
    print -- ${ids[@]}
    return 0
}

# Launch broot in current window, and fzf for selecting broot command in another window
# This assumes $BROOT contain the path to the broot executable, and $BROOT_CMD_HISTORY contains the path to
# a file containing broot commands.
br2() {
    emulate -L zsh
    set -o extendedglob
    if [[ -n $KITTY_WINDOW_ID ]]; then
	local ID=$(ksplit -r 8 -l vertical -f 1 "cat $BROOT_CMD_HISTORY |fzf --no-multi --preview-window hidden --bind='enter:execute($BROOT --send my_broot -c {}),alt-enter:execute($BROOT --send my_broot -c {};kitty @ focus-window -m id:$KITTY_WINDOW_ID),alt-up:execute($BROOT --send my_broot -c {q} && echo {q} >> $BROOT_CMD_HISTORY)+reload(cat $BROOT_CMD_HISTORY),alt-e:replace-query' --header='ctrl-shift-]=change window,RET=run selection,alt-RET=run selection & change window,alt-e=copy to query,alt-up=copy query to broot & history'; kitty @ close-window --self")
	# make sure ID is a number; sometimes ksplit returns "False" before ID, not sure why
	ID=${ID//(#b)(#s)[^0-9]#([0-9]##)*/${match[1]}} 
	if [[ ${@} == *(--cmd|-c)\ * ]] kitty @ focus-window -m id:$KITTY_WINDOW_ID
        ~/programs/broot --listen my_broot ${=@}
	if [[ -n $(kitty @ ls | jq ".[].tabs[].windows[]|select(.id==${ID})") ]] \
	       kitty @ close-window -m id:$ID
    else
	br ${=@}
    fi
}
