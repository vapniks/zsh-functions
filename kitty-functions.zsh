# Handy functions for use with the kitty terminal emulator
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

function lsof-ipc-graph () {
    trap 'sudo pkill lsof && show-lsof-ipc-graph @' SIGINT
    if [[ ! $@ == *@* ]]
    then
        eval "lsof -F ${@}" > /tmp/ipc-graph.lsof
    fi
    cat /tmp/ipc-graph.lsof | lsofgraph | unflatten -l 1 -c 6 | dot -Tjpg > /tmp/lsof-ipc-graph.jpg
    kitty +kitten icat /tmp/lsof-ipc-graph.jpg
}
compdef _lsof lsof-ipc-graph
